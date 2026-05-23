const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can access reports' });
  }
  next();
}

// GET /api/reports/today
router.get('/today', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const today = new Date().toISOString().slice(0, 10);

    const [billResult, expenseResult] = await Promise.all([
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('today', sql.NVarChar(20), today)
        .query(`
          SELECT
            COUNT(*) AS bill_count,
            ISNULL(SUM(total), 0) AS total_revenue,
            ISNULL(SUM(CASE WHEN payment_mode = 'cash'   THEN total ELSE 0 END), 0) AS cash,
            ISNULL(SUM(CASE WHEN payment_mode = 'upi'    THEN total ELSE 0 END), 0) AS upi,
            ISNULL(SUM(CASE WHEN payment_mode = 'card'   THEN total ELSE 0 END), 0) AS card,
            ISNULL(SUM(CASE WHEN payment_mode = 'credit' THEN total ELSE 0 END), 0) AS credit,
            ISNULL(SUM(CASE WHEN payment_mode = 'other'  THEN total ELSE 0 END), 0) AS other
          FROM bills
          WHERE business_id = @business_id
            AND status = 'finalized'
            AND CAST(created_at AS DATE) = @today
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('today', sql.Date, today)
        .query(`
          SELECT ISNULL(SUM(amount), 0) AS total_expenses
          FROM expenses
          WHERE business_id = @business_id AND expense_date = @today
        `),
    ]);

    const bill = billResult.recordset[0];
    const revenue = parseFloat(bill.total_revenue);
    const expenses = parseFloat(expenseResult.recordset[0].total_expenses);

    return res.json({
      date: today,
      bill_count: bill.bill_count,
      total_revenue: revenue,
      total_expenses: expenses,
      net_profit: revenue - expenses,
      by_payment_mode: {
        cash: parseFloat(bill.cash),
        upi: parseFloat(bill.upi),
        card: parseFloat(bill.card),
        credit: parseFloat(bill.credit),
        other: parseFloat(bill.other),
      },
    });
  } catch (err) {
    console.error('Today report error:', err.message);
    return res.status(500).json({ error: 'Failed to generate report' });
  }
});

// GET /api/reports/summary?from=YYYY-MM-DD&to=YYYY-MM-DD
router.get('/summary', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { from, to } = req.query;
    if (!from || !to) {
      return res.status(400).json({ error: 'from and to date params are required' });
    }

    const [billResult, expenseResult, dailyResult, expCatResult, payModeResult] = await Promise.all([
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from', sql.Date, from)
        .input('to', sql.Date, to)
        .query(`
          SELECT
            COUNT(*) AS bill_count,
            ISNULL(SUM(total), 0) AS total_revenue,
            ISNULL(SUM(tax_amount), 0) AS total_tax,
            ISNULL(SUM(CASE WHEN payment_mode = 'cash'   THEN total ELSE 0 END), 0) AS cash,
            ISNULL(SUM(CASE WHEN payment_mode = 'upi'    THEN total ELSE 0 END), 0) AS upi,
            ISNULL(SUM(CASE WHEN payment_mode = 'card'   THEN total ELSE 0 END), 0) AS card,
            ISNULL(SUM(CASE WHEN payment_mode = 'credit' THEN total ELSE 0 END), 0) AS credit,
            ISNULL(SUM(CASE WHEN payment_mode = 'other'  THEN total ELSE 0 END), 0) AS other
          FROM bills
          WHERE business_id = @business_id
            AND status = 'finalized'
            AND CAST(created_at AS DATE) BETWEEN @from AND @to
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from', sql.Date, from)
        .input('to', sql.Date, to)
        .query(`
          SELECT ISNULL(SUM(amount), 0) AS total_expenses
          FROM expenses
          WHERE business_id = @business_id
            AND expense_date BETWEEN @from AND @to
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from', sql.Date, from)
        .input('to', sql.Date, to)
        .query(`
          SELECT d.day,
                 ISNULL(b.revenue, 0) AS revenue,
                 ISNULL(e.expenses, 0) AS expenses,
                 ISNULL(b.revenue, 0) - ISNULL(e.expenses, 0) AS profit
          FROM (
            SELECT CAST(created_at AS DATE) AS day FROM bills
            WHERE business_id = @business_id AND status = 'finalized'
              AND CAST(created_at AS DATE) BETWEEN @from AND @to
            UNION
            SELECT expense_date AS day FROM expenses
            WHERE business_id = @business_id AND expense_date BETWEEN @from AND @to
          ) d
          LEFT JOIN (
            SELECT CAST(created_at AS DATE) AS day, SUM(total) AS revenue
            FROM bills WHERE business_id = @business_id AND status = 'finalized'
              AND CAST(created_at AS DATE) BETWEEN @from AND @to
            GROUP BY CAST(created_at AS DATE)
          ) b ON b.day = d.day
          LEFT JOIN (
            SELECT expense_date AS day, SUM(amount) AS expenses
            FROM expenses WHERE business_id = @business_id
              AND expense_date BETWEEN @from AND @to
            GROUP BY expense_date
          ) e ON e.day = d.day
          ORDER BY d.day
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from', sql.Date, from)
        .input('to', sql.Date, to)
        .query(`
          SELECT category, SUM(amount) AS total
          FROM expenses
          WHERE business_id = @business_id AND expense_date BETWEEN @from AND @to
          GROUP BY category ORDER BY total DESC
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from', sql.Date, from)
        .input('to', sql.Date, to)
        .query(`
          SELECT payment_mode, COUNT(*) AS count, SUM(total) AS total
          FROM bills
          WHERE business_id = @business_id AND status = 'finalized'
            AND CAST(created_at AS DATE) BETWEEN @from AND @to
          GROUP BY payment_mode ORDER BY total DESC
        `),
    ]);

    const bill = billResult.recordset[0];
    const revenue = parseFloat(bill.total_revenue);
    const expenses = parseFloat(expenseResult.recordset[0].total_expenses);

    return res.json({
      from,
      to,
      bill_count: bill.bill_count,
      total_revenue: revenue,
      total_tax: parseFloat(bill.total_tax),
      total_expenses: expenses,
      net_profit: revenue - expenses,
      by_payment_mode: {
        cash: parseFloat(bill.cash),
        upi: parseFloat(bill.upi),
        card: parseFloat(bill.card),
        credit: parseFloat(bill.credit),
        other: parseFloat(bill.other),
      },
      daily: dailyResult.recordset.map(r => ({
        day: r.day instanceof Date ? r.day.toISOString().slice(0, 10) : String(r.day),
        revenue: parseFloat(r.revenue),
        expenses: parseFloat(r.expenses),
        profit: parseFloat(r.profit),
      })),
      expenses_by_category: expCatResult.recordset.map(r => ({
        category: r.category,
        total: parseFloat(r.total),
      })),
      revenue_by_payment_mode: payModeResult.recordset.map(r => ({
        mode: r.payment_mode,
        count: r.count,
        total: parseFloat(r.total),
      })),
    });
  } catch (err) {
    console.error('Summary report error:', err.message);
    return res.status(500).json({ error: 'Failed to generate report' });
  }
});

module.exports = router;
