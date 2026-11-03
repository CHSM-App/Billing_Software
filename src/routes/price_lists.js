// =============================================================================
// Price lists — "Party", "Wholesale", "AC section".
//
// A list is an optional % rule (adjust_pct) plus fixed prices per item or size.
// Billing applies it on the device and sends each list price as the line's
// price_override (see routes/bills.js applyLineOverrides), so nothing here
// prices a bill — this is only the owner's catalogue of lists.
// =============================================================================
const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { validateNumber, validateText } = require('../validate');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can perform this action' });
  }
  next();
}

const MIN_PCT = -90;
const MAX_PCT = 500;
// 4 parameters per row; SQL Server stops at 2100 per request.
const INSERT_CHUNK = 400;

/// Every active list of [businessId] with its fixed prices, in the shape the
/// app caches: [{ id, name, adjust_pct, items: [{ item_id, variant_id, price }] }].
/// Prices for items deleted since are dropped by the join.
async function loadLists(businessId, onlyId = null) {
  const lists = await pool.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('id', sql.UniqueIdentifier, onlyId)
    .query(`
      SELECT id, name, adjust_pct
      FROM price_lists
      WHERE business_id = @business_id AND is_active = 1
        AND (@id IS NULL OR id = @id)
      ORDER BY name
    `);
  const entries = await pool.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('id', sql.UniqueIdentifier, onlyId)
    .query(`
      SELECT pli.price_list_id, pli.item_id, pli.variant_id, pli.price
      FROM price_list_items pli
      JOIN price_lists pl ON pl.id = pli.price_list_id
      JOIN items i ON i.id = pli.item_id
                  AND i.business_id = pl.business_id AND i.is_active = 1
      WHERE pl.business_id = @business_id AND pl.is_active = 1
        AND (@id IS NULL OR pl.id = @id)
    `);
  const byList = {};
  for (const e of entries.recordset) {
    (byList[e.price_list_id] ||= []).push({
      item_id: e.item_id,
      variant_id: e.variant_id,
      price: Number(e.price),
    });
  }
  return lists.recordset.map((l) => ({
    id: l.id,
    name: l.name,
    adjust_pct: l.adjust_pct == null ? null : Number(l.adjust_pct),
    items: byList[l.id] || [],
  }));
}

/// Checks a POST/PUT body. Returns { error } or the cleaned
/// { name, adjustPct, items }.
function cleanBody(body) {
  const nameErr = validateText(body.name, 'Name', 60, { required: true });
  if (nameErr) return { error: nameErr };

  let adjustPct = null;
  if (body.adjust_pct !== undefined && body.adjust_pct !== null && body.adjust_pct !== '') {
    adjustPct = parseFloat(body.adjust_pct);
    if (!Number.isFinite(adjustPct) || adjustPct < MIN_PCT || adjustPct > MAX_PCT) {
      return { error: `Adjustment must be between ${MIN_PCT}% and ${MAX_PCT}%` };
    }
    if (adjustPct === 0) adjustPct = null;
  }

  const raw = body.items === undefined ? [] : body.items;
  if (!Array.isArray(raw)) return { error: 'items must be an array' };
  const items = [];
  const seen = new Set();
  for (const r of raw) {
    if (!r || !r.item_id) return { error: 'each price needs an item_id' };
    if (r.price === undefined || r.price === null || r.price === '') {
      return { error: 'each price needs a price' };
    }
    const bad = validateNumber(r.price, 'Price');
    if (bad) return { error: bad };
    const key = `${r.item_id}|${r.variant_id || ''}`;
    if (seen.has(key)) return { error: 'An item or size may appear only once in a price list' };
    seen.add(key);
    items.push({ item_id: r.item_id, variant_id: r.variant_id || null, price: parseFloat(r.price) });
  }
  return { name: String(body.name).trim(), adjustPct, items };
}

/// Every item and size named in [items] must belong to [businessId] — and a
/// size to the item it is listed under. Returns an error string or null.
async function checkOwnership(businessId, items) {
  if (items.length === 0) return null;
  const itemIds = [...new Set(items.map((i) => i.item_id))];
  const iReq = pool.request().input('business_id', sql.UniqueIdentifier, businessId);
  const iNames = itemIds.map((id, i) => { iReq.input(`it${i}`, sql.UniqueIdentifier, id); return `@it${i}`; });
  const found = await iReq.query(`
    SELECT id FROM items WHERE business_id = @business_id AND id IN (${iNames.join(',')})
  `);
  if (found.recordset.length !== itemIds.length) return 'One or more items were not found';

  const variantIds = [...new Set(items.map((i) => i.variant_id).filter(Boolean))];
  if (variantIds.length === 0) return null;
  const vReq = pool.request().input('business_id', sql.UniqueIdentifier, businessId);
  const vNames = variantIds.map((id, i) => { vReq.input(`vr${i}`, sql.UniqueIdentifier, id); return `@vr${i}`; });
  const vFound = await vReq.query(`
    SELECT v.id, v.item_id FROM item_variants v
    JOIN items i ON i.id = v.item_id
    WHERE i.business_id = @business_id AND v.id IN (${vNames.join(',')})
  `);
  const owner = {};
  for (const v of vFound.recordset) owner[v.id] = v.item_id;
  for (const i of items) {
    if (i.variant_id && owner[i.variant_id] !== i.item_id) return 'One or more sizes were not found';
  }
  return null;
}

async function nameTaken(businessId, name, exceptId = null) {
  const r = await pool.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('name', sql.NVarChar(60), name)
    .input('id', sql.UniqueIdentifier, exceptId)
    .query(`
      SELECT 1 AS x FROM price_lists
      WHERE business_id = @business_id AND is_active = 1 AND name = @name
        AND (@id IS NULL OR id <> @id)
    `);
  return r.recordset.length > 0;
}

/// Replace a list's fixed prices inside [transaction].
async function replaceItems(transaction, listId, items) {
  await transaction.request()
    .input('id', sql.UniqueIdentifier, listId)
    .query('DELETE FROM price_list_items WHERE price_list_id = @id');
  for (let start = 0; start < items.length; start += INSERT_CHUNK) {
    const req = transaction.request().input('id', sql.UniqueIdentifier, listId);
    const rows = items.slice(start, start + INSERT_CHUNK).map((it, i) => {
      req.input(`item${i}`, sql.UniqueIdentifier, it.item_id)
        .input(`var${i}`, sql.UniqueIdentifier, it.variant_id)
        .input(`price${i}`, sql.Decimal(12, 2), it.price);
      return `(@id, @item${i}, @var${i}, @price${i})`;
    });
    await req.query(`
      INSERT INTO price_list_items (price_list_id, item_id, variant_id, price)
      VALUES ${rows.join(', ')}
    `);
  }
}

// GET /api/price-lists — every role: billing needs the lists to price lines.
router.get('/', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    return res.json(await loadLists(req.user.business_id));
  } catch (err) {
    logger.error({ err }, 'Get price lists error');
    return res.status(500).json({ error: 'Failed to fetch price lists' });
  }
});

// POST /api/price-lists — { name, adjust_pct?, items?: [{ item_id, variant_id?, price }] }
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  const body = cleanBody(req.body || {});
  if (body.error) return res.status(400).json({ error: body.error });
  const businessId = req.user.business_id;
  try {
    await poolConnect;
    if (await nameTaken(businessId, body.name)) {
      return res.status(409).json({ error: 'A price list with this name already exists' });
    }
    const ownErr = await checkOwnership(businessId, body.items);
    if (ownErr) return res.status(400).json({ error: ownErr });

    const transaction = pool.transaction();
    await transaction.begin();
    let id;
    try {
      const ins = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, businessId)
        .input('name', sql.NVarChar(60), body.name)
        .input('adjust_pct', sql.Decimal(6, 2), body.adjustPct)
        .query(`
          INSERT INTO price_lists (business_id, name, adjust_pct)
          OUTPUT INSERTED.id
          VALUES (@business_id, @name, @adjust_pct)
        `);
      id = ins.recordset[0].id;
      await replaceItems(transaction, id, body.items);
      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
    const [list] = await loadLists(businessId, id);
    return res.status(201).json(list);
  } catch (err) {
    logger.error({ err }, 'Create price list error');
    return res.status(500).json({ error: 'Failed to create price list' });
  }
});

// PUT /api/price-lists/:id — same body as POST; `items` replaces every price.
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  const body = cleanBody(req.body || {});
  if (body.error) return res.status(400).json({ error: body.error });
  const businessId = req.user.business_id;
  try {
    await poolConnect;
    const found = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query('SELECT id FROM price_lists WHERE id = @id AND business_id = @business_id AND is_active = 1');
    if (found.recordset.length === 0) return res.status(404).json({ error: 'Price list not found' });
    if (await nameTaken(businessId, body.name, req.params.id)) {
      return res.status(409).json({ error: 'A price list with this name already exists' });
    }
    const ownErr = await checkOwnership(businessId, body.items);
    if (ownErr) return res.status(400).json({ error: ownErr });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('name', sql.NVarChar(60), body.name)
        .input('adjust_pct', sql.Decimal(6, 2), body.adjustPct)
        .query('UPDATE price_lists SET name = @name, adjust_pct = @adjust_pct WHERE id = @id');
      await replaceItems(transaction, req.params.id, body.items);
      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
    const [list] = await loadLists(businessId, req.params.id);
    return res.json(list);
  } catch (err) {
    logger.error({ err }, 'Update price list error');
    return res.status(500).json({ error: 'Failed to update price list' });
  }
});

// DELETE /api/price-lists/:id — soft delete: held bills may still name it.
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        UPDATE price_lists SET is_active = 0
        WHERE id = @id AND business_id = @business_id AND is_active = 1
      `);
    if (!result.rowsAffected[0]) return res.status(404).json({ error: 'Price list not found' });
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete price list error');
    return res.status(500).json({ error: 'Failed to delete price list' });
  }
});

module.exports = router;
