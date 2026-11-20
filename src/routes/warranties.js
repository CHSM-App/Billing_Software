// =============================================================================
// /api/warranties — warranty records for "Retail & Warranty" shops.
//
// A record answers "is this tyre/battery/electronics item still under
// warranty?" months after the sale, by phone number or serial number. It can
// be created automatically when a bill with a warranty-eligible item is
// finalized (see the hook in routes/bills.js) or manually here (off-bill
// registrations, fitting-only jobs, etc.) — see migration 064.
//
// customer_name/customer_phone are stored directly rather than requiring a
// `customers` row, for the same reason bills do: `customers` is a derived,
// phone-keyed cache (migration 046), not an authoritative identity store.
// =============================================================================

const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { validateText, validateInteger, validateExtraData } = require('../validate');
const { isValidDateString, addMonths } = require('../dateUtils');

const router = express.Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PAGE_MAX = 100;

router.use(requireAuth);

// A server/kitchen user has no reason to touch warranty records — the same
// cashier-or-owner gate bill finalize uses (routes/bills.js).
function cashierOrOwner(req, res, next) {
  if (req.user.role !== 'cashier' && req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only a cashier or owner can manage warranty records' });
  }
  next();
}

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only an owner can delete a warranty record' });
  }
  next();
}

const intOrNull = (v) => (v === undefined || v === '' || !/^\d+$/.test(String(v)) ? null : parseInt(v, 10));

const STATUS_FILTER = {
  // 30 days is the same "expiring soon" horizon used nowhere else in this
  // codebase yet — chosen as a reasonable default a shop can act on.
  expiring_30: 'expiry_date >= CAST(GETUTCDATE() AS DATE) AND expiry_date < DATEADD(day, 30, CAST(GETUTCDATE() AS DATE))',
  active: 'expiry_date >= CAST(GETUTCDATE() AS DATE)',
  expired: 'expiry_date < CAST(GETUTCDATE() AS DATE)',
};

const WARRANTY_COLUMNS = [
  'id', 'business_id', 'customer_id', 'customer_name', 'customer_phone', 'item_id', 'item_name',
  'category', 'bill_id', 'bill_item_id', 'serial_number', 'purchase_date', 'warranty_months',
  'expiry_date', 'extra_data', 'notes', 'created_by_user_id', 'created_at',
];
const SELECT_COLUMNS = WARRANTY_COLUMNS.join(', ');
const OUTPUT_COLUMNS = WARRANTY_COLUMNS.map((c) => `INSERTED.${c}`).join(', ');

function mapRow(r) {
  return { ...r, extra_data: r.extra_data ? JSON.parse(r.extra_data) : [] };
}

// GET /api/warranties?q&status&limit&offset
router.get('/', cashierOrOwner, async (req, res) => {
  try {
    await poolConnect;
    const request = pool.request().input('business_id', sql.UniqueIdentifier, req.user.business_id);
    const where = ['business_id = @business_id'];

    const q = String(req.query.q || '').trim();
    if (q) {
      request.input('q', sql.NVarChar(200), `%${q}%`);
      // extra_data is the category-template + ad-hoc "label: value" pairs
      // (e.g. a tyre's KM reading, a vehicle number) — stored as JSON text,
      // so a plain LIKE against it still matches a value typed inside.
      where.push(`(customer_name LIKE @q OR customer_phone LIKE @q OR serial_number LIKE @q
        OR item_name LIKE @q OR extra_data LIKE @q)`);
    }
    const statusClause = STATUS_FILTER[req.query.status];
    if (statusClause) where.push(statusClause);

    // Purchase-date range (YYYY-MM-DD, inclusive both ends) — a plain DATE
    // column, so a direct string comparison is sargable with no CAST needed
    // (unlike the DATETIME2 columns dateUtils.js's day-boundary helpers are
    // for).
    const { from, to } = req.query;
    if (from !== undefined || to !== undefined) {
      if (from !== undefined && !isValidDateString(from)) {
        return res.status(400).json({ error: 'from must be a valid date in YYYY-MM-DD format' });
      }
      if (to !== undefined && !isValidDateString(to)) {
        return res.status(400).json({ error: 'to must be a valid date in YYYY-MM-DD format' });
      }
      if (from !== undefined) {
        request.input('from', sql.Date, from);
        where.push('purchase_date >= @from');
      }
      if (to !== undefined) {
        request.input('to', sql.Date, to);
        where.push('purchase_date <= @to');
      }
    }

    const limit = Math.min(intOrNull(req.query.limit) ?? 30, PAGE_MAX);
    const offset = intOrNull(req.query.offset) || 0;

    const result = await request
      .input('offset', sql.Int, offset)
      .input('limit', sql.Int, Math.max(limit, 1))
      .query(`
        SET NOCOUNT ON;
        SELECT COUNT(*) AS total FROM warranties WHERE ${where.join(' AND ')};
        SELECT ${SELECT_COLUMNS}
        FROM warranties
        WHERE ${where.join(' AND ')}
        ORDER BY created_at DESC
        OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
      `);

    const [countSet, rows] = result.recordsets;
    return res.json({ items: rows.map(mapRow), total: countSet[0].total, offset, limit });
  } catch (err) {
    logger.error({ err }, 'List warranties error');
    return res.status(500).json({ error: 'Failed to fetch warranty records' });
  }
});

// GET /api/warranties/:id
router.get('/:id', cashierOrOwner, async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: 'Warranty record not found' });
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`SELECT ${SELECT_COLUMNS} FROM warranties WHERE id = @id AND business_id = @business_id`);
    if (result.recordset.length === 0) return res.status(404).json({ error: 'Warranty record not found' });
    return res.json(mapRow(result.recordset[0]));
  } catch (err) {
    logger.error({ err }, 'Get warranty error');
    return res.status(500).json({ error: 'Failed to fetch warranty record' });
  }
});

/// Shared create/update validation. Returns an error string, or null.
function validateBody(body, { partial } = {}) {
  const { customer_phone, item_name, purchase_date, warranty_months, extra_data, serial_number, notes } = body;
  if (!partial || customer_phone !== undefined) {
    if (validateText(customer_phone, 'Customer phone', 20, { required: true })) {
      return 'Customer phone is required';
    }
  }
  if (!partial || item_name !== undefined) {
    if (validateText(item_name, 'Product', 200, { required: true })) {
      return 'Product name is required';
    }
  }
  if (!partial || purchase_date !== undefined) {
    if (!purchase_date || Number.isNaN(Date.parse(purchase_date))) {
      return 'A valid purchase_date is required';
    }
  }
  if (!partial || warranty_months !== undefined) {
    const monthsInvalid = validateInteger(warranty_months, 'Warranty period');
    if (monthsInvalid || warranty_months == null || parseInt(warranty_months, 10) <= 0) {
      return 'Warranty period (months) must be greater than zero';
    }
  }
  return validateText(serial_number, 'Serial number', 100)
    || validateText(notes, 'Notes', 500)
    || validateExtraData(extra_data);
}

// POST /api/warranties — manual create.
router.post('/', cashierOrOwner, async (req, res) => {
  const invalid = validateBody(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const {
    customer_name, customer_phone, item_id, item_name, serial_number,
    purchase_date, warranty_months, extra_data, notes,
  } = req.body;

  try {
    await poolConnect;

    // When an item is picked, snapshot its category so the Warranty screen
    // can look up that category's field template — same spirit as
    // bill_items snapshotting item_name/hsn_code at sale time.
    let category = req.body.category ?? null;
    if (item_id) {
      const itemCheck = await pool.request()
        .input('id', sql.UniqueIdentifier, item_id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query('SELECT category FROM items WHERE id = @id AND business_id = @business_id');
      if (itemCheck.recordset.length === 0) {
        return res.status(400).json({ error: 'item_id does not belong to this business' });
      }
      category = itemCheck.recordset[0].category;
    }

    const months = parseInt(warranty_months, 10);
    const expiry = addMonths(purchase_date, months);

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('customer_name', sql.NVarChar(200), customer_name || null)
      .input('customer_phone', sql.NVarChar(20), String(customer_phone).trim())
      .input('item_id', sql.UniqueIdentifier, item_id || null)
      .input('item_name', sql.NVarChar(200), String(item_name).trim())
      .input('category', sql.NVarChar(100), category || null)
      .input('serial_number', sql.NVarChar(100), serial_number || null)
      .input('purchase_date', sql.Date, new Date(purchase_date))
      .input('warranty_months', sql.Int, months)
      .input('expiry_date', sql.Date, expiry)
      .input('extra_data', sql.NVarChar(sql.MAX), extra_data ? JSON.stringify(extra_data) : null)
      .input('notes', sql.NVarChar(500), notes || null)
      .input('created_by_user_id', sql.UniqueIdentifier, req.user.user_id)
      .query(`
        INSERT INTO warranties (business_id, customer_name, customer_phone, item_id, item_name,
          category, serial_number, purchase_date, warranty_months, expiry_date, extra_data, notes, created_by_user_id)
        OUTPUT ${OUTPUT_COLUMNS}
        VALUES (@business_id, @customer_name, @customer_phone, @item_id, @item_name,
          @category, @serial_number, @purchase_date, @warranty_months, @expiry_date, @extra_data, @notes, @created_by_user_id)
      `);

    return res.status(201).json(mapRow(result.recordset[0]));
  } catch (err) {
    logger.error({ err }, 'Create warranty error');
    return res.status(500).json({ error: 'Failed to create warranty record' });
  }
});

// PUT /api/warranties/:id
router.put('/:id', cashierOrOwner, async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: 'Warranty record not found' });

  const invalid = validateBody(req.body, { partial: true });
  if (invalid) return res.status(400).json({ error: invalid });

  try {
    await poolConnect;
    const existing = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT purchase_date, warranty_months FROM warranties WHERE id = @id AND business_id = @business_id');
    if (existing.recordset.length === 0) return res.status(404).json({ error: 'Warranty record not found' });
    const before = existing.recordset[0];

    const {
      customer_name, customer_phone, item_name, category, serial_number,
      purchase_date, warranty_months, extra_data, notes,
    } = req.body;

    const sets = [];
    const request = pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (customer_name !== undefined) { sets.push('customer_name = @customer_name'); request.input('customer_name', sql.NVarChar(200), customer_name || null); }
    if (customer_phone !== undefined) { sets.push('customer_phone = @customer_phone'); request.input('customer_phone', sql.NVarChar(20), String(customer_phone).trim()); }
    if (item_name !== undefined) { sets.push('item_name = @item_name'); request.input('item_name', sql.NVarChar(200), String(item_name).trim()); }
    if (category !== undefined) { sets.push('category = @category'); request.input('category', sql.NVarChar(100), category || null); }
    if (serial_number !== undefined) { sets.push('serial_number = @serial_number'); request.input('serial_number', sql.NVarChar(100), serial_number || null); }
    if (notes !== undefined) { sets.push('notes = @notes'); request.input('notes', sql.NVarChar(500), notes || null); }
    if (extra_data !== undefined) { sets.push('extra_data = @extra_data'); request.input('extra_data', sql.NVarChar(sql.MAX), extra_data ? JSON.stringify(extra_data) : null); }

    // Expiry is recomputed whenever either date or period changes, from
    // whichever value (new or existing) applies.
    if (purchase_date !== undefined || warranty_months !== undefined) {
      const effectivePurchase = purchase_date !== undefined ? purchase_date : before.purchase_date;
      const effectiveMonths = warranty_months !== undefined ? parseInt(warranty_months, 10) : before.warranty_months;
      if (purchase_date !== undefined) { sets.push('purchase_date = @purchase_date'); request.input('purchase_date', sql.Date, new Date(purchase_date)); }
      if (warranty_months !== undefined) { sets.push('warranty_months = @warranty_months'); request.input('warranty_months', sql.Int, effectiveMonths); }
      sets.push('expiry_date = @expiry_date');
      request.input('expiry_date', sql.Date, addMonths(effectivePurchase, effectiveMonths));
    }

    if (sets.length === 0) return res.status(400).json({ error: 'Provide at least one field to update' });

    const result = await request.query(`
      UPDATE warranties
      SET ${sets.join(', ')}
      OUTPUT ${SELECT_COLUMNS.replace(/(^|, )/g, '$1INSERTED.')}
      WHERE id = @id AND business_id = @business_id
    `);

    return res.json(mapRow(result.recordset[0]));
  } catch (err) {
    logger.error({ err }, 'Update warranty error');
    return res.status(500).json({ error: 'Failed to update warranty record' });
  }
});

// DELETE /api/warranties/:id — not a financial record, hard delete is fine.
router.delete('/:id', ownerOnly, async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: 'Warranty record not found' });
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('DELETE FROM warranties WHERE id = @id AND business_id = @business_id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Warranty record not found' });
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete warranty error');
    return res.status(500).json({ error: 'Failed to delete warranty record' });
  }
});

module.exports = router;
