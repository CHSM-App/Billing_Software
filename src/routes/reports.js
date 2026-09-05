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
            ISNULL(SUM(round_off), 0) AS total_round_off,
            -- Payment-mode figures are the actual money collected: the payable
            -- (total - discount) plus the round_off adjustment.
            ISNULL(SUM(CASE WHEN payment_mode = 'cash'   THEN total - discount_amount + round_off ELSE 0 END), 0) AS cash,
            ISNULL(SUM(CASE WHEN payment_mode = 'upi'    THEN total - discount_amount + round_off ELSE 0 END), 0) AS upi,
            ISNULL(SUM(CASE WHEN payment_mode = 'card'   THEN total - discount_amount + round_off ELSE 0 END), 0) AS card,
            ISNULL(SUM(CASE WHEN payment_mode = 'credit' THEN total - discount_amount + round_off ELSE 0 END), 0) AS credit,
            ISNULL(SUM(CASE WHEN payment_mode = 'other'  THEN total - discount_amount + round_off ELSE 0 END), 0) AS other
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
    const roundOff  = parseFloat(bill.total_round_off);
    const expenses  = parseFloat(expenseResult.recordset[0].total_expenses);
    // Net revenue = actual money collected = gross - discount + round_off.
    const netRevenue = parseFloat((revenue - discount + roundOff).toFixed(2));

    return res.json({
      date: dateStr,
      bill_count:      bill.bill_count,
      total_revenue:   revenue,
      total_discount:  discount,
      total_round_off: roundOff,
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
          --   net amount     = total - discount_amount + round_off (the money
          --                    actually collected, what total sales uses).
          SELECT
            COUNT(*) AS bill_count,
            ISNULL(SUM(net), 0) AS total_revenue,
            ISNULL(SUM(discount_amount), 0) AS total_discount,
            ISNULL(SUM(round_off), 0) AS total_round_off,
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
              round_off,
              tax_amount,
              (total - discount_amount + round_off) AS net,
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
            SELECT CAST(created_at AS DATE) AS day, SUM(total - discount_amount + round_off) AS revenue
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
          SELECT payment_mode, COUNT(*) AS count, SUM(total - discount_amount + round_off) AS total
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
                 b.bill_number, b.total, b.discount_amount, b.round_off, b.created_at,
                 b.customer_name, t.table_number
          FROM bills b
          LEFT JOIN tables t ON t.id = b.table_id
          WHERE b.business_id = @business_id AND b.status = 'finalized'
            AND b.created_at >= @from_dt AND b.created_at < @to_dt
          ORDER BY b.created_at DESC
        `),
    ]);

    const bill      = billResult.recordset[0];
    // total_revenue is the money collected: SUM(total - discount + round_off),
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
      total_round_off: parseFloat(bill.total_round_off),
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
        round_off:       parseFloat(r.round_off || 0),
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
               SUM(total - discount_amount + round_off) AS revenue
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

// ---------------------------------------------------------------------------
// GET /api/reports/gstr1?from=YYYY-MM-DD&to=YYYY-MM-DD
//
// GSTR-1 outward-supplies summary for a filing period.
//
// SCOPE: bills carry no buyer GSTIN (the schema has no such column), so every
// sale is treated as B2C. That means the return is reported as:
//   • B2CS  — consolidated rate-wise taxable value + tax (NOT invoice-wise)
//   • HSN   — HSN/SAC-wise quantity, taxable value and tax
// There is deliberately no B2B section: emitting one would require buyer GSTINs
// this system does not capture.
//
// Money rules mirror the printed receipt exactly (routes/receipt.js), so the
// return reconciles with what customers were actually charged:
//   taxable = quantity × unit_price          (unit_price is always the NET rate)
//   lineTax = line_total − taxable           (pre-discount, as stored)
//   both scaled by discountedNet/subtotal    (tax is charged on the discounted net)
// Bills with GST disabled contribute nothing — their stored tax is ignored on
// the receipt too, so including it here would over-report the liability.
// Intra-state supply is assumed (CGST/SGST split, no IGST): the business's own
// state is the place of supply for a counter sale.
// ---------------------------------------------------------------------------
router.get('/gstr1', requireAuth, ownerOnly, async (req, res) => {
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

    // One pass over the period's line items. `ratio` re-applies the bill-level
    // discount to each line so the summed taxable value matches bills.tax_amount.
    const lineSql = `
      WITH scoped AS (
        SELECT
          bi.tax_rate,
          bi.hsn_code,
          bi.quantity,
          bi.unit_price,
          bi.line_total,
          CASE WHEN b.subtotal > 0
               THEN (b.subtotal - ISNULL(b.discount_amount, 0)) / b.subtotal
               ELSE 1 END AS ratio
        FROM bill_items bi
        INNER JOIN bills b      ON b.id = bi.bill_id
        INNER JOIN businesses bs ON bs.id = b.business_id
        WHERE b.business_id = @business_id
          AND b.created_at >= @from_dt
          AND b.created_at <= @to_dt
          AND ISNULL(bs.gst_enabled, 0) = 1
          AND bi.tax_rate IS NOT NULL
          AND bi.tax_rate > 0
      )
      SELECT
        tax_rate,
        hsn_code,
        SUM(quantity)                                        AS qty,
        SUM(quantity * unit_price * ratio)                   AS taxable,
        SUM((line_total - quantity * unit_price) * ratio)    AS tax
      FROM scoped
      GROUP BY tax_rate, hsn_code
    `;

    const [linesResult, billsResult, profileResult] = await Promise.all([
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(lineSql),
      // Invoice count/value for the period, for the summary header.
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(`
          SELECT
            COUNT(*) AS bill_count,
            ISNULL(SUM(b.total - ISNULL(b.discount_amount, 0) + ISNULL(b.round_off, 0)), 0)
              AS invoice_value
          FROM bills b
          INNER JOIN businesses bs ON bs.id = b.business_id
          WHERE b.business_id = @business_id
            AND b.created_at >= @from_dt
            AND b.created_at <= @to_dt
            AND ISNULL(bs.gst_enabled, 0) = 1
        `),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT name, gst_number, state, default_sac_code
          FROM businesses WHERE id = @business_id
        `),
    ]);

    const profile = profileResult.recordset[0] || {};
    const defaultSac = profile.default_sac_code || '';
    const r2 = (n) => Math.round(Number(n) * 100) / 100;

    // --- B2CS: consolidated by rate -----------------------------------------
    const byRate = new Map();
    for (const row of linesResult.recordset) {
      const rate = Number(row.tax_rate);
      const g = byRate.get(rate) || { rate, taxable: 0, tax: 0 };
      g.taxable += Number(row.taxable);
      g.tax     += Number(row.tax);
      byRate.set(rate, g);
    }
    const b2cs = [...byRate.values()]
      .sort((a, b) => a.rate - b.rate)
      .map((g) => {
        // Odd paisa to CGST so the halves add back to the total exactly —
        // same rule the receipt uses (gstHalves in routes/receipt.js).
        const paise = Math.round(g.tax * 100);
        return {
          rate: g.rate,
          taxable_value: r2(g.taxable),
          cgst: r2(((paise + 1) >> 1) / 100),
          sgst: r2((paise >> 1) / 100),
          total_tax: r2(g.tax),
        };
      });

    // --- HSN summary: by HSN/SAC then rate -----------------------------------
    const byHsn = new Map();
    for (const row of linesResult.recordset) {
      const code = row.hsn_code || defaultSac || '';
      const rate = Number(row.tax_rate);
      const key = `${code}|${rate}`;
      const g = byHsn.get(key) || { hsn: code, rate, qty: 0, taxable: 0, tax: 0 };
      g.qty     += Number(row.qty);
      g.taxable += Number(row.taxable);
      g.tax     += Number(row.tax);
      byHsn.set(key, g);
    }
    const hsn = [...byHsn.values()]
      .sort((a, b) => (a.hsn === b.hsn ? a.rate - b.rate : a.hsn < b.hsn ? -1 : 1))
      .map((g) => {
        const paise = Math.round(g.tax * 100);
        return {
          hsn: g.hsn,
          rate: g.rate,
          quantity: r2(g.qty),
          taxable_value: r2(g.taxable),
          cgst: r2(((paise + 1) >> 1) / 100),
          sgst: r2((paise >> 1) / 100),
          total_tax: r2(g.tax),
        };
      });

    const bills = billsResult.recordset[0] || {};
    const totalTaxable = r2(b2cs.reduce((s, r) => s + r.taxable_value, 0));
    const totalTax     = r2(b2cs.reduce((s, r) => s + r.total_tax, 0));

    return res.json({
      from: fromStr,
      to: toStr,
      business: {
        name: profile.name || '',
        gstin: profile.gst_number || '',
        state: profile.state || '',
      },
      // Every sale is B2C — see the scope note above.
      supply_type: 'b2c',
      totals: {
        bill_count: Number(bills.bill_count || 0),
        invoice_value: r2(bills.invoice_value || 0),
        taxable_value: totalTaxable,
        cgst: r2(b2cs.reduce((s, r) => s + r.cgst, 0)),
        sgst: r2(b2cs.reduce((s, r) => s + r.sgst, 0)),
        total_tax: totalTax,
      },
      b2cs,
      hsn,
    });
  } catch (err) {
    logger.error({ err }, 'gstr1 report failed');
    return res.status(500).json({ error: 'Failed to generate GSTR-1 report' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/reports/gstr2?from=YYYY-MM-DD&to=YYYY-MM-DD
//
// ITC (input tax credit) summary of recorded purchases.
//
// NOT A FILED RETURN: GSTR-2 was suspended in 2017 and is not filed today. What
// this produces is the inward-supply summary a business needs to (a) reconcile
// against GSTR-2B and (b) fill GSTR-3B Table 4. It is named GSTR-2 because that
// is what people ask for.
//
// Money rules mirror the vendor bill routes exactly:
//   taxable = quantity x unit_price          (unit_price is always the NET rate)
//   lineTax = line_total - taxable
//   both scaled by discountedNet/subtotal    (tax is charged on the discounted net)
//
// ITC rules enforced HERE, not merely in the UI:
//   * vendor_gstin NULL  -> unregistered vendor, cannot pass credit -> ZERO ITC
//   * itc_eligible = 0   -> blocked credit (s.17(5)) -> reported, not claimable
//   * reverse_charge = 1 -> buyer pays the tax; that ITC is claimed separately
//                           after payment, so it is excluded here too
// Folding any of these into the claimable figure would overstate ITC.
// ---------------------------------------------------------------------------
router.get('/gstr2', requireAuth, ownerOnly, async (req, res) => {
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

    // Purchases are dated by the VENDOR invoice date, not by entry time, so
    // this filters on invoice_date (a DATE column) rather than created_at.
    const lineSql = `
      WITH scoped AS (
        SELECT
          vb.id            AS bill_id,
          vb.vendor_gstin,
          vb.vendor_name,
          vb.is_interstate,
          vb.itc_eligible,
          vb.reverse_charge,
          vbi.tax_rate,
          vbi.hsn_code,
          vbi.quantity,
          vbi.unit_price,
          vbi.line_total,
          CASE WHEN vb.subtotal > 0
               THEN (vb.subtotal - ISNULL(vb.discount_amount, 0)) / vb.subtotal
               ELSE 1 END AS ratio
        FROM vendor_bill_items vbi
        INNER JOIN vendor_bills vb ON vb.id = vbi.vendor_bill_id
        WHERE vb.business_id = @business_id
          AND vb.invoice_date >= @from_date
          AND vb.invoice_date <= @to_date
          AND vbi.tax_rate IS NOT NULL
          AND vbi.tax_rate > 0
      )
      SELECT
        vendor_gstin, vendor_name, is_interstate, itc_eligible, reverse_charge,
        tax_rate, hsn_code,
        SUM(quantity)                                          AS qty,
        SUM(quantity * unit_price * ratio)                     AS taxable,
        SUM((line_total - quantity * unit_price) * ratio)      AS tax,
        COUNT(DISTINCT bill_id)                                AS bill_count
      FROM scoped
      GROUP BY vendor_gstin, vendor_name, is_interstate, itc_eligible,
               reverse_charge, tax_rate, hsn_code`;

    const [linesResult, billsResult, profileResult] = await Promise.all([
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_date',   sql.Date,             fromStr)
        .input('to_date',     sql.Date,             toStr)
        .query(lineSql),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_date',   sql.Date,             fromStr)
        .input('to_date',     sql.Date,             toStr)
        .query(`
          SELECT COUNT(*) AS bill_count, ISNULL(SUM(total), 0) AS invoice_value
          FROM vendor_bills
          WHERE business_id = @business_id
            AND invoice_date >= @from_date AND invoice_date <= @to_date`),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`SELECT name, gst_number, state FROM businesses WHERE id = @business_id`),
    ]);

    const profile = profileResult.recordset[0] || {};
    const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
    // Odd paisa to CGST so the halves add back exactly - same rule as /gstr1.
    const halves = (tax) => {
      const p = Math.round((Number(tax) || 0) * 100);
      return [((p + 1) >> 1) / 100, (p >> 1) / 100];
    };

    const byRate = new Map();
    const byVendor = new Map();
    const byHsn = new Map();
    const unregistered = { taxable_value: 0, total_tax: 0 };
    let totTaxable = 0, totCgst = 0, totSgst = 0, totIgst = 0, totTax = 0;
    let itcEligibleTax = 0, itcIneligibleTax = 0, reverseChargeTax = 0;

    for (const row of linesResult.recordset) {
      const taxable = Number(row.taxable);
      const tax = Number(row.tax);
      const inter = !!row.is_interstate;
      const registered = !!row.vendor_gstin;
      // Credit is claimable only from a registered vendor, on an eligible
      // (non-blocked) purchase, and not under reverse charge.
      const claimable = registered && !!row.itc_eligible && !row.reverse_charge;

      let cgst = 0, sgst = 0, igst = 0;
      if (inter) igst = tax; else [cgst, sgst] = halves(tax);

      totTaxable += taxable; totTax += tax;
      totCgst += cgst; totSgst += sgst; totIgst += igst;
      if (claimable) itcEligibleTax += tax;
      else if (row.reverse_charge) reverseChargeTax += tax;
      else itcIneligibleTax += tax;

      if (!registered) {
        unregistered.taxable_value += taxable;
        unregistered.total_tax += tax;
      }

      const rate = Number(row.tax_rate);
      const gr = byRate.get(rate) || { rate, taxable: 0, tax: 0, cgst: 0, sgst: 0, igst: 0, itc: 0 };
      gr.taxable += taxable; gr.tax += tax; gr.cgst += cgst; gr.sgst += sgst; gr.igst += igst;
      if (claimable) gr.itc += tax;
      byRate.set(rate, gr);

      if (registered) {
        const key = row.vendor_gstin;
        const gv = byVendor.get(key) || {
          gstin: key, vendor_name: row.vendor_name,
          taxable: 0, tax: 0, cgst: 0, sgst: 0, igst: 0,
          itc_eligible: !!row.itc_eligible,
        };
        gv.taxable += taxable; gv.tax += tax;
        gv.cgst += cgst; gv.sgst += sgst; gv.igst += igst;
        byVendor.set(key, gv);
      }

      const hsnKey = `${row.hsn_code || ''}|${rate}`;
      const gh = byHsn.get(hsnKey) || {
        hsn: row.hsn_code || '', rate, quantity: 0,
        taxable: 0, tax: 0, cgst: 0, sgst: 0, igst: 0,
      };
      gh.quantity += Number(row.qty);
      gh.taxable += taxable; gh.tax += tax;
      gh.cgst += cgst; gh.sgst += sgst; gh.igst += igst;
      byHsn.set(hsnKey, gh);
    }

    const bills = billsResult.recordset[0] || {};

    return res.json({
      from: fromStr,
      to: toStr,
      business: {
        name: profile.name || '',
        gstin: profile.gst_number || '',
        state: profile.state || '',
      },
      totals: {
        bill_count: Number(bills.bill_count || 0),
        invoice_value: r2(bills.invoice_value || 0),
        taxable_value: r2(totTaxable),
        cgst: r2(totCgst),
        sgst: r2(totSgst),
        igst: r2(totIgst),
        total_tax: r2(totTax),
        itc_eligible_tax: r2(itcEligibleTax),
        itc_ineligible_tax: r2(itcIneligibleTax),
        reverse_charge_tax: r2(reverseChargeTax),
      },
      by_rate: [...byRate.values()].sort((a, b) => a.rate - b.rate).map((g) => ({
        rate: g.rate,
        taxable_value: r2(g.taxable),
        cgst: r2(g.cgst), sgst: r2(g.sgst), igst: r2(g.igst),
        total_tax: r2(g.tax),
        itc_eligible_tax: r2(g.itc),
      })),
      b2b: [...byVendor.values()]
        .sort((a, b) => b.taxable - a.taxable)
        .map((g) => ({
          gstin: g.gstin,
          vendor_name: g.vendor_name,
          taxable_value: r2(g.taxable),
          cgst: r2(g.cgst), sgst: r2(g.sgst), igst: r2(g.igst),
          total_tax: r2(g.tax),
          itc_eligible: g.itc_eligible,
        })),
      unregistered: {
        taxable_value: r2(unregistered.taxable_value),
        total_tax: r2(unregistered.total_tax),
      },
      hsn: [...byHsn.values()]
        .sort((a, b) => (a.hsn === b.hsn ? a.rate - b.rate : a.hsn < b.hsn ? -1 : 1))
        .map((g) => ({
          hsn: g.hsn,
          rate: g.rate,
          quantity: r2(g.quantity),
          taxable_value: r2(g.taxable),
          cgst: r2(g.cgst), sgst: r2(g.sgst), igst: r2(g.igst),
          total_tax: r2(g.tax),
        })),
    });
  } catch (err) {
    logger.error({ err }, 'gstr2 report failed');
    return res.status(500).json({ error: 'Failed to generate GSTR-2 report' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/reports/gstr2b/reconcile
//
// Matches the GSTR-2B statement (downloaded from the GST portal) against the
// vendor bills recorded here.
//
// GSTR-2B CANNOT be produced by this app: the portal generates it from the
// suppliers' own GSTR-1 filings. The app's job is to import it and show what
// agrees, what differs, and - the part that costs real money - which invoices a
// supplier never filed, because under s.16(2)(aa) ITC cannot be claimed on those.
//
// STATELESS by design: nothing is persisted, so the reconciliation can be re-run
// any time and there is no stale state to invalidate.
//
// Accepts either shape:
//   { from, to, invoices: [...] }   <- app pre-parses the portal JSON (normal)
//   { from, to, gstr2b: <raw> }     <- raw portal JSON (kept for a future
//                                      file-picker path; note the global body
//                                      limit is 100KB, so large files must use
//                                      the pre-parsed form)
// ---------------------------------------------------------------------------
router.post('/gstr2b/reconcile', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    let fromStr, toStr;
    try {
      fromStr = requireDateParam(req.body.from, 'from');
      toStr   = requireDateParam(req.body.to,   'to');
    } catch (e) {
      return res.status(400).json({ error: e.message });
    }

    const num = (v) => Number(v) || 0;
    // The portal writes dates as DD-MM-YYYY; books store YYYY-MM-DD. Getting
    // this backwards silently makes EVERY invoice look date-mismatched.
    const toIsoDate = (s) => {
      const t = String(s || '').trim();
      if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t;
      const m = t.match(/^(\d{2})[-/](\d{2})[-/](\d{4})$/);
      return m ? `${m[3]}-${m[2]}-${m[1]}` : t;
    };

    let invoices = [];
    if (Array.isArray(req.body.invoices)) {
      invoices = req.body.invoices.map((i) => ({
        gstin: String(i.gstin || '').trim().toUpperCase(),
        vendor_name: i.vendor_name || '',
        invoice_number: String(i.invoice_number || '').trim(),
        invoice_date: toIsoDate(i.invoice_date),
        invoice_value: num(i.invoice_value),
        taxable_value: num(i.taxable_value),
        cgst: num(i.cgst), sgst: num(i.sgst),
        igst: num(i.igst), cess: num(i.cess),
      }));
    } else if (req.body.gstr2b) {
      const raw = req.body.gstr2b;
      const b2b = (raw.data && raw.data.docdata && raw.data.docdata.b2b)
        || (raw.data && raw.data.b2b)
        || (raw.data && raw.data.docsumm && raw.data.docsumm.b2b)
        || (raw.docdata && raw.docdata.b2b)
        || raw.b2b;
      if (!Array.isArray(b2b) || !b2b.length) {
        return res.status(400).json({
          error: 'Unrecognised GSTR-2B file - expected the JSON downloaded from the GST portal',
        });
      }
      for (const supplier of b2b) {
        for (const inv of (supplier.inv || [])) {
          let taxable = 0, cgst = 0, sgst = 0, igst = 0, cess = 0;
          for (const it of (inv.itms || [])) {
            const d = it.itm_det || {};
            taxable += num(d.txval); cgst += num(d.camt);
            sgst += num(d.samt); igst += num(d.iamt); cess += num(d.csamt);
          }
          invoices.push({
            gstin: String(supplier.ctin || '').trim().toUpperCase(),
            vendor_name: supplier.trdnm || '',
            invoice_number: String(inv.inum || '').trim(),
            invoice_date: toIsoDate(inv.idt),
            invoice_value: num(inv.val),
            taxable_value: taxable, cgst, sgst, igst, cess,
          });
        }
      }
    } else {
      return res.status(400).json({
        error: 'Provide the GSTR-2B data as "invoices" or "gstr2b"',
      });
    }

    // Books side, widened by 45 days each way: a bill entered under a
    // neighbouring month's date is the single most common real mismatch, and
    // restricting to the exact period would manufacture false "missing" rows.
    const widen = (d, days) => {
      const dt = new Date(`${d}T00:00:00Z`);
      dt.setUTCDate(dt.getUTCDate() + days);
      return dt.toISOString().slice(0, 10);
    };

    const booksResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('from_date',   sql.Date,             widen(fromStr, -45))
      .input('to_date',     sql.Date,             widen(toStr, 45))
      .query(`
        SELECT id, vendor_name, vendor_gstin, invoice_number, invoice_date,
               subtotal, tax_amount, cgst_amount, sgst_amount, igst_amount, total
        FROM vendor_bills
        WHERE business_id = @business_id
          AND vendor_gstin IS NOT NULL
          AND invoice_date >= @from_date AND invoice_date <= @to_date`);

    const books = booksResult.recordset.map((b) => {
      const iso = b.invoice_date.toISOString().slice(0, 10);
      return {
        vendor_bill_id: b.id,
        vendor_name: b.vendor_name,
        gstin: String(b.vendor_gstin).trim().toUpperCase(),
        invoice_number: String(b.invoice_number).trim(),
        invoice_date: iso,
        taxable_value: parseFloat(b.subtotal),
        cgst: parseFloat(b.cgst_amount),
        sgst: parseFloat(b.sgst_amount),
        igst: parseFloat(b.igst_amount),
        total_tax: parseFloat(b.tax_amount),
        total: parseFloat(b.total),
        period_mismatch: !(iso >= fromStr && iso <= toStr),
        _used: false,
      };
    });

    // Vendors write "INV-0231" on paper and "INV231" on the portal constantly,
    // so the loose key drops punctuation and leading zeros in numeric runs.
    const loose = (s) => String(s || '').toUpperCase()
      .replace(/[^A-Z0-9]/g, '').replace(/0+(\d)/g, '$1');
    // 2B values are portal-rounded; compare with a one-rupee tolerance.
    const near = (a, b) => Math.abs(num(a) - num(b)) <= 1.0;

    const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
    const matched = [];
    const missingInBooks = [];

    for (const inv of invoices) {
      const invTax = r2(inv.cgst + inv.sgst + inv.igst);

      // Pass 1: exact.
      let hit = books.find((b) => !b._used
        && b.gstin === inv.gstin
        && b.invoice_number.toUpperCase() === inv.invoice_number.toUpperCase()
        && b.invoice_date === inv.invoice_date
        && near(b.taxable_value, inv.taxable_value));

      // Pass 2: loose - same vendor, recognisably the same invoice number.
      // Most real mismatches are a typo'd date or a rupee difference, not a
      // genuinely missing bill, so these match WITH their differences listed
      // rather than being reported as missing.
      if (!hit) {
        hit = books.find((b) => !b._used
          && b.gstin === inv.gstin
          && loose(b.invoice_number) === loose(inv.invoice_number));
      }

      if (hit) {
        hit._used = true;
        const differences = [];
        if (hit.invoice_date !== inv.invoice_date) differences.push('invoice_date');
        if (!near(hit.taxable_value, inv.taxable_value)) differences.push('taxable_value');
        if (!near(hit.total_tax, invTax)) differences.push('tax_amount');
        matched.push({
          vendor_bill_id: hit.vendor_bill_id,
          gstin: inv.gstin,
          vendor_name: inv.vendor_name || hit.vendor_name,
          invoice_number: inv.invoice_number,
          invoice_date: inv.invoice_date,
          books: {
            taxable_value: hit.taxable_value, cgst: hit.cgst,
            sgst: hit.sgst, igst: hit.igst, total_tax: hit.total_tax,
            invoice_date: hit.invoice_date,
          },
          gstr2b: {
            taxable_value: r2(inv.taxable_value), cgst: r2(inv.cgst),
            sgst: r2(inv.sgst), igst: r2(inv.igst), total_tax: invTax,
          },
          differences,
          period_mismatch: hit.period_mismatch,
        });
      } else {
        missingInBooks.push({
          gstin: inv.gstin,
          vendor_name: inv.vendor_name,
          invoice_number: inv.invoice_number,
          invoice_date: inv.invoice_date,
          invoice_value: r2(inv.invoice_value),
          taxable_value: r2(inv.taxable_value),
          cgst: r2(inv.cgst), sgst: r2(inv.sgst), igst: r2(inv.igst),
          total_tax: invTax,
        });
      }
    }

    // Anything left in books that 2B never mentioned: the supplier has not
    // filed (or filed under a different period) - ITC at risk.
    const missingIn2b = books.filter((b) => !b._used).map((b) => ({
      vendor_bill_id: b.vendor_bill_id,
      vendor_name: b.vendor_name,
      gstin: b.gstin,
      invoice_number: b.invoice_number,
      invoice_date: b.invoice_date,
      taxable_value: b.taxable_value,
      total_tax: b.total_tax,
      total: b.total,
      period_mismatch: b.period_mismatch,
    }));

    const sum = (arr, f) => r2(arr.reduce((s, x) => s + f(x), 0));
    const withDiff = matched.filter((m) => m.differences.length > 0);
    const clean = matched.filter((m) => m.differences.length === 0);

    const itcAvailable2b = sum(invoices, (i) => i.cgst + i.sgst + i.igst);
    const itcClaimedBooks = r2(sum(clean, (m) => m.books.total_tax)
      + sum(withDiff, (m) => m.books.total_tax)
      + sum(missingIn2b, (m) => m.total_tax));

    return res.json({
      from: fromStr,
      to: toStr,
      summary: {
        matched_count: clean.length,
        matched_tax: sum(clean, (m) => m.books.total_tax),
        mismatch_count: withDiff.length,
        mismatch_tax: sum(withDiff, (m) => m.books.total_tax),
        missing_in_books_count: missingInBooks.length,
        missing_in_books_tax: sum(missingInBooks, (m) => m.total_tax),
        missing_in_2b_count: missingIn2b.length,
        missing_in_2b_tax: sum(missingIn2b, (m) => m.total_tax),
        itc_available_2b: itcAvailable2b,
        itc_claimed_books: itcClaimedBooks,
        // The number the owner actually cares about: negative means more was
        // claimed in books than the portal will allow.
        itc_difference: r2(itcAvailable2b - itcClaimedBooks),
      },
      matched: clean,
      mismatched: withDiff,
      missing_in_books: missingInBooks,
      missing_in_2b: missingIn2b,
    });
  } catch (err) {
    logger.error({ err }, 'gstr2b reconcile failed');
    return res.status(500).json({ error: 'Failed to reconcile GSTR-2B' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/reports/gstr3b?from=YYYY-MM-DD&to=YYYY-MM-DD
//
// GSTR-3B is the summary return that IS still filed, monthly. This assembles
// the figures for the tables a small retailer/restaurant actually fills:
//
//   Table 3.1(a) - outward taxable supplies         <- bills (same basis as /gstr1)
//   Table 4(A)(5) - ITC on all other inward supplies <- vendor bills (/gstr2 rules)
//   Table 6.1    - tax payable, less ITC, = payable in cash
//
// It deliberately does NOT compute 3.1(b)-(e), 3.2, 4(B) reversals or Table 5:
// the app holds no data for zero-rated/exempt/nil-rated supplies, imports, ISD
// credit or reversals, and inventing zeroes for them would look authoritative
// while being unverified. Those cells are returned as null with a note.
//
// Set-off follows the CGST/SGST rule: IGST credit is used first (against IGST
// liability), then whatever remains may offset CGST and then SGST.
// ---------------------------------------------------------------------------
router.get('/gstr3b', requireAuth, ownerOnly, async (req, res) => {
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
    const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
    const halves = (tax) => {
      const p = Math.round((Number(tax) || 0) * 100);
      return [((p + 1) >> 1) / 100, (p >> 1) / 100];
    };

    const [outward, inward, profileResult] = await Promise.all([
      // Outward: identical basis to /gstr1 so Table 3.1 always agrees with it.
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_dt',     sql.DateTime2,        fromDt)
        .input('to_dt',       sql.DateTime2,        toDt)
        .query(`
          WITH scoped AS (
            SELECT bi.quantity, bi.unit_price, bi.line_total,
              CASE WHEN b.subtotal > 0
                   THEN (b.subtotal - ISNULL(b.discount_amount, 0)) / b.subtotal
                   ELSE 1 END AS ratio
            FROM bill_items bi
            INNER JOIN bills b       ON b.id = bi.bill_id
            INNER JOIN businesses bs ON bs.id = b.business_id
            WHERE b.business_id = @business_id
              AND b.created_at >= @from_dt AND b.created_at <= @to_dt
              AND ISNULL(bs.gst_enabled, 0) = 1
              AND bi.tax_rate IS NOT NULL AND bi.tax_rate > 0
          )
          SELECT
            ISNULL(SUM(quantity * unit_price * ratio), 0)                AS taxable,
            ISNULL(SUM((line_total - quantity * unit_price) * ratio), 0) AS tax
          FROM scoped`),
      // Inward: claimable ITC only - registered vendor, eligible, not RCM.
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('from_date',   sql.Date,             fromStr)
        .input('to_date',     sql.Date,             toStr)
        .query(`
          WITH scoped AS (
            SELECT vb.is_interstate, vbi.quantity, vbi.unit_price, vbi.line_total,
              CASE WHEN vb.subtotal > 0
                   THEN (vb.subtotal - ISNULL(vb.discount_amount, 0)) / vb.subtotal
                   ELSE 1 END AS ratio
            FROM vendor_bill_items vbi
            INNER JOIN vendor_bills vb ON vb.id = vbi.vendor_bill_id
            WHERE vb.business_id = @business_id
              AND vb.invoice_date >= @from_date AND vb.invoice_date <= @to_date
              AND vb.vendor_gstin IS NOT NULL
              AND vb.itc_eligible = 1
              AND vb.reverse_charge = 0
              AND vbi.tax_rate IS NOT NULL AND vbi.tax_rate > 0
          )
          SELECT
            ISNULL(SUM(CASE WHEN is_interstate = 0
                       THEN (line_total - quantity * unit_price) * ratio ELSE 0 END), 0) AS intra_tax,
            ISNULL(SUM(CASE WHEN is_interstate = 1
                       THEN (line_total - quantity * unit_price) * ratio ELSE 0 END), 0) AS inter_tax
          FROM scoped`),
      pool.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`SELECT name, gst_number, state FROM businesses WHERE id = @business_id`),
    ]);

    const o = outward.recordset[0] || {};
    const i = inward.recordset[0] || {};
    const profile = profileResult.recordset[0] || {};

    // Outward liability. Counter sales are intra-state, so tax splits
    // CGST/SGST; the app records no inter-state outward supply today.
    const outTaxable = Number(o.taxable) || 0;
    const outTax = Number(o.tax) || 0;
    const [outCgst, outSgst] = halves(outTax);

    // Available credit.
    const [inCgst, inSgst] = halves(Number(i.intra_tax) || 0);
    const inIgst = r2(Number(i.inter_tax) || 0);

    // Set-off. IGST credit is used first against IGST liability (nil here),
    // then the remainder may offset CGST and SGST in that order.
    let igstCredit = inIgst;
    const igstLiability = 0;
    const igstUsedOnIgst = Math.min(igstCredit, igstLiability);
    igstCredit = r2(igstCredit - igstUsedOnIgst);

    const cgstFromCgst = Math.min(inCgst, outCgst);
    let cgstDue = r2(outCgst - cgstFromCgst);
    const cgstFromIgst = Math.min(igstCredit, cgstDue);
    igstCredit = r2(igstCredit - cgstFromIgst);
    cgstDue = r2(cgstDue - cgstFromIgst);

    const sgstFromSgst = Math.min(inSgst, outSgst);
    let sgstDue = r2(outSgst - sgstFromSgst);
    const sgstFromIgst = Math.min(igstCredit, sgstDue);
    igstCredit = r2(igstCredit - sgstFromIgst);
    sgstDue = r2(sgstDue - sgstFromIgst);

    return res.json({
      from: fromStr,
      to: toStr,
      business: {
        name: profile.name || '',
        gstin: profile.gst_number || '',
        state: profile.state || '',
      },
      // Table 3.1(a): outward taxable supplies (other than zero-rated etc.)
      table_3_1: {
        taxable_value: r2(outTaxable),
        igst: 0,
        cgst: outCgst,
        sgst: outSgst,
        cess: 0,
      },
      // Table 4(A)(5): ITC available, "all other ITC"
      table_4: {
        igst: inIgst,
        cgst: inCgst,
        sgst: inSgst,
        cess: 0,
        total: r2(inIgst + inCgst + inSgst),
      },
      // Table 6.1: liability, credit utilised, and the cash still payable
      table_6_1: {
        liability: { igst: 0, cgst: outCgst, sgst: outSgst, total: r2(outTax) },
        paid_through_itc: {
          igst: 0,
          cgst: r2(cgstFromCgst + cgstFromIgst),
          sgst: r2(sgstFromSgst + sgstFromIgst),
          total: r2(cgstFromCgst + cgstFromIgst + sgstFromSgst + sgstFromIgst),
        },
        payable_in_cash: {
          igst: 0, cgst: cgstDue, sgst: sgstDue,
          total: r2(cgstDue + sgstDue),
        },
        itc_balance_carried: r2(
          Math.max(inCgst - cgstFromCgst, 0)
          + Math.max(inSgst - sgstFromSgst, 0)
          + igstCredit),
      },
      // Cells the app holds no data for. Returned as null rather than 0 so the
      // UI can say "not tracked" instead of implying a verified nil.
      not_tracked: {
        zero_rated_supplies: null,
        nil_rated_exempt_supplies: null,
        non_gst_outward_supplies: null,
        inward_reverse_charge_supplies: null,
        itc_reversals: null,
        import_of_goods_services: null,
      },
    });
  } catch (err) {
    logger.error({ err }, 'gstr3b report failed');
    return res.status(500).json({ error: 'Failed to generate GSTR-3B report' });
  }
});

module.exports = router;
