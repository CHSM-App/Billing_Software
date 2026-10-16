const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { broadcast } = require('../realtime');
const { BILL_ITEMS_JOIN, BILL_ITEMS_ORDER } = require('../billItemsOrder');

const router = express.Router();

// Viewing the kitchen queue is open to any authenticated role (owner,
// kitchen chef, waiter) — everyone on staff may want to check order status.

// Who may move a dish where — per role, target status → statuses it may be
// moved FROM:
//   * the kitchen chef ticks dishes pending <-> ready, and may send any dish
//     (delivered included) back to pending to re-cook it — but never marks a
//     delivered dish "ready", which would undo the delivery;
//   * everyone else (owner, cashier, captain) marks a READY dish delivered once
//     it reaches the table, or undoes that back to ready.
const ROLE_RULES = {
  kitchen: { pending: ['pending', 'ready', 'delivered'], ready: ['pending', 'ready'] },
  other: { delivered: ['ready', 'delivered'], ready: ['ready', 'delivered'] },
};

const VALID_KITCHEN_STATUSES = ['pending', 'ready', 'delivered'];

// GET /api/kitchen/orders
// Active orders for the kitchen: draft bills (an order that has not been paid),
// with their line items and per-item kitchen status. Oldest order first so the
// kitchen works through the queue in arrival order.
router.get('/orders', requireAuth, async (req, res) => {
  try {
    await poolConnect;

    const billsResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.id, b.bill_number, b.table_id, b.customer_name, b.created_at,
               -- The customer's instruction ("no onions", "extra spicy"). The
               -- kitchen is the one place that has to act on it.
               b.notes,
               t.table_number
        FROM bills b
        LEFT JOIN tables t ON t.id = b.table_id AND t.business_id = b.business_id
        WHERE b.business_id = @business_id AND b.status = 'draft'
        ORDER BY b.created_at ASC
      `);

    if (billsResult.recordset.length === 0) return res.json([]);

    const billIds = billsResult.recordset.map((b) => b.id);
    const names = billIds.map((_, i) => `@p${i}`);
    const itemsReq = pool.request();
    billIds.forEach((id, i) => itemsReq.input(`p${i}`, sql.UniqueIdentifier, id));

    const itemsResult = await itemsReq.query(`
      SELECT bi.id, bi.bill_id, bi.item_name, bi.quantity, bi.kitchen_status, bi.kitchen_done_at,
             bi.source, bi.diner_name, bi.diner_phone
      FROM bill_items bi
      ${BILL_ITEMS_JOIN}
      WHERE bi.bill_id IN (${names.join(',')})
      ${BILL_ITEMS_ORDER}
    `);

    const itemsByBill = {};
    for (const item of itemsResult.recordset) {
      (itemsByBill[item.bill_id] ||= []).push(item);
    }

    // Backward compatibility with app versions released before "delivered"
    // existed (≤ 1.1.12). They treat only 'ready' as done and know nothing
    // else, so unless the caller says it understands 'delivered' (the current
    // app sends ?statuses=delivered), a delivered dish is reported as 'ready' —
    // which, from the kitchen's side, it is. Without this an old kitchen
    // display showed delivered dishes as un-cooked.
    const knowsDelivered = req.query.statuses === 'delivered';

    const orders = billsResult.recordset.map((b) => {
      const items = itemsByBill[b.id] || [];
      // all_ready keeps its original meaning (every dish cooked) — old apps
      // split Pending/Completed on it. all_delivered (every dish served) is
      // what the current app uses for its Completed tab.
      const allReady = items.length > 0 &&
        items.every((i) => i.kitchen_status === 'ready' || i.kitchen_status === 'delivered');
      const allDelivered = items.length > 0 &&
        items.every((i) => i.kitchen_status === 'delivered');
      const outItems = knowsDelivered ? items : items.map((i) => (
        i.kitchen_status === 'delivered' ? { ...i, kitchen_status: 'ready' } : i));
      return { ...b, items: outItems, all_ready: allReady, all_delivered: allDelivered };
    });

    return res.json(orders);
  } catch (err) {
    logger.error({ err }, 'Get kitchen orders error');
    return res.status(500).json({ error: 'Failed to fetch kitchen orders' });
  }
});

// PUT /api/kitchen/items/:id
// Move a single dish between pending / ready / delivered, within the caller's
// role rules (see ROLE_RULES). Scoped to the caller's business via the parent
// bill so nobody can touch another business's orders.
router.put('/items/:id', requireAuth, async (req, res) => {
  const { kitchen_status } = req.body;

  if (!VALID_KITCHEN_STATUSES.includes(kitchen_status)) {
    return res.status(400).json({ error: `kitchen_status must be one of: ${VALID_KITCHEN_STATUSES.join(', ')}` });
  }
  const rules = req.user.role === 'kitchen' ? ROLE_RULES.kitchen : ROLE_RULES.other;
  const fromStatuses = rules[kitchen_status];
  if (!fromStatuses) {
    return res.status(403).json({
      error: req.user.role === 'kitchen'
        ? 'The kitchen cannot mark items delivered'
        : 'Only the kitchen can mark items ready or pending',
    });
  }

  try {
    await poolConnect;

    const request = pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('kitchen_status', sql.NVarChar(20), kitchen_status)
      .input('now', sql.DateTime2, new Date());
    fromStatuses.forEach((s, i) => request.input(`from${i}`, sql.NVarChar(20), s));

    // kitchen_done_at is when the dish became ready: cleared on pending, kept
    // when it is later delivered (or un-delivered) rather than reset.
    const result = await request.query(`
        UPDATE bi
        SET bi.kitchen_status = @kitchen_status,
            bi.kitchen_done_at = CASE WHEN @kitchen_status = 'pending' THEN NULL
                                      ELSE COALESCE(bi.kitchen_done_at, @now) END
        OUTPUT INSERTED.id, INSERTED.bill_id, INSERTED.item_name,
               INSERTED.quantity, INSERTED.kitchen_status, INSERTED.kitchen_done_at
        FROM bill_items bi
        JOIN bills b ON b.id = bi.bill_id
        WHERE bi.id = @id AND b.business_id = @business_id
          AND bi.kitchen_status IN (${fromStatuses.map((_, i) => `@from${i}`).join(', ')})
      `);

    if (result.rowsAffected[0] === 0) {
      // Missing, another business's, or not in a status this role may move it
      // from (e.g. delivering a dish the kitchen has not marked ready yet).
      return res.status(404).json({ error: 'Order item not found or not ready for this change' });
    }

    // Real-time: tell every device in this business to refresh the kitchen view,
    // so a cashier/server (not just the chef who tapped) sees the change live.
    broadcast(req.user.business_id, { type: 'kitchen' });

    return res.json(result.recordset[0]);
  } catch (err) {
    logger.error({ err }, 'Mark kitchen item error');
    return res.status(500).json({ error: 'Failed to update order item' });
  }
});

module.exports = router;
