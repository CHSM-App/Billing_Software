const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { broadcast } = require('../realtime');
const { attachCharges } = require('../charges');

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

// GET /api/credit/customers
// Debtor list for the Credit tab: one row per customer (grouped by phone),
// with their outstanding total and unpaid-bill count. Most-owed first.
router.get('/customers', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT
          b.customer_phone                              AS customer_phone,
          MAX(b.customer_name)                          AS customer_name,
          COUNT(*)                                      AS unpaid_count,
          SUM(b.total - b.discount_amount)              AS outstanding,
          MAX(b.created_at)                             AS last_bill_at
        FROM bills b
        WHERE b.business_id = @business_id
          AND b.payment_status = 'unpaid'
          AND b.status = 'finalized'
        GROUP BY b.customer_phone
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
  const phone = req.params.phone;
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
               b.created_at, b.receipt_token
        FROM bills b
        WHERE b.business_id = @business_id
          AND b.customer_phone = @phone
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
      SELECT bill_id, item_name, quantity, unit_price, tax_rate, line_total
      FROM bill_items
      WHERE bill_id IN (${params})
    `);
    const byBill = {};
    for (const it of itemsResult.recordset) {
      (byBill[it.bill_id] ||= []).push(it);
    }
    for (const b of bills) attachCharges(b).items = byBill[b.id] || [];

    return res.json(bills);
  } catch (err) {
    logger.error({ err }, 'credit customer bills error');
    return res.status(500).json({ error: 'Failed to load customer bills' });
  }
});

// GET /api/credit/customers/:phone/summary
// Lightweight outstanding-credit summary for one phone — used on the billing
// screen to show "previous credit due" as the cashier types the customer's
// number. Returns the total, count and the unpaid bill ids (to settle later).
router.get('/customers/:phone/summary', requireAuth, async (req, res) => {
  const phone = req.params.phone;
  if (!phone) return res.status(400).json({ error: 'phone is required' });

  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('phone',       sql.NVarChar(20),     phone)
      .query(`
        SELECT id, total - discount_amount AS due
        FROM bills
        WHERE business_id = @business_id
          AND customer_phone = @phone
          AND payment_status = 'unpaid'
          AND status = 'finalized'
      `);
    const rows = result.recordset;
    const outstanding = rows.reduce((s, r) => s + Number(r.due), 0);
    return res.json({
      outstanding,
      unpaid_count: rows.length,
      bill_ids: rows.map((r) => r.id),
    });
  } catch (err) {
    logger.error({ err }, 'credit summary error');
    return res.status(500).json({ error: 'Failed to load credit summary' });
  }
});

// POST /api/credit/settle
// Marks the given unpaid credit bills as paid, in place, with one shared
// settlement time and payment mode. Body: { bill_ids: [...], payment_mode }.
// Returns the updated bills so the client can build a merged receipt.
router.post('/settle', requireAuth, cashierOrOwner, async (req, res) => {
  const { bill_ids, payment_mode } = req.body;

  if (!Array.isArray(bill_ids) || bill_ids.length === 0) {
    return res.status(400).json({ error: 'bill_ids array is required and must not be empty' });
  }
  if (bill_ids.some((id) => typeof id !== 'string' || !UUID_RE.test(id))) {
    return res.status(400).json({ error: 'bill_ids must all be valid UUIDs' });
  }
  if (!payment_mode || !VALID_PAYMENT_MODES.includes(payment_mode)) {
    return res.status(400).json({ error: `payment_mode must be one of: ${VALID_PAYMENT_MODES.join(', ')}` });
  }

  try {
    await poolConnect;
    const transaction = pool.transaction();
    await transaction.begin();
    try {
      const params = bill_ids.map((_, i) => `@id${i}`).join(', ');
      const request = transaction.request()
        .input('business_id',  sql.UniqueIdentifier, req.user.business_id)
        .input('payment_mode', sql.NVarChar(20),     payment_mode);
      bill_ids.forEach((id, i) => request.input(`id${i}`, sql.UniqueIdentifier, id));

      // Flip only the rows that are still unpaid credit bills for this business.
      // OUTPUT tells us exactly which rows changed so we can detect a mismatch
      // (already-settled or foreign ids) and reject the whole batch.
      const updated = await request.query(`
        UPDATE bills
        SET payment_status       = 'paid',
            settled_at           = GETUTCDATE(),
            settled_payment_mode = @payment_mode
        OUTPUT INSERTED.id
        WHERE business_id = @business_id
          AND id IN (${params})
          AND payment_status = 'unpaid'
          AND status = 'finalized'
      `);

      if (updated.recordset.length !== bill_ids.length) {
        // Some ids were not unpaid credit bills (already settled, voided, or not
        // this business's). Roll back so nothing is partially settled.
        await transaction.rollback();
        return res.status(409).json({
          error: 'Some bills could not be settled (already paid or not found)',
          settled_count: updated.recordset.length,
          requested_count: bill_ids.length,
        });
      }

      await transaction.commit();
    } catch (inner) {
      try { await transaction.rollback(); } catch (_) {}
      throw inner;
    }

    // Return the freshly-settled bills with items for the merged receipt.
    const params2 = bill_ids.map((_, i) => `@id${i}`).join(', ');
    const billsReq = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);
    bill_ids.forEach((id, i) => billsReq.input(`id${i}`, sql.UniqueIdentifier, id));
    const billsResult = await billsReq.query(`
      SELECT b.id, b.bill_number, b.customer_name, b.customer_phone,
             b.subtotal, b.tax_amount, b.discount_amount, b.charges_amount,
             b.additional_charges, b.total, b.round_off,
             b.payment_mode, b.payment_status, b.settled_at, b.settled_payment_mode,
             b.created_at, b.receipt_token
      FROM bills b
      WHERE b.business_id = @business_id AND b.id IN (${params2})
      ORDER BY b.created_at DESC
    `);

    const itemsReq = pool.request();
    bill_ids.forEach((id, i) => itemsReq.input(`id${i}`, sql.UniqueIdentifier, id));
    const itemsResult = await itemsReq.query(`
      SELECT bill_id, item_name, quantity, unit_price, tax_rate, line_total
      FROM bill_items
      WHERE bill_id IN (${params2})
    `);
    const byBill = {};
    for (const it of itemsResult.recordset) (byBill[it.bill_id] ||= []).push(it);
    for (const b of billsResult.recordset) attachCharges(b).items = byBill[b.id] || [];

    // Nudge other devices to refresh the Credit tab.
    broadcast(req.user.business_id, { type: 'credit' });

    logger.info(
      { business_id: req.user.business_id, count: bill_ids.length, payment_mode },
      'credit bills settled',
    );
    return res.json({ success: true, bills: billsResult.recordset });
  } catch (err) {
    logger.error({ err }, 'credit settle error');
    return res.status(500).json({ error: 'Failed to settle credit bills' });
  }
});

module.exports = router;
