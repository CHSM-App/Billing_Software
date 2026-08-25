const express = require('express');
const fs = require('fs');
const path = require('path');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const audit = require('../audit');
const {
  MAX_DECIMAL_12_4,
  validateNumber,
  validateInteger,
  validateText,
  validateEnum,
} = require('../validate');

const router = express.Router();

// Units an item may be sold in. Must stay in sync with `_units` in the Flutter
// item form — the value drives unit conversion, not just display.
const VALID_UNITS = ['piece', 'kg', 'g', 'litre', 'ml', 'metre', 'dozen', 'plate'];

// Item photos are compressed on the device and uploaded as JPEG. They live on
// disk under backend/uploads/items and are served by an explicit static mount
// at /uploads (see server.js); the public URL path is stored in items.image_url.
//
// IMPORTANT: this dir is OUTSIDE public/ on purpose. CI rebuilds public/ (the
// landing page) and force-pushes the backend folder to an orphan branch, so
// anything under public/ can be clobbered on deploy. uploads/ lives beside it,
// untouched by that flow, so customer photos persist across deploys.
//
// Photos are customer-facing only (shown on the QR order menu) — the staff
// item/billing payloads never include them. See PUT/DELETE /:id/image below.
const UPLOAD_DIR = path.join(__dirname, '..', '..', 'uploads', 'items');
// Created at server startup too (server.js), but ensure it here so the route is
// self-sufficient in tests that require this module directly.
try { fs.mkdirSync(UPLOAD_DIR, { recursive: true }); } catch (_) {}

// A JPEG always starts with the SOI marker FF D8 FF. We reject anything else so
// a client can't drop arbitrary bytes (or another image type) onto disk.
function isJpeg(buf) {
  return Buffer.isBuffer(buf) && buf.length > 3 &&
    buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
}

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can manage items' });
  }
  next();
}

// Attach active variants to a list of item rows (mutates rows in place).
// Each item gets a `variants` array (empty when none). One round-trip.
// SQL Server raises 2627 (unique constraint) / 2601 (unique index) when a
// barcode collides. Without this the error falls into a generic catch and the
// client sees "Failed to create…", which tells the user nothing actionable.
function isDuplicateKeyError(err) {
  return err && (err.number === 2627 || err.number === 2601);
}


async function attachVariants(businessId, itemRows) {
  if (itemRows.length === 0) return itemRows;
  const ids = itemRows.map((r) => r.id);
  const request = pool.request().input('business_id', sql.UniqueIdentifier, businessId);
  const params = ids.map((id, i) => {
    request.input(`v${i}`, sql.UniqueIdentifier, id);
    return `@v${i}`;
  });
  const result = await request.query(`
    SELECT v.id, v.item_id, v.label, v.price, v.barcode,
           v.stock_quantity, v.low_stock_threshold, v.sort_order, v.is_active
    FROM item_variants v
    JOIN items i ON i.id = v.item_id
    WHERE i.business_id = @business_id
      AND v.item_id IN (${params.join(', ')})
      AND v.is_active = 1
    ORDER BY v.sort_order ASC, v.label ASC
  `);
  const byItem = {};
  for (const v of result.recordset) {
    (byItem[v.item_id] = byItem[v.item_id] || []).push(v);
  }
  for (const row of itemRows) {
    row.variants = byItem[row.id] || [];
  }
  return itemRows;
}

// GET /api/items/top-sold — must be before /:id to avoid being caught by it
// Returns item_ids ordered by total quantity sold (finalized bills only)
router.get('/top-sold', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT bi.item_id, SUM(bi.quantity) AS total_qty
        FROM bill_items bi
        JOIN bills b ON bi.bill_id = b.id
        WHERE b.business_id = @business_id
          AND b.status = 'finalized'
          AND bi.item_id IS NOT NULL
        GROUP BY bi.item_id
        ORDER BY total_qty DESC
      `);
    return res.json(result.recordset.map((r) => r.item_id));
  } catch (err) {
    logger.error({ err }, 'Get top-sold error');
    return res.status(500).json({ error: 'Failed to fetch top-sold items' });
  }
});

// GET /api/items/with-images — owner-only list for the Menu Photos screen.
// Defined before /:id so the literal path isn't swallowed by the id param.
// This is the ONE staff route that returns image_url; the billing/items list
// (GET /) deliberately omits it so photos never appear during billing.
router.get('/with-images', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, name, category, price, image_url
        FROM items
        WHERE business_id = @business_id AND is_active = 1
        ORDER BY category ASC, name ASC
      `);
    return res.json(result.recordset);
  } catch (err) {
    logger.error({ err }, 'Get items with images error');
    return res.status(500).json({ error: 'Failed to fetch items' });
  }
});

// GET /api/items/categories — must be before /:id to avoid being caught by it
router.get('/categories', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT DISTINCT category
        FROM items
        WHERE business_id = @business_id
          AND category IS NOT NULL
          AND is_active = 1
        ORDER BY category ASC
      `);

    return res.json(result.recordset.map((r) => r.category));
  } catch (err) {
    logger.error({ err }, 'Get categories error');
    return res.status(500).json({ error: 'Failed to fetch categories' });
  }
});

// GET /api/items
router.get('/', requireAuth, async (req, res) => {
  const { search, category, barcode } = req.query;

  try {
    await poolConnect;
    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    let where = 'business_id = @business_id AND is_active = 1';

    // Normalised (spaces/dashes/dots stripped) form of the scanned barcode.
    // Declared out here so the variant fallback below can reuse it.
    let normalised = null;
    if (barcode) {
      // Normalise: strip spaces, dashes, dots so scanner formatting doesn't
      // matter. Both the stored value and the incoming value are compared after
      // stripping non-alphanumeric characters via REPLACE chains.
      normalised = barcode.replace(/[\s\-\.]/g, '');
      request.input('barcode', sql.NVarChar(100), normalised);
      // Match against stored barcode after stripping the same characters
      where += ` AND REPLACE(REPLACE(REPLACE(barcode, '-', ''), ' ', ''), '.', '') = @barcode`;
    }
    if (search) {
      request.input('search', sql.NVarChar(200), `%${search}%`);
      where += ' AND name LIKE @search';
    }
    if (category) {
      request.input('category', sql.NVarChar(100), category);
      where += ' AND category = @category';
    }

    const result = await request.query(`
      SELECT id, business_id, name, barcode, category, price, tax_rate, hsn_code, stock_quantity, low_stock_threshold, unit, is_active, created_at
      FROM items
      WHERE ${where}
      ORDER BY name ASC
    `);

    // Barcode lookup returns a single item. The scanned code may belong to the
    // item itself OR to one of its sizes (variants), so if the item-level match
    // misses, fall back to matching a variant barcode and return that variant's
    // parent item tagged with `matched_variant_id` so the client can select the
    // right size/price.
    if (barcode) {
      if (result.recordset.length === 0) {
        const variantReq = pool.request()
          .input('business_id', sql.UniqueIdentifier, req.user.business_id)
          .input('barcode', sql.NVarChar(100), normalised);
        const variantMatch = await variantReq.query(`
          SELECT TOP 1 i.id, i.business_id, i.name, i.barcode, i.category, i.price,
                 i.tax_rate, i.hsn_code, i.stock_quantity, i.low_stock_threshold, i.unit,
                 i.is_active, i.created_at, v.id AS matched_variant_id
          FROM item_variants v
          JOIN items i ON i.id = v.item_id
          WHERE i.business_id = @business_id
            AND i.is_active = 1
            AND v.is_active = 1
            AND v.barcode IS NOT NULL
            AND REPLACE(REPLACE(REPLACE(v.barcode, '-', ''), ' ', ''), '.', '') = @barcode
        `);
        if (variantMatch.recordset.length === 0) {
          return res.status(404).json({ error: 'Item not found' });
        }
        const row = variantMatch.recordset[0];
        const matchedVariantId = row.matched_variant_id;
        delete row.matched_variant_id;
        await attachVariants(req.user.business_id, [row]);
        row.matched_variant_id = matchedVariantId;
        return res.json(row);
      }
      await attachVariants(req.user.business_id, result.recordset);
      return res.json(result.recordset[0]);
    }

    await attachVariants(req.user.business_id, result.recordset);
    return res.json(result.recordset);
  } catch (err) {
    logger.error({ err }, 'Get items error');
    return res.status(500).json({ error: 'Failed to fetch items' });
  }
});

// GET /api/items/:id
router.get('/:id', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, business_id, name, barcode, category, price, tax_rate, hsn_code, stock_quantity, low_stock_threshold, unit, is_active, created_at, image_url
        FROM items
        WHERE id = @id AND business_id = @business_id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }
    await attachVariants(req.user.business_id, result.recordset);
    return res.json(result.recordset[0]);
  } catch (err) {
    logger.error({ err }, 'Get item error');
    return res.status(500).json({ error: 'Failed to fetch item' });
  }
});

// POST /api/items
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  const {
    name, barcode, category, price, tax_rate, hsn_code, stock_quantity, unit,
    low_stock_threshold,
    // Set by the client when the item is being created with sizes. The variants
    // themselves are POSTed separately straight after, so at INSERT time this is
    // the only signal that the missing price is intentional.
    has_variants,
  } = req.body;

  const sizedItem = has_variants === true;

  // A variant item has no price of its own — each size carries one. A plain item
  // must have a price, or billing it would have nothing to charge.
  if (!sizedItem && (price === undefined || price === null)) {
    return res.status(400).json({ error: 'price is required unless the item has variants' });
  }
  const invalid = validateText(name, 'Name', 200, { required: true })
    || validateNumber(price, 'Price')
    || validateNumber(stock_quantity, 'Stock')
    || validateNumber(low_stock_threshold, 'Low stock alert')
    // tax_rate is DECIMAL(5,2) — a percentage, so cap it at 100 rather than the
    // column max. 999% tax would fit the column and still be nonsense.
    || validateNumber(tax_rate, 'Tax rate', { max: 100 })
    || validateText(barcode, 'Barcode', 100)
    || validateText(hsn_code, 'HSN/SAC code', 10)
    || validateText(category, 'Category', 100)
    // Unit is not free text — it drives the g↔kg / ml↔litre conversion when a
    // recipe quantity is stored, so an unknown value would silently skip it.
    || validateEnum(unit, 'Unit', VALID_UNITS);
  if (invalid) return res.status(400).json({ error: invalid });

  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('name', sql.NVarChar(200), name)
      // A sized item owns none of these — its variants carry the price, barcode
      // and stock. Force them null so a leftover value can never be billed or
      // scanned in place of a size.
      .input('barcode', sql.NVarChar(100), sizedItem ? null : (barcode || null))
      .input('category', sql.NVarChar(100), category || null)
      .input('price', sql.Decimal(10, 2),
        sizedItem || price == null ? null : parseFloat(price))
      .input('tax_rate', sql.Decimal(5, 2), tax_rate != null ? parseFloat(tax_rate) : null)
      .input('hsn_code', sql.NVarChar(10), hsn_code || null)
      .input('stock_quantity', sql.Decimal(10, 2),
        sizedItem || stock_quantity == null ? null : parseFloat(stock_quantity))
      .input('unit', sql.NVarChar(20), unit || 'piece')
      // Low-stock alert level. Previously hardcoded to 50, so it was impossible
      // to set from the app — a shop selling 5 kg of rice alerted at the same
      // level as one selling 500 packets. 50 stays the default when omitted so
      // existing callers are unaffected.
      .input('low_stock_threshold', sql.Decimal(10, 2),
        low_stock_threshold != null ? parseFloat(low_stock_threshold) : 50)
      .query(`
        INSERT INTO items (business_id, name, barcode, category, price, tax_rate, hsn_code, stock_quantity, unit, low_stock_threshold)
        OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.barcode, INSERTED.category,
               INSERTED.price, INSERTED.tax_rate, INSERTED.hsn_code, INSERTED.stock_quantity, INSERTED.low_stock_threshold, INSERTED.unit, INSERTED.is_active, INSERTED.created_at
        VALUES (@business_id, @name, @barcode, @category, @price, @tax_rate, @hsn_code, @stock_quantity, @unit, @low_stock_threshold)
      `);

    const created = result.recordset[0];

    audit.logItemCreated(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      created,
    );

    // Attach variants (always [] for a brand-new item) so the response shape
    // matches every other item-returning endpoint. Without a `variants` key the
    // client's Item.fromJson defaults it to [], which is the same shape that
    // made a sized item look plain and bill at its base price — see the note on
    // PUT /:id below.
    await attachVariants(req.user.business_id, [created]);

    return res.status(201).json(created);
  } catch (err) {
    if (isDuplicateKeyError(err)) {
      return res.status(409).json({ error: 'That barcode is already used by another item' });
    }
    logger.error({ err }, 'Create item error');
    return res.status(500).json({ error: 'Failed to create item' });
  }
});

// PUT /api/items/:id
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  const {
    name, barcode, category, price, tax_rate, hsn_code, stock_quantity, unit,
    low_stock_threshold,
  } = req.body;

  if (!name && price === undefined && !category && barcode === undefined && tax_rate === undefined && hsn_code === undefined && stock_quantity === undefined && unit === undefined && low_stock_threshold === undefined) {
    return res.status(400).json({ error: 'Provide at least one field to update' });
  }
  const invalid = (name !== undefined
        ? validateText(name, 'Name', 200, { required: true })
        : null)
    || validateNumber(price, 'Price')
    || validateNumber(stock_quantity, 'Stock')
    || validateNumber(low_stock_threshold, 'Low stock alert')
    || validateNumber(tax_rate, 'Tax rate', { max: 100 })
    || validateText(barcode, 'Barcode', 100)
    || validateText(hsn_code, 'HSN/SAC code', 10)
    || validateText(category, 'Category', 100)
    // Unit is not free text — it drives the g↔kg / ml↔litre conversion when a
    // recipe quantity is stored, so an unknown value would silently skip it.
    || validateEnum(unit, 'Unit', VALID_UNITS);
  if (invalid) return res.status(400).json({ error: invalid });

  try {
    await poolConnect;

    // Whether the item actually has sizes is read from the DB, never taken on
    // trust from the request — an edit that cleared the price would otherwise
    // just have to claim the item was sized.
    const check = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT i.id, i.name, i.price, i.stock_quantity,
               (SELECT COUNT(*) FROM item_variants v
                 WHERE v.item_id = i.id AND v.is_active = 1) AS variant_count
        FROM items i
        WHERE i.id = @id AND i.business_id = @business_id
      `);

    if (check.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }
    const before = check.recordset[0];
    const sizedItem = before.variant_count > 0;

    // Clearing the price is only meaningful for an item whose sizes carry their
    // own. On a plain item it would leave nothing to bill — and because billing
    // falls back to the item price when a size has none, a null here would
    // otherwise surface as NaN on the invoice.
    if (price !== undefined && price == null && !sizedItem) {
      return res.status(400).json({
        error: 'price can only be cleared on an item that has variants',
      });
    }

    const sets = [];
    const request = pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (name !== undefined) {
      sets.push('name = @name');
      request.input('name', sql.NVarChar(200), name);
    }
    if (barcode !== undefined) {
      sets.push('barcode = @barcode');
      request.input('barcode', sql.NVarChar(100), barcode || null);
    }
    if (category !== undefined) {
      sets.push('category = @category');
      request.input('category', sql.NVarChar(100), category || null);
    }
    if (price !== undefined) {
      sets.push('price = @price');
      request.input('price', sql.Decimal(10, 2),
        price != null ? parseFloat(price) : null);
    }
    if (tax_rate !== undefined) {
      sets.push('tax_rate = @tax_rate');
      request.input('tax_rate', sql.Decimal(5, 2), tax_rate != null ? parseFloat(tax_rate) : null);
    }
    if (hsn_code !== undefined) {
      sets.push('hsn_code = @hsn_code');
      request.input('hsn_code', sql.NVarChar(10), hsn_code || null);
    }
    if (stock_quantity !== undefined) {
      sets.push('stock_quantity = @stock_quantity');
      request.input('stock_quantity', sql.Decimal(10, 2), stock_quantity != null ? parseFloat(stock_quantity) : null);
    }
    if (unit !== undefined) {
      sets.push('unit = @unit');
      request.input('unit', sql.NVarChar(20), unit || 'piece');
    }
    if (low_stock_threshold !== undefined) {
      sets.push('low_stock_threshold = @low_stock_threshold');
      request.input('low_stock_threshold', sql.Decimal(10, 2),
        low_stock_threshold != null ? parseFloat(low_stock_threshold) : null);
    }
    const result = await request.query(`
      UPDATE items
      SET ${sets.join(', ')}
      OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.barcode, INSERTED.category,
             INSERTED.price, INSERTED.tax_rate, INSERTED.hsn_code, INSERTED.stock_quantity, INSERTED.low_stock_threshold, INSERTED.unit, INSERTED.is_active, INSERTED.created_at
      WHERE id = @id AND business_id = @business_id
    `);

    const updated = result.recordset[0];
    // Attach the item's sizes. Without this the response has NO `variants` key,
    // so the client's Item.fromJson defaults it to [] and the updated item lands
    // in the billing list looking like a plain item — tapping it then bills the
    // base price instead of opening the size picker (Chicken 65: base 230 when
    // the real sizes are half 180 / Full 280). Every other item-returning
    // endpoint already does this; this one was the odd one out.
    await attachVariants(req.user.business_id, [updated]);
    const actor = { user_id: req.user.user_id, user_name: req.user.name || null };

    if (price !== undefined && parseFloat(price) !== parseFloat(before.price)) {
      audit.logItemPriceChanged(actor, updated, parseFloat(before.price), parseFloat(price));
    }
    if (stock_quantity !== undefined && parseFloat(stock_quantity) !== parseFloat(before.stock_quantity)) {
      audit.logItemStockAdjusted(actor, updated, before.stock_quantity, parseFloat(stock_quantity));
    }

    return res.json(updated);
  } catch (err) {
    if (isDuplicateKeyError(err)) {
      return res.status(409).json({ error: 'That barcode is already used by another item' });
    }
    logger.error({ err }, 'Update item error');
    return res.status(500).json({ error: 'Failed to update item' });
  }
});

// DELETE /api/items/:id — soft delete
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    // Fetch before soft-delete so we can snapshot name/price in the audit log
    const snapshot = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT id, business_id, name, price FROM items WHERE id = @id AND business_id = @business_id AND is_active = 1');

    if (snapshot.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }

    await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('UPDATE items SET is_active = 0 WHERE id = @id AND business_id = @business_id');

    audit.logItemDeleted(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      snapshot.recordset[0],
    );

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete item error');
    return res.status(500).json({ error: 'Failed to delete item' });
  }
});

// ---------------------------------------------------------------------------
// Item photo (customer-facing only). The owner uploads a JPEG that the device
// has already resized/compressed. We store it on disk and record its public URL
// in items.image_url; the QR order menu serves it. Billing never sees photos.
// ---------------------------------------------------------------------------

// Raw JPEG body, scoped to this route only so no other route pays the cost and
// the global JSON parser is untouched. 2MB is generous for a ~1000px JPEG.
const jpegBody = express.raw({ type: 'image/jpeg', limit: '2mb' });

// PUT /api/items/:id/image — replace the item's photo. Body is the JPEG bytes.
router.put('/:id/image', requireAuth, ownerOnly, jpegBody, async (req, res) => {
  const buf = req.body;
  if (!isJpeg(buf)) {
    return res.status(400).json({ error: 'A JPEG image body is required' });
  }
  try {
    await poolConnect;
    // Verify ownership before writing anything to disk.
    const check = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT id FROM items WHERE id = @id AND business_id = @business_id AND is_active = 1');
    if (check.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }

    // Filename is the item id; a cache-busting ?v= is added to the URL so a
    // replaced photo shows immediately despite the stable filename.
    const fileName = `${req.params.id}.jpg`;
    await fs.promises.writeFile(path.join(UPLOAD_DIR, fileName), buf);
    const imageUrl = `/uploads/items/${fileName}?v=${Date.now()}`;

    await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('image_url', sql.NVarChar(500), imageUrl)
      .query('UPDATE items SET image_url = @image_url WHERE id = @id AND business_id = @business_id');

    return res.json({ image_url: imageUrl });
  } catch (err) {
    logger.error({ err }, 'Upload item image error');
    return res.status(500).json({ error: 'Failed to save image' });
  }
});

// DELETE /api/items/:id/image — remove the photo and clear image_url.
router.delete('/:id/image', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const check = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT id FROM items WHERE id = @id AND business_id = @business_id');
    if (check.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }

    await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('UPDATE items SET image_url = NULL WHERE id = @id AND business_id = @business_id');

    // Best-effort file removal — a missing file is fine.
    fs.promises.unlink(path.join(UPLOAD_DIR, `${req.params.id}.jpg`)).catch(() => {});

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete item image error');
    return res.status(500).json({ error: 'Failed to delete image' });
  }
});

// ---------------------------------------------------------------------------
// Variants — sizes (S/M/L/XL) with independent stock, nested under an item.
// ---------------------------------------------------------------------------

// Verify the parent item exists and belongs to the caller's business.
async function loadOwnedItem(itemId, businessId) {
  const result = await pool.request()
    .input('id', sql.UniqueIdentifier, itemId)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query('SELECT id FROM items WHERE id = @id AND business_id = @business_id AND is_active = 1');
  return result.recordset.length > 0;
}

const VARIANT_OUTPUT =
  'INSERTED.id, INSERTED.item_id, INSERTED.label, INSERTED.price, INSERTED.barcode, ' +
  'INSERTED.stock_quantity, INSERTED.low_stock_threshold, INSERTED.sort_order, INSERTED.is_active';

// POST /api/items/:id/variants
router.post('/:id/variants', requireAuth, ownerOnly, async (req, res) => {
  const { label, price, barcode, stock_quantity, low_stock_threshold, sort_order } = req.body;

  const invalid = validateText(label, 'Size name', 50, { required: true })
    || validateNumber(price, 'Price')
    || validateNumber(stock_quantity, 'Stock')
    || validateNumber(low_stock_threshold, 'Low stock alert')
    || validateInteger(sort_order, 'sort_order')
    || validateText(barcode, 'Barcode', 100);
  if (invalid) return res.status(400).json({ error: invalid });

  try {
    await poolConnect;
    if (!(await loadOwnedItem(req.params.id, req.user.business_id))) {
      return res.status(404).json({ error: 'Item not found' });
    }

    const result = await pool.request()
      .input('item_id', sql.UniqueIdentifier, req.params.id)
      .input('label', sql.NVarChar(50), String(label).trim())
      .input('price', sql.Decimal(10, 2), price != null ? parseFloat(price) : null)
      .input('barcode', sql.NVarChar(100), barcode || null)
      .input('stock_quantity', sql.Decimal(10, 2), stock_quantity != null ? parseFloat(stock_quantity) : null)
      .input('low_stock_threshold', sql.Decimal(10, 2), low_stock_threshold != null ? parseFloat(low_stock_threshold) : null)
      .input('sort_order', sql.Int, sort_order != null ? parseInt(sort_order, 10) : 0)
      .query(`
        INSERT INTO item_variants (item_id, label, price, barcode, stock_quantity, low_stock_threshold, sort_order)
        OUTPUT ${VARIANT_OUTPUT}
        VALUES (@item_id, @label, @price, @barcode, @stock_quantity, @low_stock_threshold, @sort_order)
      `);

    // Once an item has sizes, its own stock is meaningless — stock is tracked
    // per size. Null the parent's stock so it is never considered or alerted on.
    await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .query('UPDATE items SET stock_quantity = NULL, low_stock_threshold = NULL WHERE id = @id');

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    if (isDuplicateKeyError(err)) {
      return res.status(409).json({
        error: 'That barcode is already used by another size of this item',
      });
    }
    logger.error({ err }, 'Create variant error');
    return res.status(500).json({ error: 'Failed to create variant' });
  }
});

// PUT /api/items/:id/variants/:variantId
router.put('/:id/variants/:variantId', requireAuth, ownerOnly, async (req, res) => {
  const { label, price, barcode, stock_quantity, low_stock_threshold, sort_order } = req.body;

  if (label === undefined && price === undefined && barcode === undefined &&
      stock_quantity === undefined && low_stock_threshold === undefined && sort_order === undefined) {
    return res.status(400).json({ error: 'Provide at least one field to update' });
  }
  // The same rules as create — this route had none, so an edit could set a
  // negative price or blank out a size's name where a create could not.
  const invalid = (label !== undefined
        ? validateText(label, 'Size name', 50, { required: true })
        : null)
    || validateNumber(price, 'Price')
    || validateNumber(stock_quantity, 'Stock')
    || validateNumber(low_stock_threshold, 'Low stock alert')
    || validateInteger(sort_order, 'sort_order')
    || validateText(barcode, 'Barcode', 100);
  if (invalid) return res.status(400).json({ error: invalid });

  try {
    await poolConnect;
    if (!(await loadOwnedItem(req.params.id, req.user.business_id))) {
      return res.status(404).json({ error: 'Item not found' });
    }

    const sets = [];
    const request = pool.request()
      .input('id', sql.UniqueIdentifier, req.params.variantId)
      .input('item_id', sql.UniqueIdentifier, req.params.id);

    if (label !== undefined) {
      sets.push('label = @label');
      request.input('label', sql.NVarChar(50), String(label).trim());
    }
    if (price !== undefined) {
      sets.push('price = @price');
      request.input('price', sql.Decimal(10, 2), price != null ? parseFloat(price) : null);
    }
    if (barcode !== undefined) {
      sets.push('barcode = @barcode');
      request.input('barcode', sql.NVarChar(100), barcode || null);
    }
    if (stock_quantity !== undefined) {
      sets.push('stock_quantity = @stock_quantity');
      request.input('stock_quantity', sql.Decimal(10, 2), stock_quantity != null ? parseFloat(stock_quantity) : null);
    }
    if (low_stock_threshold !== undefined) {
      sets.push('low_stock_threshold = @low_stock_threshold');
      request.input('low_stock_threshold', sql.Decimal(10, 2), low_stock_threshold != null ? parseFloat(low_stock_threshold) : null);
    }
    if (sort_order !== undefined) {
      sets.push('sort_order = @sort_order');
      request.input('sort_order', sql.Int, sort_order != null ? parseInt(sort_order, 10) : 0);
    }

    const result = await request.query(`
      UPDATE item_variants
      SET ${sets.join(', ')}
      OUTPUT ${VARIANT_OUTPUT}
      WHERE id = @id AND item_id = @item_id
    `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Variant not found' });
    }
    return res.json(result.recordset[0]);
  } catch (err) {
    if (isDuplicateKeyError(err)) {
      return res.status(409).json({
        error: 'That barcode is already used by another size of this item',
      });
    }
    logger.error({ err }, 'Update variant error');
    return res.status(500).json({ error: 'Failed to update variant' });
  }
});

// DELETE /api/items/:id/variants/:variantId — soft delete
router.delete('/:id/variants/:variantId', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    if (!(await loadOwnedItem(req.params.id, req.user.business_id))) {
      return res.status(404).json({ error: 'Item not found' });
    }
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.variantId)
      .input('item_id', sql.UniqueIdentifier, req.params.id)
      .query('UPDATE item_variants SET is_active = 0 WHERE id = @id AND item_id = @item_id');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Variant not found' });
    }
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete variant error');
    return res.status(500).json({ error: 'Failed to delete variant' });
  }
});

// ---------------------------------------------------------------------------
// Recipes — the raw materials a sellable item consumes per unit sold (BOM).
// Raw materials themselves live in routes/raw_materials.js and never appear on
// the billing page; only the parent item is billed.
// ---------------------------------------------------------------------------

// An item WITHOUT sizes keeps its recipe on the item (variant_id NULL); an item
// WITH sizes carries one per size. The two shapes share these helpers so the
// item-level and variant-level routes can never drift apart.
//
// Every variant predicate needs the explicit IS NULL arm — `= @variant_id`
// alone never matches NULL, so an item-level read/write would silently touch
// nothing (or, for the DELETE, everything).

async function fetchRecipe(itemId, variantId, businessId) {
  const result = await pool.request()
    .input('item_id', sql.UniqueIdentifier, itemId)
    .input('variant_id', sql.UniqueIdentifier, variantId || null)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`
      SELECT ir.id, ir.item_id, ir.variant_id, ir.raw_material_id, ir.quantity,
             rm.name AS raw_material_name, rm.unit AS raw_material_unit,
             rm.stock_quantity, rm.low_stock_threshold
      FROM item_recipes ir
      JOIN items i ON i.id = ir.item_id
      JOIN raw_materials rm ON rm.id = ir.raw_material_id
      WHERE ir.item_id = @item_id AND i.business_id = @business_id AND rm.is_active = 1
        AND ((@variant_id IS NULL AND ir.variant_id IS NULL)
             OR ir.variant_id = @variant_id)
      ORDER BY rm.name ASC
    `);
  return result.recordset;
}

/// Validates [rows] and replaces one recipe wholesale. Returns null on success,
/// or `{ status, error }` to send back.
async function replaceRecipe(itemId, variantId, rows, businessId) {
  if (!Array.isArray(rows)) {
    return { status: 400, error: 'rows array is required' };
  }
  const seen = new Set();
  for (const r of rows) {
    if (!r.raw_material_id) {
      return { status: 400, error: 'each row needs a raw_material_id' };
    }
    // Must be > 0 (a zero-quantity ingredient is just a missing row) and within
    // DECIMAL(12,4) — past that SQL Server raises an arithmetic overflow that
    // would surface as an opaque 500.
    const badQty = validateNumber(r.quantity, 'Quantity',
      { max: MAX_DECIMAL_12_4, allowZero: false });
    if (r.quantity == null || badQty) {
      return { status: 400, error: badQty || 'each row needs a quantity > 0' };
    }
    // Without this a duplicate reaches UQ_item_recipes_item_variant_raw and
    // surfaces as an opaque 500 instead of a fixable message.
    if (seen.has(r.raw_material_id)) {
      return { status: 400, error: 'Each raw material may appear only once in a recipe' };
    }
    seen.add(r.raw_material_id);
  }

  // Validate all referenced raw materials belong to this business.
  if (rows.length > 0) {
    const request = pool.request().input('business_id', sql.UniqueIdentifier, businessId);
    const ids = [...seen];
    const params = ids.map((id, i) => { request.input(`r${i}`, sql.UniqueIdentifier, id); return `@r${i}`; });
    const check = await request.query(`
      SELECT id FROM raw_materials
      WHERE business_id = @business_id AND is_active = 1 AND id IN (${params.join(', ')})
    `);
    if (check.recordset.length !== ids.length) {
      return { status: 400, error: 'One or more raw materials were not found' };
    }
  }

  const transaction = pool.transaction();
  await transaction.begin();
  try {
    // Scoped by variant: an unscoped delete would wipe every OTHER size's
    // recipe whenever one size was saved.
    await transaction.request()
      .input('item_id', sql.UniqueIdentifier, itemId)
      .input('variant_id', sql.UniqueIdentifier, variantId || null)
      .query(`
        DELETE FROM item_recipes
        WHERE item_id = @item_id
          AND ((@variant_id IS NULL AND variant_id IS NULL)
               OR variant_id = @variant_id)
      `);

    for (const r of rows) {
      await transaction.request()
        .input('item_id', sql.UniqueIdentifier, itemId)
        .input('variant_id', sql.UniqueIdentifier, variantId || null)
        .input('raw_material_id', sql.UniqueIdentifier, r.raw_material_id)
        .input('quantity', sql.Decimal(12, 4), parseFloat(r.quantity))
        .query(`
          INSERT INTO item_recipes (item_id, variant_id, raw_material_id, quantity)
          VALUES (@item_id, @variant_id, @raw_material_id, @quantity)
        `);
    }
    await transaction.commit();
  } catch (err) {
    await transaction.rollback();
    throw err;
  }
  return null;
}

// Confirms the size exists and belongs to this item. Reads don't require the
// size to still be active (an owner may inspect a removed size's recipe);
// writes pass requireActive so a deactivated size can't be edited.
async function loadOwnedVariant(itemId, variantId, { requireActive } = {}) {
  const result = await pool.request()
    .input('id', sql.UniqueIdentifier, variantId)
    .input('item_id', sql.UniqueIdentifier, itemId)
    .query(`
      SELECT id FROM item_variants
      WHERE id = @id AND item_id = @item_id
        ${requireActive ? 'AND is_active = 1' : ''}
    `);
  return result.recordset[0] || null;
}

// GET /api/items/:id/recipe — the recipe of an item that has no sizes.
router.get('/:id/recipe', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    return res.json(await fetchRecipe(req.params.id, null, req.user.business_id));
  } catch (err) {
    logger.error({ err }, 'Get recipe error');
    return res.status(500).json({ error: 'Failed to fetch recipe' });
  }
});

// PUT /api/items/:id/recipe — replace that item-level recipe.
// Body: { rows: [{ raw_material_id, quantity }, ...] }
router.put('/:id/recipe', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    if (!(await loadOwnedItem(req.params.id, req.user.business_id))) {
      return res.status(404).json({ error: 'Item not found' });
    }
    const fail = await replaceRecipe(
      req.params.id, null, req.body.rows, req.user.business_id);
    if (fail) return res.status(fail.status).json({ error: fail.error });
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Update recipe error');
    return res.status(500).json({ error: 'Failed to update recipe' });
  }
});

// GET /api/items/:id/variants/:variantId/recipe — one size's recipe.
router.get('/:id/variants/:variantId/recipe', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    if (!(await loadOwnedItem(req.params.id, req.user.business_id))) {
      return res.status(404).json({ error: 'Item not found' });
    }
    if (!(await loadOwnedVariant(req.params.id, req.params.variantId))) {
      return res.status(404).json({ error: 'Variant not found' });
    }
    return res.json(
      await fetchRecipe(req.params.id, req.params.variantId, req.user.business_id));
  } catch (err) {
    logger.error({ err }, 'Get variant recipe error');
    return res.status(500).json({ error: 'Failed to fetch recipe' });
  }
});

// PUT /api/items/:id/variants/:variantId/recipe — replace one size's recipe.
router.put('/:id/variants/:variantId/recipe', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    if (!(await loadOwnedItem(req.params.id, req.user.business_id))) {
      return res.status(404).json({ error: 'Item not found' });
    }
    if (!(await loadOwnedVariant(req.params.id, req.params.variantId, { requireActive: true }))) {
      return res.status(404).json({ error: 'Variant not found' });
    }
    const fail = await replaceRecipe(
      req.params.id, req.params.variantId, req.body.rows, req.user.business_id);
    if (fail) return res.status(fail.status).json({ error: fail.error });
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Update variant recipe error');
    return res.status(500).json({ error: 'Failed to update recipe' });
  }
});

module.exports = router;
