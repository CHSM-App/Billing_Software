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

    const [billResult, expenseResult, dailyResult, expCatResult, payModeResult] = await Promise.all([
      // Sargable DATETIME2 range for bills.created_at
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(`
          SELECT
            COUNT(*) AS bill_count,
            ISNULL(SUM(total), 0) AS total_revenue,
            ISNULL(SUM(discount_amount), 0) AS total_discount,
            ISNULL(SUM(tax_amount), 0) AS total_tax,
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
    ]);

    const bill      = billResult.recordset[0];
    const revenue   = parseFloat(bill.total_revenue);
    const discount  = parseFloat(bill.total_discount);
    const expenses  = parseFloat(expenseResult.recordset[0].total_expenses);
    const netRevenue = parseFloat((revenue - discount).toFixed(2));

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
    });
  } catch (err) {
    logger.error({ err }, 'Summary report error');
    return res.status(500).json({ error: 'Failed to generate report' });
  }
});

module.exports = router;
