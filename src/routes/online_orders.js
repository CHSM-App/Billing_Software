'use strict';
// =============================================================================
// Online-store order queue (staff side).  Mounted at /api/online-orders.
//
//   GET  /api/online-orders            -> pending orders + the last day's decided
//   POST /api/online-orders/:id/accept -> turn the order into a draft bill
//   POST /api/online-orders/:id/reject -> decline it with a reason; no bill
//
// An order placed on the public store (routes/public_store.js) is NOT a bill.
// It waits here until a human decides. Accepting is the only path that writes
// to `bills`, which is the whole point of the queue: an internet stranger never
// creates rows in a shop's books unattended.
//
// Accept is deliberately one transaction that also copies the lines, so a
// half-accepted order (bill with no items, or an order pointing at a bill that
// was never finished) cannot exist.
// =============================================================================

const express = require('express');
const crypto = require('crypto');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { broadcast } = require('../realtime');
const { serializeCharges } = require('../charges');
const audit = require('../audit');

const router = express.Router();

// Deciding an order commits the shop to work and to money, so it sits with the
// same roles that finalize bills. A server builds orders; it does not accept them.
const DECIDER_ROLES = ['owner', 'cashier'];

function canDecide(req, res, next) {
  if (!DECIDER_ROLES.includes(req.user.role)) {
    return res.status(403).json({ error: 'Only an owner or cashier can accept or reject online orders' });
  }
  next();
}

// Public receipt token for the bill (same scheme as the POS bills route):
// 16 URL-safe base62 chars, unguessable.
function generateReceiptToken() {
  return crypto.randomBytes(12).toString('base64url').slice(0, 16);
}

const round2 = (n) => +(Number(n) || 0).toFixed(2);

// ---------------------------------------------------------------------------
// GET /api/online-orders
//
// Everything the shop still has work to do on, plus anything decided in the
// last 24h so it can see what it just did (and read back a rejection reason)
// without a separate history screen.
//
// "Still work to do" is deliberately NOT just 'pending'. Accepting an order
// creates a DRAFT bill that nobody has settled yet, so the order is only really
// finished once that bill leaves draft. `bill_status` is returned so the client
// can make exactly that distinction — it drives whether the Online sub-tab is
// shown at all, and an accepted-but-unsettled order must not make the tab (and
// the order with it) vanish.
// ---------------------------------------------------------------------------
router.get('/', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const ordersResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT o.id, o.order_number, o.customer_name, o.customer_phone,
               o.fulfilment, o.address, o.note,
               o.subtotal, o.delivery_charge, o.total,
               o.amount_due, o.paid_amount, o.payment_txn_id, o.payment_status,
               o.status, o.reject_reason, o.bill_id, o.decided_at, o.created_at,
               b.bill_number, b.status AS bill_status
        FROM online_orders o
        LEFT JOIN bills b ON b.id = o.bill_id
        WHERE o.business_id = @business_id
          AND (o.status = 'pending'
               OR (o.status = 'accepted' AND b.status = 'draft')
               OR o.decided_at >= DATEADD(hour, -24, GETUTCDATE()))
        ORDER BY CASE WHEN o.status = 'pending' THEN 0 ELSE 1 END, o.created_at DESC
      `);

    const orders = ordersResult.recordset;
    if (orders.length === 0) return res.json([]);

    const ids = orders.map((_, i) => `@o${i}`);
    const itemReq = pool.request();
    orders.forEach((o, i) => itemReq.input(`o${i}`, sql.UniqueIdentifier, o.id));
    const itemsResult = await itemReq.query(`
      SELECT order_id, item_id, variant_id, item_name, quantity, unit_price,
             tax_rate, line_total
      FROM online_order_items
      WHERE order_id IN (${ids.join(',')})
    `);

    const byOrder = {};
    for (const it of itemsResult.recordset) (byOrder[it.order_id] ||= []).push(it);
    for (const o of orders) o.items = byOrder[o.id] || [];

    return res.json(orders);
  } catch (err) {
    logger.error({ err }, 'Get online orders error');
    return res.status(500).json({ error: 'Failed to fetch online orders' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/online-orders/:id/accept   body: { payment_verified?: boolean }
//
// Creates the draft bill and moves the order to 'accepted'. `payment_verified`
// is the owner confirming, in their own UPI app, that the transaction reference
// the customer typed is real — nothing server-side can check that.
// ---------------------------------------------------------------------------
router.post('/:id/accept', requireAuth, canDecide, async (req, res) => {
  const paymentVerified = req.body ? req.body.payment_verified === true : false;

  // pool.transaction(), matching routes/bills.js.
  const transaction = pool.transaction();
  let started = false;
  try {
    await poolConnect;
    await transaction.begin();
    started = true;

    // UPDLOCK so two devices tapping Accept on the same order serialise here;
    // the loser sees status != 'pending' and gets a clean 409 instead of
    // creating a second bill for the same order.
    const orderRes = await transaction.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, order_number, customer_name, customer_phone, fulfilment,
               address, note, subtotal, delivery_charge, total, amount_due,
               paid_amount, payment_txn_id, payment_status, status
        FROM online_orders WITH (UPDLOCK, ROWLOCK)
        WHERE id = @id AND business_id = @business_id
      `);
    if (orderRes.recordset.length === 0) {
      throw { httpStatus: 404, message: 'Order not found' };
    }
    const order = orderRes.recordset[0];
    if (order.status !== 'pending') {
      throw {
        httpStatus: 409,
        code: 'already_decided',
        message: `This order was already ${order.status}.`,
      };
    }

    const itemsRes = await transaction.request()
      .input('order_id', sql.UniqueIdentifier, order.id)
      .query(`
        SELECT item_id, variant_id, item_name, quantity, unit_price, tax_rate, line_total
        FROM online_order_items
        WHERE order_id = @order_id
      `);
    const lines = itemsRes.recordset;
    if (lines.length === 0) {
      throw { httpStatus: 400, message: 'This order has no items' };
    }

    // Bill number: INV-#### using the same scheme as the POS.
    const numRes = await transaction.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT (SELECT COUNT(*) FROM bills WHERE business_id = @business_id) AS cnt,
               (SELECT bill_prefix FROM businesses WHERE id = @business_id) AS bill_prefix
      `);
    const prefix = (numRes.recordset[0].bill_prefix || 'INV').trim() || 'INV';
    const billNumber = `${prefix}-` + String(numRes.recordset[0].cnt + 1).padStart(4, '0');

    // Delivery rides the existing additional-charges model (migration 035):
    // it is folded into total but is NOT part of the taxable base.
    const deliveryCharge = round2(order.delivery_charge);
    const charges = deliveryCharge > 0 ? [{ name: 'Delivery', amount: deliveryCharge }] : [];
    const subtotal = round2(lines.reduce((s, l) => s + Number(l.line_total), 0));
    const total = round2(subtotal + deliveryCharge);

    // The bill has NO table: an online order is a takeaway/delivery order, so it
    // surfaces in the table-less "Open Orders" queue (GET /api/bills/drafts).
    const billRes = await transaction.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('bill_number', sql.NVarChar(50), billNumber)
      .input('customer_name', sql.NVarChar(200), order.customer_name)
      .input('customer_phone', sql.NVarChar(20), order.customer_phone)
      .input('subtotal', sql.Decimal(10, 2), subtotal)
      .input('charges_amount', sql.Decimal(10, 2), deliveryCharge)
      .input('additional_charges', sql.NVarChar(sql.MAX), serializeCharges(charges))
      .input('total', sql.Decimal(10, 2), total)
      .input('created_by', sql.UniqueIdentifier, req.user.user_id)
      .input('receipt_token', sql.NVarChar(16), generateReceiptToken())
      .query(`
        INSERT INTO bills (business_id, bill_number, table_id, customer_name, customer_phone,
                           subtotal, tax_amount, charges_amount, additional_charges, total,
                           payment_mode, status, created_by_user_id, receipt_token)
        OUTPUT INSERTED.id, INSERTED.bill_number
        VALUES (@business_id, @bill_number, NULL, @customer_name, @customer_phone,
                @subtotal, 0, @charges_amount, @additional_charges, @total,
                'cash', 'draft', @created_by, @receipt_token)
      `);
    const bill = billRes.recordset[0];

    // Lines carry source='customer' so the bill screen and the kitchen can tell
    // them apart from anything staff added later; kitchen_status='pending' puts
    // them straight on the kitchen queue.
    for (const l of lines) {
      await transaction.request()
        .input('bill_id', sql.UniqueIdentifier, bill.id)
        .input('item_id', sql.UniqueIdentifier, l.item_id)
        .input('variant_id', sql.UniqueIdentifier, l.variant_id)
        .input('item_name', sql.NVarChar(200), l.item_name)
        .input('quantity', sql.Decimal(10, 2), l.quantity)
        .input('unit_price', sql.Decimal(12, 4), l.unit_price)
        .input('tax_rate', sql.Decimal(5, 2), l.tax_rate)
        .input('line_total', sql.Decimal(10, 2), l.line_total)
        .input('diner_phone', sql.NVarChar(20), order.customer_phone)
        .input('diner_name', sql.NVarChar(200), order.customer_name)
        .query(`
          INSERT INTO bill_items (bill_id, item_id, variant_id, item_name, quantity,
                                  unit_price, tax_rate, line_total, kitchen_status,
                                  source, diner_phone, diner_name)
          VALUES (@bill_id, @item_id, @variant_id, @item_name, @quantity,
                  @unit_price, @tax_rate, @line_total, 'pending',
                  'customer', @diner_phone, @diner_name)
        `);
    }

    // 'verified' only when the owner says they saw the money. A claimed-but-
    // unconfirmed payment stays 'claimed' so the counter still collects it.
    const newPaymentStatus =
      paymentVerified && order.payment_txn_id ? 'verified' : order.payment_status;

    await transaction.request()
      .input('id', sql.UniqueIdentifier, order.id)
      .input('bill_id', sql.UniqueIdentifier, bill.id)
      .input('user_id', sql.UniqueIdentifier, req.user.user_id)
      .input('payment_status', sql.NVarChar(20), newPaymentStatus)
      .query(`
        UPDATE online_orders
        SET status = 'accepted', bill_id = @bill_id, decided_by_user_id = @user_id,
            decided_at = GETUTCDATE(), payment_status = @payment_status
        WHERE id = @id
      `);

    await transaction.commit();

    // Live refresh: the new draft, the kitchen queue, and the store queue itself.
    broadcast(req.user.business_id, { type: 'drafts' });
    broadcast(req.user.business_id, { type: 'kitchen' });
    broadcast(req.user.business_id, { type: 'store' });

    audit.logOnlineOrderAccepted(
      { user_id: req.user.user_id, user_name: req.user.name, business_id: req.user.business_id },
      order,
      bill.bill_number,
    );

    return res.json({
      success: true,
      bill_id: bill.id,
      bill_number: bill.bill_number,
      order_number: order.order_number,
    });
  } catch (err) {
    if (started) { try { await transaction.rollback(); } catch (_) {} }
    if (err && err.httpStatus) {
      return res.status(err.httpStatus).json({
        error: err.message,
        ...(err.code ? { code: err.code } : {}),
      });
    }
    logger.error({ err }, 'Accept online order error');
    return res.status(500).json({ error: 'Failed to accept the order' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/online-orders/:id/reject   body: { reason? }
// No bill is created. Any advance the customer paid is refunded by the shop
// out-of-band — we never took the money, their UPI app did.
// ---------------------------------------------------------------------------
router.post('/:id/reject', requireAuth, canDecide, async (req, res) => {
  const reason = ((req.body && req.body.reason) || '').toString().trim().slice(0, 200);

  try {
    await poolConnect;
    const orderRes = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, order_number, customer_phone, total, status
        FROM online_orders
        WHERE id = @id AND business_id = @business_id
      `);
    if (orderRes.recordset.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }
    const order = orderRes.recordset[0];
    if (order.status !== 'pending') {
      return res.status(409).json({
        code: 'already_decided',
        error: `This order was already ${order.status}.`,
      });
    }

    // The status guard is in the UPDATE too, so a concurrent accept cannot be
    // overwritten by a reject that read 'pending' a moment earlier.
    const upd = await pool.request()
      .input('id', sql.UniqueIdentifier, order.id)
      .input('user_id', sql.UniqueIdentifier, req.user.user_id)
      .input('reason', sql.NVarChar(200), reason || null)
      .query(`
        UPDATE online_orders
        SET status = 'rejected', reject_reason = @reason,
            decided_by_user_id = @user_id, decided_at = GETUTCDATE()
        WHERE id = @id AND status = 'pending'
      `);
    if (!upd.rowsAffected[0]) {
      return res.status(409).json({
        code: 'already_decided',
        error: 'This order was just decided on another device.',
      });
    }

    broadcast(req.user.business_id, { type: 'store' });

    audit.logOnlineOrderRejected(
      { user_id: req.user.user_id, user_name: req.user.name, business_id: req.user.business_id },
      order,
      reason,
    );

    return res.json({ success: true, order_number: order.order_number });
  } catch (err) {
    logger.error({ err }, 'Reject online order error');
    return res.status(500).json({ error: 'Failed to reject the order' });
  }
});

module.exports = router;
