const express = require('express');
const crypto = require('crypto');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const { whatsappLimiter } = require('../middleware/rateLimiter');
const logger = require('../logger');
const { generateReceiptToken, RECEIPT_BASE } = require('../receiptToken');
const { stripBillPrefix } = require('../billNumber');
const { normalisePhone, sendReceiptLink } = require('../whatsapp');
const { broadcast } = require('../realtime');
const { attachCharges } = require('../charges');
const { canonicalPhone, billPhoneMatch } = require('../customers');
const {
  DUE, round2, parseCollections, checkCollections, recordCreditPayments, attachCreditInfo,
} = require('../creditPayments');

const router = express.Router();

// Credit (giving items on udhaari) and settlement are money operations, so
// they're limited to cashiers and owners — the same roles allowed to finalize
// a bill and take payment. Servers cannot give or settle credit.
function cashierOrOwner(req, res, next) {
  if (req.user.role !== 'cashier' && req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only a cashier or owner can settle credit' });
  }
  next();
}

const VALID_PAYMENT_MODES = ['cash', 'upi', 'card', 'other'];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The single Payment Receipt for one /settle call: one line per bill paid —
 * its number, date, net payable, what was paid on it NOW and what it still
 * owes after. [bills] are the re-read bills (with `due`); [paidNow] maps a
 * lowercased bill id to the amount just paid.
 */
function settlementPayload(id, receiptToken, mode, bills, paidNow) {
  const lines = bills.map((b) => ({
    bill_id: b.id,
    bill_number: b.bill_number,
    bill_date: b.finalized_at || b.created_at,
    bill_total: round2(Number(b.total) - Number(b.discount_amount || 0) + Number(b.round_off || 0)),
    paid: round2(paidNow.get(String(b.id).toLowerCase()) || 0),
    due: round2(Math.max(0, Number(b.due) || 0)),
  })).filter((l) => l.paid > 0);
  return {
    id,
    receipt_token: receiptToken,
    created_at: new Date().toISOString(),
    mode,
    total: round2(lines.reduce((s, l) => s + l.paid, 0)),
    customer_name: bills[0]?.customer_name || null,
    customer_phone: bills[0]?.customer_phone || null,
    lines,
  };
}

// What an unpaid bill still owes is DUE (src/creditPayments.js): its credit
// part — a split bill's credit_amount, else its Net Payable with round-off —
// less whatever has been paid against it so far (credit_payments).

// GET /api/credit/customers
// Debtor list for the Credit tab: one row per customer, with their outstanding
// total and unpaid-bill count. Most-owed first.
//
// Grouped by the CANONICAL number (migration 047): the billing app saves
// 9876543210 while the online store saves 919876543210 — the same person must
// be one debtor, not two. customer_phone is returned in that 10-digit form;
// the bills/summary routes below accept it (or any format) and match every
// stored variant.
router.get('/customers', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      // Each bill's due is worked out in the inner query and summed outside:
      // DUE contains a subquery, and SQL Server refuses SUM() over one
      // (error 130) — which failed this list and hid the Credit tab.
      .query(`
        SELECT
          x.customer_phone,
          MAX(x.customer_name) AS customer_name,
          COUNT(*)             AS unpaid_count,
          SUM(x.due)           AS outstanding,
          MAX(x.created_at)    AS last_bill_at
        FROM (
          SELECT dbo.canonical_phone(b.customer_phone) AS customer_phone,
                 b.customer_name, b.created_at, ${DUE} AS due
          FROM bills b
          WHERE b.business_id = @business_id
            AND b.payment_status = 'unpaid'
            AND b.status = 'finalized'
        ) x
        GROUP BY x.customer_phone
        ORDER BY outstanding DESC
      `);
    return res.json(result.recordset);
  } catch (err) {
    logger.error({ err }, 'credit customers list error');
    return res.status(500).json({ error: 'Failed to load credit customers' });
  }
});

// GET /api/credit/customers/:phone/bills
// All unpaid credit bills for one customer (by phone), newest first, each with
// its line items so the client can preview/merge them.
router.get('/customers/:phone/bills', requireAuth, async (req, res) => {
  const phone = canonicalPhone(req.params.phone);
  if (!phone) return res.status(400).json({ error: 'phone is required' });

  try {
    await poolConnect;
    const billsResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('phone',       sql.NVarChar(20),     phone)
      .query(`
        SELECT b.id, b.bill_number, b.customer_name, b.customer_phone,
               b.subtotal, b.tax_amount, b.discount_amount, b.charges_amount,
               b.additional_charges, b.total, b.round_off,
               b.payment_mode, b.payment_status, b.status,
               b.credit_amount, ${DUE} AS due,
               b.created_at, b.finalized_at, b.receipt_token
        FROM bills b
        WHERE b.business_id = @business_id
          AND ${billPhoneMatch('@phone')}
          AND b.payment_status = 'unpaid'
          AND b.status = 'finalized'
        ORDER BY b.created_at DESC
      `);

    const bills = billsResult.recordset;
    if (bills.length === 0) return res.json([]);

    // Fetch all line items for these bills in one query, then attach.
    const ids = bills.map((b) => b.id);
    const params = ids.map((_, i) => `@id${i}`).join(', ');
    const itemsReq = pool.request();
    ids.forEach((id, i) => itemsReq.input(`id${i}`, sql.UniqueIdentifier, id));
    const itemsResult = await itemsReq.query(`
      SELECT bill_id, item_name, quantity, unit_price, tax_rate, line_total, discount_amount
      FROM bill_items
      WHERE bill_id IN (${params})
    `);
    const byBill = {};
    for (const it of itemsResult.recordset) {
      (byBill[it.bill_id] ||= []).push(it);
    }
    for (const b of bills) attachCharges(b).items = byBill[b.id] || [];

    // What has been paid against each so far, for the "₹300 paid in …" lines.
    return res.json(await attachCreditInfo(bills));
  } catch (err) {
    logger.error({ err }, 'credit customer bills error');
    return res.status(500).json({ error: 'Failed to load customer bills' });
  }
});

// GET /api/credit/customers/:phone/summary
// Lightweight outstanding-credit summary for one phone — used on the billing
// screen to show "previous credit due" as the cashier types the customer's
// number. Returns the total, count, and each unpaid bill with what it owes —
// the billing screen lists them one line each, to collect in full or in part.
router.get('/customers/:phone/summary', requireAuth, async (req, res) => {
  const phone = canonicalPhone(req.params.phone);
  if (!phone) return res.status(400).json({ error: 'phone is required' });

  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('phone',       sql.NVarChar(20),     phone)
      .query(`
        SELECT b.id, b.bill_number, b.created_at, ${DUE} AS due
        FROM bills b
        WHERE b.business_id = @business_id
          AND ${billPhoneMatch('@phone')}
          AND b.payment_status = 'unpaid'
          AND b.status = 'finalized'
        ORDER BY b.created_at
      `);
    const rows = result.recordset;
    const outstanding = rows.reduce((s, r) => s + Number(r.due), 0);
    return res.json({
      outstanding,
      unpaid_count: rows.length,
      bill_ids: rows.map((r) => r.id),
      bills: rows.map((r) => ({
        id: r.id, bill_number: r.bill_number, created_at: r.created_at, due: round2(r.due),
      })),
    });
  } catch (err) {
    logger.error({ err }, 'credit summary error');
    return res.status(500).json({ error: 'Failed to load credit summary' });
  }
});

// POST /api/credit/settle
// Pays credit bills from the Credit tab, in full or in part, in one mode.
// Body: { payments: [{ bill_id, amount }], payment_mode } — or the older
// { bill_ids: [...], payment_mode }, which pays each bill everything it owes.
// A bill paid down to 0 is settled (payment_status 'paid'); a part payment
// leaves it unpaid with less owing. All or nothing. Returns the bills with
// their payment history, so the client can print each one.
router.post('/settle', requireAuth, cashierOrOwner, async (req, res) => {
  const { bill_ids, payments, payment_mode } = req.body || {};

  if (!payment_mode || !VALID_PAYMENT_MODES.includes(payment_mode)) {
    return res.status(400).json({ error: `payment_mode must be one of: ${VALID_PAYMENT_MODES.join(', ')}` });
  }
  let wanted;
  if (payments !== undefined) {
    const parsed = parseCollections(payments);
    if (parsed.error) return res.status(400).json({ error: parsed.error });
    wanted = parsed.list;
  } else {
    if (!Array.isArray(bill_ids) || bill_ids.length === 0) {
      return res.status(400).json({ error: 'bill_ids array is required and must not be empty' });
    }
    if (bill_ids.some((id) => typeof id !== 'string' || !UUID_RE.test(id))) {
      return res.status(400).json({ error: 'bill_ids must all be valid UUIDs' });
    }
    // null amount = everything the bill owes (checkCollections fills it in).
    wanted = bill_ids.map((id) => ({ bill_id: id, amount: null }));
  }
  if (wanted.length === 0) {
    return res.status(400).json({ error: 'payments must list at least one bill' });
  }
  const ids = wanted.map((p) => p.bill_id);

  try {
    await poolConnect;
    const transaction = pool.transaction();
    await transaction.begin();
    // One settlement per call: the single receipt that lists every bill paid
    // here (migration 052).
    const settlementId = crypto.randomUUID();
    const receiptToken = generateReceiptToken();
    let paidNow;
    try {
      // Locks the bills and checks no amount exceeds what is owed. A bill that
      // is already paid, voided or another shop's fails the whole batch.
      const checked = await checkCollections(transaction.request(), req.user.business_id, wanted);
      if (checked.error) {
        await transaction.rollback();
        return res.status(409).json({ error: checked.error });
      }
      paidNow = new Map(checked.list.map((p) => [p.bill_id.toLowerCase(), p.amount]));
      // The customer is the bills' customer — all of a Credit-tab customer's
      // bills share one (canonical) phone, so the first bill's details do.
      await transaction.request()
        .input('id',          sql.UniqueIdentifier, settlementId)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('token',       sql.NVarChar(16),     receiptToken)
        .input('mode',        sql.NVarChar(20),     payment_mode)
        .input('total',       sql.Decimal(10, 2),   round2(checked.list.reduce((s, p) => s + p.amount, 0)))
        .input('user_id',     sql.UniqueIdentifier, req.user.user_id || null)
        .input('first_bill',  sql.UniqueIdentifier, checked.list[0].bill_id)
        .query(`
          INSERT INTO credit_settlements
            (id, business_id, receipt_token, customer_name, customer_phone, mode, total, created_by_user_id)
          SELECT @id, @business_id, @token, b.customer_name, b.customer_phone, @mode, @total, @user_id
          FROM bills b WHERE b.id = @first_bill AND b.business_id = @business_id
        `);
      await recordCreditPayments(transaction, req.user.business_id,
        checked.list.map((p) => ({ bill_id: p.bill_id, mode: payment_mode, amount: p.amount })),
        null, settlementId);
      await transaction.commit();
    } catch (inner) {
      try { await transaction.rollback(); } catch (_) {}
      throw inner;
    }

    // The bills again, with items and payment history, for their receipts.
    const params2 = ids.map((_, i) => `@id${i}`).join(', ');
    const billsReq = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);
    ids.forEach((id, i) => billsReq.input(`id${i}`, sql.UniqueIdentifier, id));
    const billsResult = await billsReq.query(`
      SELECT b.id, b.bill_number, b.customer_name, b.customer_phone,
             b.subtotal, b.tax_amount, b.discount_amount, b.charges_amount,
             b.additional_charges, b.total, b.round_off,
             b.payment_mode, b.payment_status, b.settled_at, b.settled_payment_mode,
             b.credit_amount, ${DUE} AS due, b.created_at, b.finalized_at, b.receipt_token
      FROM bills b
      WHERE b.business_id = @business_id AND b.id IN (${params2})
      ORDER BY b.created_at DESC
    `);

    const itemsReq = pool.request();
    ids.forEach((id, i) => itemsReq.input(`id${i}`, sql.UniqueIdentifier, id));
    const itemsResult = await itemsReq.query(`
      SELECT bill_id, item_name, quantity, unit_price, tax_rate, line_total, discount_amount
      FROM bill_items
      WHERE bill_id IN (${params2})
    `);
    const byBill = {};
    for (const it of itemsResult.recordset) (byBill[it.bill_id] ||= []).push(it);
    for (const b of billsResult.recordset) attachCharges(b).items = byBill[b.id] || [];
    await attachCreditInfo(billsResult.recordset);

    // Nudge other devices to refresh the Credit tab.
    broadcast(req.user.business_id, { type: 'credit' });

    logger.info(
      { business_id: req.user.business_id, count: ids.length, payment_mode, partial: payments !== undefined },
      'credit bills paid',
    );
    return res.json({
      success: true,
      bills: billsResult.recordset,
      settlement: settlementPayload(settlementId, receiptToken, payment_mode,
        billsResult.recordset, paidNow),
    });
  } catch (err) {
    logger.error({ err }, 'credit settle error');
    return res.status(500).json({ error: 'Failed to settle credit bills' });
  }
});

// POST /api/credit/settlements/:id/whatsapp
// Sends ONE message for a whole Credit-tab payment — every bill paid and the
// total received — linking to its Payment Receipt (/receipt/s/<token>). Same
// api/deeplink split as a bill's (see sendReceiptLink).
router.post('/settlements/:id/whatsapp', requireAuth, whatsappLimiter, async (req, res) => {
  if (!UUID_RE.test(req.params.id)) {
    return res.status(400).json({ error: 'Invalid settlement id' });
  }
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id',          sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT s.receipt_token, s.customer_phone, s.mode, s.total,
               bs.name AS shop_name, bs.whatsapp_mode, b.bill_number
        FROM credit_settlements s
        JOIN businesses bs ON bs.id = s.business_id
        LEFT JOIN credit_payments cp ON cp.settlement_id = s.id
        LEFT JOIN bills b ON b.id = cp.bill_id
        WHERE s.id = @id AND s.business_id = @business_id
        ORDER BY b.created_at
      `);
    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Payment not found' });
    }
    const s = result.recordset[0];
    if (!s.customer_phone || !normalisePhone(s.customer_phone)) {
      return res.status(400).json({ error: 'This customer has no valid phone number' });
    }

    const numbers = [...new Set(result.recordset
      .filter((r) => r.bill_number)
      .map((r) => stripBillPrefix(r.bill_number)))];
    const receiptUrl = `${RECEIPT_BASE}/receipt/s/${s.receipt_token}`;
    const message =
      `Payment received at ${s.shop_name}. Thank you!\n\n` +
      `Bills: ${numbers.map((n) => '#' + n).join(', ')}\n` +
      `Total received: Rs.${Number(s.total).toFixed(2)} (${String(s.mode).toUpperCase()})\n` +
      `View your receipt: ${receiptUrl}`;

    // ponytail: the API template reads "Your bill … is ready / Bill No: {2}";
    // a dedicated "payment received" template needs Meta approval first.
    const out = await sendReceiptLink({
      whatsappMode: s.whatsapp_mode,
      phone: s.customer_phone,
      shopName: s.shop_name,
      billNumber: numbers.join(' '),
      receiptUrl,
      message,
    });
    return res.status(out.status).json(out.body);
  } catch (err) {
    logger.error({ err }, 'settlement whatsapp error');
    return res.status(500).json({ error: 'Failed to send WhatsApp message' });
  }
});

module.exports = router;
