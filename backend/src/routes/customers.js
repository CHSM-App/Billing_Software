// =============================================================================
// /api/customers — the owner's customer base and WhatsApp campaigns.
//
// Customers live in `customers` (migration 046), filled from bills one way —
// see src/customers.js. Visit count, spend and last visit are always computed
// from finalized bills here, never stored.
// =============================================================================

const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const { whatsappLimiter } = require('../middleware/rateLimiter');
const logger = require('../logger');
const { attachCharges } = require('../charges');
const { BILL_ITEMS_JOIN, BILL_ITEMS_ORDER } = require('../billItemsOrder');
const { syncCustomers, billPhoneMatch, canonicalPhone, customersAllowed } = require('../customers');
const { sendCampaignMessage, normalisePhone } = require('../whatsapp');

const router = express.Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_MESSAGE = 500;
const MAX_RECIPIENTS = 500;

// Customer data and messaging are the owner's alone.
function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Owner access required' });
  }
  return next();
}

// Vittam admin can switch the whole feature off per business (migration 048).
// Checked on every route — sending offers costs money on the shared account,
// so hiding the menu in the app is not enough on its own.
async function customersEnabled(req, res, next) {
  try {
    if (await customersAllowed(req.user.business_id)) return next();
    return res.status(403).json({
      error: 'customers_disabled',
      message: 'Customers & offers are not enabled for this business. Please contact Vittam support.',
    });
  } catch (err) {
    logger.error({ err }, 'customers entitlement check failed');
    return res.status(500).json({ error: 'Failed to load customers' });
  }
}

router.use(requireAuth, ownerOnly, customersEnabled);

// ---------------------------------------------------------------------------
// List query: search, filters, sort and paging all happen here, so the app
// only ever holds one page. Every value is a bound parameter; sort column and
// direction come from fixed maps, never from the request text.
// ---------------------------------------------------------------------------

const RECENCY = {
  within7: ['>=', 7], within30: ['>=', 30], within90: ['>=', 90],
  inactive30: ['<', 30], inactive60: ['<', 60], inactive90: ['<', 90],
};
const SORT_COLUMNS = {
  spend: 'total_spend', visits: 'bill_count', recent: 'last_visit',
  name: 'ISNULL(NULLIF(name, \'\'), phone)',
};
const PAGE_MAX = 100;

const intOrNull = (v) => (v === undefined || v === '' || !/^\d+$/.test(String(v)) ? null : parseInt(v, 10));
const numOrNull = (v) => (v === undefined || v === '' || !/^\d+(\.\d+)?$/.test(String(v)) ? null : Number(v));

/**
 * Turns the request's query string into a WHERE over the per-customer
 * aggregate (`#agg`, see AGG_INTO_TEMP) plus its bound inputs. Unknown or malformed
 * values are ignored, never an error — a filter that cannot be read must not
 * break the screen.
 */
function buildListFilter(query) {
  const where = [];
  const inputs = [];
  const q = String(query.q || '').trim();
  if (q) {
    const rawDigits = q.replace(/\D/g, '');
    const digits = rawDigits.length > 10 ? canonicalPhone(rawDigits) : rawDigits;
    inputs.push(['q_name', sql.NVarChar(200), `%${q}%`]);
    inputs.push(['q_phone', sql.NVarChar(20), digits ? `%${digits}%` : '~no~match~']);
    where.push('(name LIKE @q_name OR phone LIKE @q_phone)');
  }
  for (const [key, col, parse, type] of [
    ['min_visits', 'bill_count >=', intOrNull, sql.Int],
    ['max_visits', 'bill_count <=', intOrNull, sql.Int],
    ['min_spend', 'total_spend >=', numOrNull, sql.Decimal(14, 2)],
    ['max_spend', 'total_spend <=', numOrNull, sql.Decimal(14, 2)],
  ]) {
    const v = parse(query[key]);
    if (v !== null) {
      inputs.push([key, type, v]);
      where.push(`${col} @${key}`);
    }
  }
  const rec = RECENCY[query.recency];
  if (rec) {
    inputs.push(['recency_days', sql.Int, rec[1]]);
    where.push(`last_visit ${rec[0]} DATEADD(day, -@recency_days, GETUTCDATE())`);
  }
  if (query.offers === 'allowed') where.push('opted_out = 0');
  if (query.offers === 'opted_out') where.push('opted_out = 1');
  return { where: where.length ? where.join(' AND ') : '1 = 1', inputs };
}

// One row per customer with a finalized bill: identity + computed totals.
// Materialised into #agg so the counts and the page (and the ids) are read
// from one computation in ONE round trip — each trip to the database is the
// dominant cost of these screens (~90 ms to the hosted DB), not the query.
const AGG_INTO_TEMP = `
  SET NOCOUNT ON;
  SELECT c.id, c.name, c.phone, c.opted_out,
         v.bill_count, v.total_spend, v.last_visit
  INTO #agg
  FROM customers c
  CROSS APPLY (
    SELECT COUNT(*) AS bill_count,
           SUM(b.total - b.discount_amount + ISNULL(b.round_off, 0)) AS total_spend,
           MAX(b.created_at) AS last_visit
    FROM bills b
    WHERE b.business_id = c.business_id
      AND ${billPhoneMatch('c.phone')}
      AND b.status = 'finalized'
  ) v
  WHERE c.business_id = @business_id AND v.bill_count > 0;`;

function listRequest(req, filter) {
  const r = pool.request().input('business_id', sql.UniqueIdentifier, req.user.business_id);
  for (const [name, type, value] of filter.inputs) r.input(name, type, value);
  return r;
}

// The catch-up sync never holds a screen up: every bill save already upserts
// its customer (customers.js), so this only mops up stragglers — the next
// load shows them.
function syncInBackground(businessId) {
  syncCustomers(businessId)
    .catch((err) => logger.warn({ err }, 'background customer sync failed'));
}

// GET /api/customers?q&min_visits&max_visits&min_spend&max_spend&recency
//                    &offers&sort&dir&limit&offset
// One page of customers plus counts: `total` (matching), `total_all` (every
// customer) and `total_eligible` (matching AND not opted out — what "Select
// all" will pick). limit=0 returns just the counts. One round trip.
router.get('/', async (req, res) => {
  try {
    await poolConnect;
    syncInBackground(req.user.business_id);

    const filter = buildListFilter(req.query);
    const limitRaw = intOrNull(req.query.limit);
    const limit = Math.min(limitRaw === null ? 30 : limitRaw, PAGE_MAX);
    const offset = intOrNull(req.query.offset) || 0;
    const sortCol = SORT_COLUMNS[req.query.sort] || SORT_COLUMNS.spend;
    const dir = req.query.dir === 'asc' ? 'ASC' : 'DESC';

    const result = await listRequest(req, filter)
      .input('offset', sql.Int, offset)
      .input('limit', sql.Int, Math.max(limit, 1))
      .query(`${AGG_INTO_TEMP}
        SELECT COUNT(*) AS total_all,
               ISNULL(SUM(CASE WHEN ${filter.where} THEN 1 ELSE 0 END), 0) AS total,
               ISNULL(SUM(CASE WHEN ${filter.where} AND opted_out = 0 THEN 1 ELSE 0 END), 0) AS total_eligible
        FROM #agg;
        ${limit > 0 ? `
        SELECT * FROM #agg
        WHERE ${filter.where}
        ORDER BY ${sortCol} ${dir}, id
        OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;` : ''}
        DROP TABLE #agg;`);

    const [countSet, pageSet = []] = result.recordsets;
    const items = pageSet.map((r) => ({ ...r, opted_out: !!r.opted_out }));
    return res.json({ items, ...countSet[0], offset, limit });
  } catch (err) {
    logger.error({ err }, 'customers list error');
    return res.status(500).json({ error: 'Failed to load customers' });
  }
});

// GET /api/customers/ids?<same filters as the list>
// Every matching customer who can be messaged — "Select all" across pages
// without downloading the pages. Capped at the per-send recipient limit.
router.get('/ids', async (req, res) => {
  try {
    await poolConnect;
    const filter = buildListFilter(req.query);
    const result = await listRequest(req, filter)
      .input('cap', sql.Int, MAX_RECIPIENTS)
      .query(`${AGG_INTO_TEMP}
        SELECT TOP (@cap) id FROM #agg
        WHERE ${filter.where} AND opted_out = 0
        ORDER BY total_spend DESC, id;
        DROP TABLE #agg;`);
    return res.json({ ids: result.recordset.map((r) => r.id) });
  } catch (err) {
    logger.error({ err }, 'customer ids error');
    return res.status(500).json({ error: 'Failed to load customers' });
  }
});

// GET /api/customers/:id/bills?limit&offset
// One page of that customer's finalized bills, newest first, with line items —
// the same shape as Bill.fromJson, so the app's bill popup can open any of
// them. Returns { items, total }.
//
// One round trip: the customer lookup, the page, the total and the page's
// line items are a single batch (they used to be 3–4 sequential trips).
router.get('/:id/bills', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: 'Customer not found' });
  const limitRaw = intOrNull(req.query.limit);
  const limit = Math.min(limitRaw === null ? 20 : Math.max(limitRaw, 1), PAGE_MAX);
  const offset = intOrNull(req.query.offset) || 0;
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('offset', sql.Int, offset)
      .input('limit', sql.Int, limit)
      .query(`
        SET NOCOUNT ON;
        DECLARE @phone NVARCHAR(20) =
          (SELECT phone FROM customers WHERE id = @id AND business_id = @business_id);
        SELECT @phone AS phone;

        DECLARE @page TABLE (id UNIQUEIDENTIFIER PRIMARY KEY);
        IF @phone IS NOT NULL
          INSERT INTO @page (id)
          SELECT b.id FROM bills b
          WHERE b.business_id = @business_id
            AND ${billPhoneMatch('@phone')}
            AND b.status = 'finalized'
          ORDER BY b.created_at DESC, b.id
          OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;

        SELECT COUNT(*) AS total FROM bills b
        WHERE @phone IS NOT NULL
          AND b.business_id = @business_id
          AND ${billPhoneMatch('@phone')}
          AND b.status = 'finalized';

        SELECT b.id, b.business_id, b.bill_number, b.table_id, b.customer_name, b.customer_phone,
               b.subtotal, b.tax_amount, b.discount_amount, b.charges_amount,
               b.additional_charges, b.total, b.round_off,
               b.payment_mode, b.payment_status, b.status,
               b.created_by_user_id, b.created_at, b.finalized_at, b.receipt_token
        FROM @page p JOIN bills b ON b.id = p.id
        ORDER BY b.created_at DESC, b.id;

        SELECT bi.id, bi.bill_id, bi.item_id, bi.variant_id, bi.item_name, bi.quantity,
               bi.unit_price, bi.tax_rate, bi.hsn_code, bi.line_total, bi.discount_amount
        FROM @page p JOIN bill_items bi ON bi.bill_id = p.id
        ${BILL_ITEMS_JOIN}
        ${BILL_ITEMS_ORDER};
      `);

    const [custSet, totalSet, bills, items] = result.recordsets;
    if (!custSet[0] || custSet[0].phone == null) {
      return res.status(404).json({ error: 'Customer not found' });
    }
    const byBill = {};
    for (const it of items) (byBill[it.bill_id] ||= []).push(it);
    for (const b of bills) attachCharges(b).items = byBill[b.id] || [];

    return res.json({ items: bills, total: totalSet[0].total, offset, limit });
  } catch (err) {
    logger.error({ err }, 'customer bills error');
    return res.status(500).json({ error: 'Failed to load customer bills' });
  }
});

// PUT /api/customers/:id/opt-out   { opted_out: bool }
// "Stop sending me offers" — an opted-out customer is never messaged.
router.put('/:id/opt-out', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: 'Customer not found' });
  const optedOut = req.body && req.body.opted_out;
  if (typeof optedOut !== 'boolean') {
    return res.status(400).json({ error: 'opted_out must be true or false' });
  }
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('opted_out', sql.Bit, optedOut ? 1 : 0)
      .query(`
        UPDATE customers
        SET opted_out = @opted_out,
            opted_out_at = CASE WHEN @opted_out = 1 THEN GETUTCDATE() ELSE NULL END,
            updated_at = GETUTCDATE()
        WHERE id = @id AND business_id = @business_id
      `);
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Customer not found' });
    return res.json({ id: req.params.id, opted_out: optedOut });
  } catch (err) {
    logger.error({ err }, 'customer opt-out error');
    return res.status(500).json({ error: 'Failed to update customer' });
  }
});

// POST /api/customers/message   { customer_ids: [...], message }
// Queues one WhatsApp message per selected customer and returns 202 at once;
// sending carries on in the background, each result recorded in
// campaign_messages. Only this business's own, not-opted-out customers are
// ever messaged — anything else is counted as skipped.
router.post('/message', whatsappLimiter, async (req, res) => {
  const { customer_ids: ids } = req.body || {};
  const message = typeof (req.body || {}).message === 'string' ? req.body.message.trim() : '';
  if (!message) return res.status(400).json({ error: 'message is required' });
  if (message.length > MAX_MESSAGE) {
    return res.status(400).json({ error: `message must be at most ${MAX_MESSAGE} characters` });
  }
  if (!Array.isArray(ids) || ids.length === 0) {
    return res.status(400).json({ error: 'customer_ids must be a non-empty array' });
  }
  if (ids.length > MAX_RECIPIENTS) {
    return res.status(400).json({ error: `At most ${MAX_RECIPIENTS} customers per send` });
  }
  if (!ids.every((id) => typeof id === 'string' && UUID_RE.test(id))) {
    return res.status(400).json({ error: 'customer_ids must all be valid ids' });
  }

  try {
    await poolConnect;
    const unique = [...new Set(ids.map((id) => id.toLowerCase()))];

    const recReq = pool.request().input('business_id', sql.UniqueIdentifier, req.user.business_id);
    unique.forEach((id, i) => recReq.input(`c${i}`, sql.UniqueIdentifier, id));
    const recResult = await recReq.query(`
      SELECT c.id, c.phone, b.name AS shop_name
      FROM customers c
      JOIN businesses b ON b.id = c.business_id
      WHERE c.business_id = @business_id
        AND c.opted_out = 0
        AND c.id IN (${unique.map((_, i) => `@c${i}`).join(', ')})
    `);

    // One message per real number: 9876543210 and 919876543210 are one person.
    const seen = new Set();
    const recipients = [];
    for (const r of recResult.recordset) {
      const norm = normalisePhone(r.phone);
      if (!norm || seen.has(norm)) continue;
      seen.add(norm);
      recipients.push(r);
    }
    const skipped = ids.length - recipients.length;
    if (recipients.length === 0) {
      return res.status(400).json({ error: 'None of the selected customers can be messaged', skipped });
    }

    // Per-business daily cap — every queued/sent/failed row today counts.
    const dailyLimit = parseInt(process.env.CAMPAIGN_DAILY_LIMIT, 10) || 500;
    const usedResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT COUNT(*) AS used FROM campaign_messages
        WHERE business_id = @business_id
          AND status IN ('queued', 'sent', 'failed')
          AND created_at >= CAST(CAST(GETUTCDATE() AS DATE) AS DATETIME2)
      `);
    const remaining = Math.max(0, dailyLimit - usedResult.recordset[0].used);
    if (recipients.length > remaining) {
      return res.status(429).json({
        error: `Daily message limit reached — ${remaining} message(s) left today`,
        remaining,
      });
    }

    // Record every recipient as queued BEFORE replying, so the log and the cap
    // are right even if the server restarts mid-send (rows stay 'queued').
    const insReq = pool.request().input('business_id', sql.UniqueIdentifier, req.user.business_id);
    recipients.forEach((r, i) => {
      insReq.input(`cid${i}`, sql.UniqueIdentifier, r.id);
      insReq.input(`ph${i}`, sql.NVarChar(20), r.phone);
    });
    const insResult = await insReq.query(`
      INSERT INTO campaign_messages (business_id, customer_id, phone, status)
      OUTPUT INSERTED.id, INSERTED.phone
      VALUES ${recipients.map((_, i) => `(@business_id, @cid${i}, @ph${i}, 'queued')`).join(', ')}
    `);

    const shopName = recipients[0].shop_name || '';
    // ponytail: in-process background loop — a server restart mid-send leaves
    // the rest 'queued' (visible, not lost). Move to a job queue if that matters.
    setImmediate(() => sendQueued(insResult.recordset, shopName, message));

    const willDeliver = process.env.WHATSAPP_ENABLED === 'true' && !!process.env.WHATSAPP_TPL_CAMPAIGN;
    return res.status(202).json({ queued: recipients.length, skipped, will_deliver: willDeliver });
  } catch (err) {
    logger.error({ err }, 'customer message error');
    return res.status(500).json({ error: 'Failed to send message' });
  }
});

/** Sends each queued row one at a time and records the outcome. Never throws. */
async function sendQueued(rows, shopName, message) {
  for (const row of rows) {
    try {
      const r = await sendCampaignMessage({ phone: row.phone, shopName, message });
      const status = r.sent ? 'sent' : r.skipped ? 'skipped' : 'failed';
      await pool.request()
        .input('id', sql.UniqueIdentifier, row.id)
        .input('status', sql.NVarChar(20), status)
        .input('error_detail', sql.NVarChar(500), r.error ? String(r.error).slice(0, 500) : null)
        .input('provider_ref', sql.NVarChar(100), r.campaignId ? String(r.campaignId).slice(0, 100) : null)
        .query(`
          UPDATE campaign_messages
          SET status = @status, error_detail = @error_detail, provider_ref = @provider_ref
          WHERE id = @id
        `);
    } catch (err) {
      logger.warn({ err, id: row.id }, 'campaign message send/log failed');
    }
  }
}

module.exports = router;
module.exports.sendQueued = sendQueued;
