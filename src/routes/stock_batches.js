// Stock batches (batches.js, migration 079): the purchase form's batch picker
// and the owner's per-batch profit report.

const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');

const router = express.Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can see batch profit' });
  }
  next();
}

// GET /api/stock-batches/report?status=open|settled|all — what each batch cost,
// sold for and earned. Declared before '/' only for readability; no :id here.
//
// Revenue is what sale lines fetched net of GST and of BOTH discounts: the
// line's own (already inside unit_price) and the bill's, spread by
// (subtotal - discount) / subtotal — the same rule the top-items report uses.
// Only finalized bills count; a held draft's stock is taken but not yet sold.
router.get('/report', requireAuth, ownerOnly, async (req, res) => {
  // 'all' lets the app group a purchase's items under one batch no. and call
  // the batch open while any of its items has stock left.
  const status = ['settled', 'all'].includes(req.query.status) ? req.query.status : 'open';
  const filter = { open: 'AND sb.qty_remaining > 0', settled: 'AND sb.qty_remaining <= 0', all: '' }[status];
  try {
    await poolConnect;
    const r = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        WITH alloc AS (
          SELECT a.batch_id, a.bill_id, a.item_id, a.variant_id, SUM(a.quantity) AS qty
          FROM stock_batch_allocations a
          INNER JOIN bills b ON b.id = a.bill_id AND b.status = 'finalized'
          WHERE a.business_id = @business_id
          GROUP BY a.batch_id, a.bill_id, a.item_id, a.variant_id
        ),
        lines AS (
          SELECT bi.bill_id, bi.item_id, bi.variant_id, SUM(bi.quantity) AS qty,
                 SUM(bi.quantity * bi.unit_price)
                   * CASE WHEN b.subtotal > 0
                          THEN (b.subtotal - b.discount_amount) / b.subtotal ELSE 1 END AS net
          FROM bill_items bi
          INNER JOIN bills b ON b.id = bi.bill_id
          WHERE b.business_id = @business_id AND b.status = 'finalized'
            AND bi.bill_id IN (SELECT bill_id FROM alloc)
          GROUP BY bi.bill_id, bi.item_id, bi.variant_id, b.subtotal, b.discount_amount
        ),
        -- Reserved by held (draft) bills: taken from the batch, not yet sold.
        held AS (
          SELECT a.batch_id, SUM(a.quantity) AS qty
          FROM stock_batch_allocations a
          INNER JOIN bills b ON b.id = a.bill_id AND b.status = 'draft'
          WHERE a.business_id = @business_id
          GROUP BY a.batch_id
        ),
        sold AS (
          SELECT al.batch_id, SUM(al.qty) AS qty,
                 SUM(al.qty * l.net / NULLIF(l.qty, 0)) AS revenue
          FROM alloc al
          INNER JOIN lines l ON l.bill_id = al.bill_id AND l.item_id = al.item_id
            AND ((al.variant_id IS NULL AND l.variant_id IS NULL) OR l.variant_id = al.variant_id)
          GROUP BY al.batch_id
        )
        SELECT sb.id, sb.batch_no, sb.unit_cost, sb.received_date,
               sb.qty_received, sb.qty_sold, sb.qty_lost, sb.qty_remaining,
               i.name AS item_name, v.label AS variant_label,
               vb.vendor_name, vb.invoice_number,
               s.qty AS billed_qty, s.revenue, h.qty AS held_qty
        FROM stock_batches sb
        LEFT JOIN item_variants v ON v.id = sb.variant_id
        LEFT JOIN items i ON i.id = COALESCE(sb.item_id, v.item_id)
        LEFT JOIN vendor_bills vb
          ON vb.id = sb.created_by_vendor_bill_id AND vb.business_id = sb.business_id
        LEFT JOIN sold s ON s.batch_id = sb.id
        LEFT JOIN held h ON h.batch_id = sb.id
        WHERE sb.business_id = @business_id
          ${filter}
        ORDER BY sb.received_date DESC, sb.created_at DESC`);

    return res.json(r.recordset.map((b) => {
      const cost = Number(b.unit_cost);
      const billed = Number(b.billed_qty) || 0;
      const revenue = r2(b.revenue);
      const costOfSold = r2(billed * cost);
      const lostCost = r2(Number(b.qty_lost) * cost);
      return {
        id: b.id,
        code: b.batch_no,
        item_name: b.variant_label ? `${b.item_name} (${b.variant_label})` : b.item_name,
        vendor_name: b.vendor_name ?? null,
        invoice_number: b.invoice_number ?? null,
        received_date: b.received_date instanceof Date
          ? b.received_date.toISOString().slice(0, 10) : String(b.received_date).slice(0, 10),
        unit_cost: cost,
        received: Number(b.qty_received),
        // Sold = on settled bills; held = reserved by bills not settled yet.
        sold: billed,
        held: Number(b.held_qty) || 0,
        lost: Number(b.qty_lost),
        remaining: Math.max(Number(b.qty_remaining), 0),
        revenue,
        cost_of_sold: costOfSold,
        lost_cost: lostCost,
        // Written-off stock is a loss too.
        profit: r2(revenue - costOfSold - lostCost),
      };
    }));
  } catch (err) {
    logger.error({ err }, 'Stock batch report error');
    return res.status(500).json({ error: 'Failed to load batches' });
  }
});

// GET /api/stock-batches/codes — batch nos. used before, newest first, for the
// purchase form to reuse on a new bill or item. Owner only, like purchases.
router.get('/codes', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const r = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`SELECT TOP 50 batch_no, MAX(received_date) AS received_date,
                     COUNT(*) AS items,
                     SUM(CASE WHEN qty_remaining > 0 THEN 1 ELSE 0 END) AS open_items
              FROM stock_batches
              WHERE business_id = @business_id
              GROUP BY batch_no
              ORDER BY MAX(created_at) DESC`);
    return res.json(r.recordset.map((b) => ({
      code: b.batch_no,
      received_date: b.received_date instanceof Date
        ? b.received_date.toISOString().slice(0, 10) : String(b.received_date).slice(0, 10),
      items: Number(b.items),
      open: Number(b.open_items) > 0,
    })));
  } catch (err) {
    logger.error({ err }, 'List batch codes error');
    return res.status(500).json({ error: 'Failed to load batches' });
  }
});

// GET /api/stock-batches?item_id=|variant_id= — a target's open batches,
// oldest first, for the purchase form's "add to batch" picker.
router.get('/', requireAuth, async (req, res) => {
  const { item_id: itemId, variant_id: variantId } = req.query;
  const id = variantId || itemId;
  if (!id || !UUID_RE.test(String(id))) {
    return res.status(400).json({ error: 'item_id or variant_id is required' });
  }
  try {
    await poolConnect;
    const r = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('id', sql.UniqueIdentifier, id)
      .query(`SELECT id, batch_no, unit_cost, received_date, qty_remaining
              FROM stock_batches
              WHERE business_id = @business_id
                AND ${variantId ? 'variant_id' : 'item_id'} = @id
                AND qty_remaining > 0
              ORDER BY received_date, created_at`);
    return res.json(r.recordset.map((b) => ({
      id: b.id,
      code: b.batch_no,
      unit_cost: Number(b.unit_cost),
      remaining: Number(b.qty_remaining),
    })));
  } catch (err) {
    logger.error({ err }, 'List stock batches error');
    return res.status(500).json({ error: 'Failed to load batches' });
  }
});

module.exports = router;
