const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

// GET /api/reports/today
router.get('/today', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const today = new Date().toISOString().slice(0, 10);

    const result = await pool.request()
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
      `);

    const row = result.recordset[0];
    return res.json({
      date: today,
      bill_count: row.bill_count,
      total_revenue: parseFloat(row.total_revenue),
      by_payment_mode: {
        cash: parseFloat(row.cash),
        upi: parseFloat(row.upi),
        card: parseFloat(row.card),
        credit: parseFloat(row.credit),
        other: parseFloat(row.other),
      },
    });
  } catch (err) {
    console.error('Today report error:', err.message);
    return res.status(500).json({ error: 'Failed to generate report' });
  }
});

module.exports = router;
