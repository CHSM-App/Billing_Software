const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { broadcast } = require('../realtime');

const router = express.Router();

// Viewing the kitchen queue is open to any authenticated role (owner,
// kitchen chef, waiter) — everyone on staff may want to check order status.

// Marking a dish ready is reserved for the kitchen chef. Owners/waiters may
// watch the queue but cannot tick dishes off.
function kitchenOnly(req, res, next) {
  if (req.user.role !== 'kitchen') {
    return res.status(403).json({ error: 'Only the kitchen can mark items ready' });
  }
  next();
}

const VALID_KITCHEN_STATUSES = ['pending', 'ready'];

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
      SELECT id, bill_id, item_name, quantity, kitchen_status, kitchen_done_at
      FROM bill_items
      WHERE bill_id IN (${names.join(',')})
      ORDER BY id ASC
    `);

    const itemsByBill = {};
    for (const item of itemsResult.recordset) {
      (itemsByBill[item.bill_id] ||= []).push(item);
    }

    const orders = billsResult.recordset.map((b) => {
      const items = itemsByBill[b.id] || [];
      const allReady = items.length > 0 && items.every((i) => i.kitchen_status === 'ready');
      return { ...b, items, all_ready: allReady };
    });

    return res.json(orders);
  } catch (err) {
    logger.error({ err }, 'Get kitchen orders error');
    return res.status(500).json({ error: 'Failed to fetch kitchen orders' });
  }
});

// PUT /api/kitchen/items/:id
// Mark a single dish ready (or back to pending). Scoped to the caller's business
// via the parent bill so a kitchen user cannot touch another business's orders.
router.put('/items/:id', requireAuth, kitchenOnly, async (req, res) => {
  const { kitchen_status } = req.body;

  if (!VALID_KITCHEN_STATUSES.includes(kitchen_status)) {
    return res.status(400).json({ error: `kitchen_status must be one of: ${VALID_KITCHEN_STATUSES.join(', ')}` });
  }

  try {
    await poolConnect;
    const doneAt = kitchen_status === 'ready' ? new Date() : null;

    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('kitchen_status', sql.NVarChar(20), kitchen_status)
      .input('kitchen_done_at', sql.DateTime2, doneAt)
      .query(`
        UPDATE bi
        SET bi.kitchen_status = @kitchen_status,
            bi.kitchen_done_at = @kitchen_done_at
        OUTPUT INSERTED.id, INSERTED.bill_id, INSERTED.item_name,
               INSERTED.quantity, INSERTED.kitchen_status, INSERTED.kitchen_done_at
        FROM bill_items bi
        JOIN bills b ON b.id = bi.bill_id
        WHERE bi.id = @id AND b.business_id = @business_id
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Order item not found' });
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
