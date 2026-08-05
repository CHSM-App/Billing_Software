const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { requireDateParam, todayUtc, dayRange, dateRange } = require('../dateUtils');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can access reports' });
  }
  next();
}

// ---------------------------------------------------------------------------
// GET /api/reports/today?date=YYYY-MM-DD
//
// `date` is optional — defaults to today in UTC when omitted.
// Flutter clients should pass the device's local date to avoid UTC midnight
// cutoff issues for businesses in non-UTC timezones.
// ---------------------------------------------------------------------------
router.get('/today', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    // Accept an explicit date from the client so businesses in non-UTC
    // timezones get the correct local "today".
    const dateStr = req.query.date || todayUtc();
    if (req.query.date && !/^\d{4}-\d{2}-\d{2}$/.test(req.query.date)) {
      return res.status(400).json({ error: 'date must be in YYYY-MM-DD format' });
    }

    const { start, end } = dayRange(dateStr);

    const [billResult, expenseResult] = await Promise.all([
      // Sargable range on DATETIME2 — no CAST() wrapping the column.
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        start)
        .input('to_dt',       sql.DateTime2,        end)
        .query(`
          SELECT
            COUNT(*) AS bill_count,
            ISNULL(SUM(total), 0) AS total_revenue,
            ISNULL(SUM(discount_amount), 0) AS total_discount,
            ISNULL(SUM(CASE WHEN payment_mode = 'cash'   THEN total ELSE 0 END), 0) AS cash,
            ISNULL(SUM(CASE WHEN payment_mode = 'upi'    THEN total ELSE 0 END), 0) AS upi,
            ISNULL(SUM(CASE WHEN payment_mode = 'card'   THEN total ELSE 0 END), 0) AS card,
            ISNULL(SUM(CASE WHEN payment_mode = 'credit' THEN total ELSE 0 END), 0) AS credit,
            ISNULL(SUM(CASE WHEN payment_mode = 'other'  THEN total ELSE 0 END), 0) AS other
          FROM bills
          WHERE business_id = @business_id
            AND status = 'finalized'
            AND created_at >= @from_dt AND created_at < @to_dt
        `),
      // expenses.expense_date is a DATE column — bind as sql.Date to avoid
      // implicit conversion and keep the index usable.
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('expense_date', sql.Date, dateStr)
        .query(`
          SELECT ISNULL(SUM(amount), 0) AS total_expenses
          FROM expenses
          WHERE business_id = @business_id AND expense_date = @expense_date
        `),
    ]);

    const bill      = billResult.recordset[0];
    const revenue   = parseFloat(bill.total_revenue);
    const discount  = parseFloat(bill.total_discount);
    const expenses  = parseFloat(expenseResult.recordset[0].total_expenses);
    const netRevenue = parseFloat((revenue - discount).toFixed(2));

    return res.json({
      date: dateStr,
      bill_count:      bill.bill_count,
      total_revenue:   revenue,
      total_discount:  discount,
      total_expenses:  expenses,
      net_profit:      parseFloat((netRevenue - expenses).toFixed(2)),
      by_payment_mode: {
        cash:   parseFloat(bill.cash),
        upi:    parseFloat(bill.upi),
        card:   parseFloat(bill.card),
        credit: parseFloat(bill.credit),
        other:  parseFloat(bill.other),
      },
    });
  } catch (err) {
    logger.error({ err }, 'Today report error');
    return res.status(500).json({ error: 'Failed to generate report' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/reports/summary?from=YYYY-MM-DD&to=YYYY-MM-DD
// ---------------------------------------------------------------------------
router.get('/summary', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    let fromStr, toStr;
    try {
      fromStr = requireDateParam(req.query.from, 'from');
      toStr   = requireDateParam(req.query.to,   'to');
    } catch (e) {
      return res.status(400).json({ error: e.message });
    }

    if (fromStr > toStr) {
      return res.status(400).json({ error: '"from" must not be after "to"' });
    }

    const { start: fromDt, end: toDt } = dateRange(fromStr, toStr);

    const [billResult, expenseResult, dailyResult, expCatResult, payModeResult, topItemsResult, recentBillsResult] = await Promise.all([
      // Sargable DATETIME2 range for bills.created_at
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(`
          -- The payment split uses the EFFECTIVE mode and NET amount so it
          -- tallies exactly with total sales:
          --   effective mode = settled_payment_mode once a credit bill is paid
          --                    (real cash/upi it was collected as), else
          --                    payment_mode (an unpaid credit stays 'credit').
          --   net amount     = total - discount_amount (what total sales uses).
          SELECT
            COUNT(*) AS bill_count,
            ISNULL(SUM(total - discount_amount), 0) AS total_revenue,
            ISNULL(SUM(discount_amount), 0) AS total_discount,
            ISNULL(SUM(tax_amount), 0) AS total_tax,
            ISNULL(SUM(CASE WHEN eff_mode = 'cash'   THEN net ELSE 0 END), 0) AS cash,
            ISNULL(SUM(CASE WHEN eff_mode = 'upi'    THEN net ELSE 0 END), 0) AS upi,
            ISNULL(SUM(CASE WHEN eff_mode = 'card'   THEN net ELSE 0 END), 0) AS card,
            ISNULL(SUM(CASE WHEN eff_mode = 'credit' THEN net ELSE 0 END), 0) AS credit,
            ISNULL(SUM(CASE WHEN eff_mode = 'other'  THEN net ELSE 0 END), 0) AS other
          FROM (
            SELECT
              total,
              discount_amount,
              tax_amount,
              (total - discount_amount) AS net,
              CASE
                WHEN payment_mode = 'credit' AND payment_status = 'paid'
                     AND settled_payment_mode IS NOT NULL
                THEN settled_payment_mode
                ELSE payment_mode
              END AS eff_mode
            FROM bills
            WHERE business_id = @business_id
              AND status = 'finalized'
              AND created_at >= @from_dt AND created_at < @to_dt
          ) x
        `),
      // expenses.expense_date is a DATE column — bind as sql.Date
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_date',   sql.Date, fromStr)
        .input('to_date',     sql.Date, toStr)
        .query(`
          SELECT ISNULL(SUM(amount), 0) AS total_expenses
          FROM expenses
          WHERE business_id = @business_id
            AND expense_date >= @from_date AND expense_date <= @to_date
        `),
      // Daily breakdown — project created_at → DATE for grouping only in the
      // SELECT/GROUP BY, not in the WHERE filter (which remains sargable).
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .input('from_date',   sql.Date,             fromStr)
        .input('to_date',     sql.Date,             toStr)
        .query(`
          SELECT d.day,
                 ISNULL(b.revenue,  0) AS revenue,
                 ISNULL(e.expenses, 0) AS expenses,
                 ISNULL(b.revenue,  0) - ISNULL(e.expenses, 0) AS profit
          FROM (
            SELECT CAST(created_at AS DATE) AS day
            FROM bills
            WHERE business_id = @business_id AND status = 'finalized'
              AND created_at >= @from_dt AND created_at < @to_dt
            UNION
            SELECT expense_date AS day
            FROM expenses
            WHERE business_id = @business_id
              AND expense_date >= @from_date AND expense_date <= @to_date
          ) d
          LEFT JOIN (
            SELECT CAST(created_at AS DATE) AS day, SUM(total) AS revenue
            FROM bills
            WHERE business_id = @business_id AND status = 'finalized'
              AND created_at >= @from_dt AND created_at < @to_dt
            GROUP BY CAST(created_at AS DATE)
          ) b ON b.day = d.day
          LEFT JOIN (
            SELECT expense_date AS day, SUM(amount) AS expenses
            FROM expenses
            WHERE business_id = @business_id
              AND expense_date >= @from_date AND expense_date <= @to_date
            GROUP BY expense_date
          ) e ON e.day = d.day
          ORDER BY d.day
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_date',   sql.Date, fromStr)
        .input('to_date',     sql.Date, toStr)
        .query(`
          SELECT category, SUM(amount) AS total
          FROM expenses
          WHERE business_id = @business_id
            AND expense_date >= @from_date AND expense_date <= @to_date
          GROUP BY category
          ORDER BY total DESC
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(`
          SELECT payment_mode, COUNT(*) AS count, SUM(total) AS total
          FROM bills
          WHERE business_id = @business_id AND status = 'finalized'
            AND created_at >= @from_dt AND created_at < @to_dt
          GROUP BY payment_mode
          ORDER BY total DESC
        `),
      // Top-selling items — by revenue, over the same period. qty_sold is the
      // total quantity across all finalized bills; revenue is the line totals.
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(`
          SELECT TOP 8
                 bi.item_name,
                 SUM(bi.quantity)   AS qty_sold,
                 SUM(bi.line_total) AS revenue
          FROM bill_items bi
          JOIN bills b ON b.id = bi.bill_id
          WHERE b.business_id = @business_id AND b.status = 'finalized'
            AND b.created_at >= @from_dt AND b.created_at < @to_dt
          GROUP BY bi.item_name
          ORDER BY revenue DESC
        `),
      // Recent bills — latest finalized bills in the period, for the list.
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(`
          SELECT TOP 10
                 b.bill_number, b.total, b.discount_amount, b.created_at,
                 b.customer_name, t.table_number
          FROM bills b
          LEFT JOIN tables t ON t.id = b.table_id
          WHERE b.business_id = @business_id AND b.status = 'finalized'
            AND b.created_at >= @from_dt AND b.created_at < @to_dt
          ORDER BY b.created_at DESC
        `),
    ]);

    const bill      = billResult.recordset[0];
    // total_revenue is already NET of discount (SUM(total - discount_amount)),
    // so the payment split below sums exactly to it.
    const netRevenue = parseFloat(bill.total_revenue);
    const revenue    = netRevenue;
    const discount   = parseFloat(bill.total_discount);
    const expenses   = parseFloat(expenseResult.recordset[0].total_expenses);

    return res.json({
      from: fromStr,
      to:   toStr,
      bill_count:      bill.bill_count,
      total_revenue:   revenue,
      total_discount:  discount,
      total_tax:       parseFloat(bill.total_tax),
      total_expenses:  expenses,
      net_profit:      parseFloat((netRevenue - expenses).toFixed(2)),
      by_payment_mode: {
        cash:   parseFloat(bill.cash),
        upi:    parseFloat(bill.upi),
        card:   parseFloat(bill.card),
        credit: parseFloat(bill.credit),
        other:  parseFloat(bill.other),
      },
      daily: dailyResult.recordset.map((r) => ({
        day:      r.day instanceof Date ? r.day.toISOString().slice(0, 10) : String(r.day),
        revenue:  parseFloat(r.revenue),
        expenses: parseFloat(r.expenses),
        profit:   parseFloat(r.profit),
      })),
      expenses_by_category: expCatResult.recordset.map((r) => ({
        category: r.category,
        total:    parseFloat(r.total),
      })),
      revenue_by_payment_mode: payModeResult.recordset.map((r) => ({
        mode:  r.payment_mode,
        count: r.count,
        total: parseFloat(r.total),
      })),
      top_items: topItemsResult.recordset.map((r) => ({
        item_name: r.item_name,
        qty_sold:  parseFloat(r.qty_sold),
        revenue:   parseFloat(r.revenue),
      })),
      recent_bills: recentBillsResult.recordset.map((r) => ({
        bill_number:     r.bill_number,
        total:           parseFloat(r.total),
        discount_amount: parseFloat(r.discount_amount || 0),
        created_at:      r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at),
        customer_name:   r.customer_name,
        table_number:    r.table_number,
      })),
    });
  } catch (err) {
    logger.error({ err }, 'Summary report error');
    return res.status(500).json({ error: 'Failed to generate report' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/reports/weekly-sales?date=YYYY-MM-DD
//
// Net sales for the last 7 days ending on `date` (defaults to today, UTC).
// This is INDEPENDENT of the report's period filter, so the "Last 7 days"
// chart always shows the real last week regardless of what range is selected.
// Days with no bills are returned with revenue 0.
// ---------------------------------------------------------------------------
router.get('/weekly-sales', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const dateStr = req.query.date || todayUtc();
    if (req.query.date && !/^\d{4}-\d{2}-\d{2}$/.test(req.query.date)) {
      return res.status(400).json({ error: 'date must be in YYYY-MM-DD format' });
    }

    // 7-day window: [today-6 .. today]. Build the from/to date strings, then a
    // sargable DATETIME2 range covering the whole span.
    const [y, m, d] = dateStr.split('-').map(Number);
    const end = new Date(Date.UTC(y, m - 1, d));
    const start = new Date(end);
    start.setUTCDate(start.getUTCDate() - 6);
    const fromStr = start.toISOString().slice(0, 10);
    const { start: fromDt, end: toDt } = dateRange(fromStr, dateStr);

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('from_dt',     sql.DateTime2,        fromDt)
      .input('to_dt',       sql.DateTime2,        toDt)
      .query(`
        SELECT CAST(created_at AS DATE) AS day,
               SUM(total - discount_amount) AS revenue
        FROM bills
        WHERE business_id = @business_id AND status = 'finalized'
          AND created_at >= @from_dt AND created_at < @to_dt
        GROUP BY CAST(created_at AS DATE)
      `);

    const byDay = {};
    for (const r of result.recordset) {
      const key = r.day instanceof Date ? r.day.toISOString().slice(0, 10) : String(r.day);
      byDay[key] = parseFloat(r.revenue);
    }

    // Emit all 7 days in order, filling gaps with 0.
    const days = [];
    for (let i = 0; i < 7; i++) {
      const dt = new Date(start);
      dt.setUTCDate(dt.getUTCDate() + i);
      const key = dt.toISOString().slice(0, 10);
      days.push({ day: key, revenue: byDay[key] || 0 });
    }

    return res.json({ days });
  } catch (err) {
    logger.error({ err }, 'Weekly sales report error');
    return res.status(500).json({ error: 'Failed to generate weekly sales' });
  }
});

module.exports = router;
