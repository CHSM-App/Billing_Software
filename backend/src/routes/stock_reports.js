const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { requireDateParam, dateRange } = require('../dateUtils');
const { BUSINESS_DATE_SQL } = require('../stockLedger');

// Opening/closing stock and item-wise profit. Mounted on /api/reports beside
// routes/reports.js; stock history comes from the stock_movements ledger.
const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can access reports' });
  }
  next();
}

function parseRange(req, res) {
  try {
    const from = requireDateParam(req.query.from, 'from');
    const to = requireDateParam(req.query.to, 'to');
    if (from > to) {
      res.status(400).json({ error: '"from" must not be after "to"' });
      return null;
    }
    return { from, to };
  } catch (e) {
    res.status(400).json({ error: e.message });
    return null;
  }
}

const num = (v) => (v == null ? 0 : parseFloat(v));
const day = (d) => d.toISOString().slice(0, 10);

// GET /stock-summary?from&to — one row per tracked item / size: opening = stock
// before `from`, closing = stock at the end of `to`, plus what moved between.
// A day's opening is the previous day's closing by construction (both are sums
// of the same ledger), so a mid-day purchase never disturbs either.
router.get('/stock-summary', requireAuth, ownerOnly, async (req, res) => {
  const r = parseRange(req, res);
  if (!r) return;
  try {
    await poolConnect;
    const q = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('from', sql.Date, r.from)
      .input('to', sql.Date, r.to)
      .input('at', sql.DateTime2, null)
      .query(`
        DECLARE @today DATE = ${BUSINESS_DATE_SQL};
        WITH m AS (
          SELECT item_id, variant_id,
            SUM(CASE WHEN movement_date < @from OR movement_type = 'opening' THEN qty ELSE 0 END) AS opening,
            SUM(CASE WHEN movement_date >= @from AND movement_type = 'purchase' THEN qty ELSE 0 END) AS purchased,
            -SUM(CASE WHEN movement_date >= @from AND movement_type = 'sale' THEN qty ELSE 0 END) AS sold,
            SUM(CASE WHEN movement_date >= @from AND movement_type = 'void' THEN qty ELSE 0 END) AS returned,
            SUM(CASE WHEN movement_date >= @from AND movement_type = 'adjust' THEN qty ELSE 0 END) AS adjusted,
            SUM(qty) AS closing
          FROM stock_movements
          WHERE business_id = @business_id AND movement_date <= @to
          GROUP BY item_id, variant_id
        ),
        t AS (  -- every tracked target, with its live stock
          SELECT i.id AS item_id, CAST(NULL AS UNIQUEIDENTIFIER) AS variant_id,
                 i.name, CAST(NULL AS NVARCHAR(50)) AS label, i.unit, i.stock_quantity AS live
          FROM items i WHERE i.business_id = @business_id AND i.stock_quantity IS NOT NULL
          UNION ALL
          SELECT CAST(NULL AS UNIQUEIDENTIFIER), v.id, i.name, v.label, ISNULL(v.unit, i.unit), v.stock_quantity
          FROM item_variants v JOIN items i ON i.id = v.item_id
          WHERE i.business_id = @business_id AND v.stock_quantity IS NOT NULL
        )
        SELECT t.item_id, t.variant_id, t.name, t.label, t.unit,
               ISNULL(m.opening, 0) AS opening, ISNULL(m.purchased, 0) AS purchased,
               ISNULL(m.sold, 0) AS sold, ISNULL(m.returned, 0) AS returned,
               ISNULL(m.adjusted, 0) AS adjusted, ISNULL(m.closing, 0) AS closing,
               t.live - ISNULL((SELECT SUM(s.qty) FROM stock_movements s
                                WHERE s.business_id = @business_id
                                  AND ((t.item_id IS NOT NULL AND s.item_id = t.item_id)
                                    OR (t.variant_id IS NOT NULL AND s.variant_id = t.variant_id))), 0) AS drift,
               @today AS today,
               (SELECT MIN(movement_date) FROM stock_movements WHERE business_id = @business_id) AS history_from
        FROM t
        LEFT JOIN m ON (t.item_id IS NOT NULL AND m.item_id = t.item_id)
                    OR (t.variant_id IS NOT NULL AND m.variant_id = t.variant_id)
        ORDER BY t.name, t.label`);

    const rows = [];
    let historyFrom = null;
    for (const x of q.recordset) {
      historyFrom = x.history_from;
      // A path that changed stock without logging (or a race) leaves the ledger
      // short of the live count: fold the gap into today's adjustment so any
      // range reaching today closes on exactly what is on the shelf.
      const drift = r.to >= day(x.today) ? num(x.drift) : 0;
      const row = {
        item_id: x.item_id,
        variant_id: x.variant_id,
        name: x.label ? `${x.name} - ${x.label}` : x.name,
        unit: x.unit,
        opening: num(x.opening),
        purchased: num(x.purchased),
        sold: num(x.sold),
        returned: num(x.returned),
        adjusted: num(x.adjusted) + drift,
        closing: num(x.closing) + drift,
      };
      if (row.opening || row.purchased || row.sold || row.returned || row.adjusted || row.closing) {
        rows.push(row);
      }
    }
    return res.json({ from: r.from, to: r.to, history_from: historyFrom ? day(historyFrom) : null, rows });
  } catch (err) {
    logger.error({ err }, 'Stock summary error');
    return res.status(500).json({ error: 'Failed to generate stock report' });
  }
});

// GET /stock-daily?from&to&item_id|variant_id — one item day by day: each
// day's opening, purchased, sold and closing (the next day opens on this closing).
router.get('/stock-daily', requireAuth, ownerOnly, async (req, res) => {
  const r = parseRange(req, res);
  if (!r) return;
  const { item_id: itemId, variant_id: variantId } = req.query;
  if (!itemId === !variantId) {
    return res.status(400).json({ error: 'Pass exactly one of item_id, variant_id' });
  }
  try {
    await poolConnect;
    const q = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('id', sql.UniqueIdentifier, itemId || variantId)
      .input('to', sql.Date, r.to)
      .query(`
        SELECT movement_date AS d, movement_type AS t, SUM(qty) AS qty
        FROM stock_movements
        WHERE business_id = @business_id AND movement_date <= @to
          AND ${itemId ? 'item_id' : 'variant_id'} = @id
        GROUP BY movement_date, movement_type`);

    let running = 0; // stock before the range
    const byDay = {};
    for (const x of q.recordset) {
      const d = day(x.d);
      if (d < r.from || x.t === 'opening') running += num(x.qty);
      else (byDay[d] = byDay[d] || []).push(x);
    }
    const days = [];
    for (let d = new Date(`${r.from}T00:00:00Z`); day(d) <= r.to; d.setUTCDate(d.getUTCDate() + 1)) {
      const rows = byDay[day(d)] || [];
      const sum = (t) => rows.filter((x) => x.t === t).reduce((a, x) => a + num(x.qty), 0);
      // Sold is net of voided bills (a cancelled bill is not a sale), same as
      // the summary. Manual corrections move the closing but are not a column.
      const purchased = sum('purchase');
      const sold = -sum('sale') - sum('void');
      const opening = running;
      running += purchased - sold + sum('adjust');
      days.push({ date: day(d), opening, purchased, sold, closing: running });
    }
    return res.json({ from: r.from, to: r.to, days });
  } catch (err) {
    logger.error({ err }, 'Stock daily error');
    return res.status(500).json({ error: 'Failed to generate daily stock' });
  }
});

// GET /item-profit?from&to — per item / size: qty sold, net sales, buying cost
// (snapshot on each sale line from purchase bills) and profit. Ex-tax, after
// line and bill discounts, finalized bills only. Lines with no cost (never
// purchased, or sold before costs were tracked) are counted in qty_no_cost and
// left out of cost and profit rather than guessed.
router.get('/item-profit', requireAuth, ownerOnly, async (req, res) => {
  const r = parseRange(req, res);
  if (!r) return;
  try {
    await poolConnect;
    const { start, end } = dateRange(r.from, r.to);
    const q = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('from_dt', sql.DateTime2, start)
      .input('to_dt', sql.DateTime2, end)
      .query(`
        -- Business day: a shop open past midnight (day_end_hour = 4) books its
        -- 12:30am sales to the day it opened. Same rule as the stock ledger.
        DECLARE @shift INT = 60 * ISNULL((SELECT day_end_hour FROM businesses WHERE id = @business_id), 0);
        WITH L AS (
          SELECT bi.item_id, bi.variant_id, bi.item_name, bi.quantity, bi.unit_cost,
                 bi.quantity * bi.unit_price * CASE WHEN b.subtotal > 0
                   THEN (b.subtotal - ISNULL(b.discount_amount, 0)) / b.subtotal ELSE 1 END AS net
          FROM bill_items bi JOIN bills b ON b.id = bi.bill_id
          WHERE b.business_id = @business_id AND b.status = 'finalized'
            AND b.finalized_at >= DATEADD(MINUTE, @shift, @from_dt)
            AND b.finalized_at <  DATEADD(MINUTE, @shift, @to_dt)
        )
        SELECT MAX(item_name) AS name, item_id, variant_id,
               SUM(quantity) AS qty, SUM(net) AS sales,
               SUM(CASE WHEN unit_cost IS NOT NULL THEN quantity * unit_cost END) AS cost,
               SUM(CASE WHEN unit_cost IS NOT NULL THEN net END) AS costed_sales,
               SUM(CASE WHEN unit_cost IS NULL THEN quantity ELSE 0 END) AS qty_no_cost
        FROM L
        GROUP BY item_id, variant_id,
                 CASE WHEN item_id IS NULL AND variant_id IS NULL THEN item_name END`);

    const rows = q.recordset.map((x) => {
      const qty = num(x.qty);
      const cost = num(x.cost);
      const costedSales = num(x.costed_sales);
      const costedQty = qty - num(x.qty_no_cost);
      const profit = costedSales - cost;
      return {
        item_id: x.item_id,
        variant_id: x.variant_id,
        name: x.name,
        qty,
        sales: num(x.sales),
        cost,
        profit,
        avg_sell: costedQty > 0 ? costedSales / costedQty : null,
        avg_cost: costedQty > 0 ? cost / costedQty : null,
        margin_pct: costedSales > 0 ? (profit / costedSales) * 100 : null,
        qty_no_cost: num(x.qty_no_cost),
      };
    }).sort((a, b) => b.profit - a.profit);

    const sum = (k) => rows.reduce((a, x) => a + x[k], 0);
    return res.json({
      from: r.from,
      to: r.to,
      rows,
      totals: { qty: sum('qty'), sales: sum('sales'), cost: sum('cost'), profit: sum('profit'), qty_no_cost: sum('qty_no_cost') },
    });
  } catch (err) {
    logger.error({ err }, 'Item profit error');
    return res.status(500).json({ error: 'Failed to generate profit report' });
  }
});

module.exports = router;
