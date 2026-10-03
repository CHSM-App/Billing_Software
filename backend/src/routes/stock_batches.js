const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can view stock batches' });
  }
  next();
}

// GET /api/stock-batches — open batches, oldest first, so the owner can see
// what has been sitting longest and clear it. Optional ?item_id= narrows it.
router.get('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);
    let filter = '';
    if (req.query.item_id) {
      request.input('item_id', sql.UniqueIdentifier, req.query.item_id);
      filter = 'AND COALESCE(b.item_id, v.item_id) = @item_id';
    }
    const result = await request.query(`
      SELECT b.id, b.item_id, b.variant_id, b.batch_no, b.received_date,
             b.unit_cost, b.qty_received, b.qty_remaining,
             DATEDIFF(day, b.received_date, CAST(GETUTCDATE() AS DATE)) AS days_old,
             CASE WHEN v.id IS NULL THEN i.name ELSE vi.name + ' (' + v.label + ')' END AS item_name,
             vb.vendor_name
      FROM stock_batches b
      LEFT JOIN items i ON i.id = b.item_id
      LEFT JOIN item_variants v ON v.id = b.variant_id
      LEFT JOIN items vi ON vi.id = v.item_id
      LEFT JOIN vendor_bills vb ON vb.id = b.vendor_bill_id
      WHERE b.business_id = @business_id AND b.qty_remaining > 0 ${filter}
      ORDER BY b.received_date, b.created_at
    `);
    return res.json(result.recordset.map((r) => ({
      id: r.id,
      item_id: r.item_id,
      variant_id: r.variant_id,
      item_name: r.item_name,
      vendor_name: r.vendor_name,
      batch_no: r.batch_no,
      received_date: r.received_date instanceof Date
        ? r.received_date.toISOString().slice(0, 10) : r.received_date,
      days_old: r.days_old,
      unit_cost: parseFloat(r.unit_cost),
      qty_received: parseFloat(r.qty_received),
      qty_remaining: parseFloat(r.qty_remaining),
    })));
  } catch (err) {
    logger.error({ err }, 'List stock batches error');
    return res.status(500).json({ error: 'Failed to fetch stock batches' });
  }
});

module.exports = router;
