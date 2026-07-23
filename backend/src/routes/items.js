const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const audit = require('../audit');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can manage items' });
  }
  next();
}

// Attach active variants to a list of item rows (mutates rows in place).
// Each item gets a `variants` array (empty when none). One round-trip.
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

    if (barcode) {
      // Normalise: strip spaces, dashes, dots so scanner formatting doesn't
      // matter. Both the stored value and the incoming value are compared after
      // stripping non-alphanumeric characters via REPLACE chains.
      const normalised = barcode.replace(/[\s\-\.]/g, '');
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
      SELECT id, business_id, name, barcode, category, price, tax_rate, stock_quantity, low_stock_threshold, unit, is_active, created_at
      FROM items
      WHERE ${where}
      ORDER BY name ASC
    `);

    // Barcode lookup returns single item
    if (barcode) {
      if (result.recordset.length === 0) {
        return res.status(404).json({ error: 'Item not found' });
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
        SELECT id, business_id, name, barcode, category, price, tax_rate, stock_quantity, low_stock_threshold, unit, is_active, created_at
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
  const { name, barcode, category, price, tax_rate, stock_quantity, unit } = req.body;

  if (!name || price === undefined || price === null) {
    return res.status(400).json({ error: 'name and price are required' });
  }
  if (isNaN(parseFloat(price)) || parseFloat(price) < 0) {
    return res.status(400).json({ error: 'price must be a non-negative number' });
  }

  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('name', sql.NVarChar(200), name)
      .input('barcode', sql.NVarChar(100), barcode || null)
      .input('category', sql.NVarChar(100), category || null)
      .input('price', sql.Decimal(10, 2), parseFloat(price))
      .input('tax_rate', sql.Decimal(5, 2), tax_rate != null ? parseFloat(tax_rate) : null)
      .input('stock_quantity', sql.Decimal(10, 2), stock_quantity != null ? parseFloat(stock_quantity) : null)
      .input('unit', sql.NVarChar(20), unit || 'piece')
      .query(`
        INSERT INTO items (business_id, name, barcode, category, price, tax_rate, stock_quantity, unit, low_stock_threshold)
        OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.barcode, INSERTED.category,
               INSERTED.price, INSERTED.tax_rate, INSERTED.stock_quantity, INSERTED.low_stock_threshold, INSERTED.unit, INSERTED.is_active, INSERTED.created_at
        VALUES (@business_id, @name, @barcode, @category, @price, @tax_rate, @stock_quantity, @unit, 50)
      `);

    const created = result.recordset[0];

    audit.logItemCreated(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      created,
    );

    return res.status(201).json(created);
  } catch (err) {
    logger.error({ err }, 'Create item error');
    return res.status(500).json({ error: 'Failed to create item' });
  }
});

// PUT /api/items/:id
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  const { name, barcode, category, price, tax_rate, stock_quantity, unit } = req.body;

  if (!name && price === undefined && !category && barcode === undefined && tax_rate === undefined && stock_quantity === undefined && unit === undefined) {
    return res.status(400).json({ error: 'Provide at least one field to update' });
  }
  if (price !== undefined && (isNaN(parseFloat(price)) || parseFloat(price) < 0)) {
    return res.status(400).json({ error: 'price must be a non-negative number' });
  }

  try {
    await poolConnect;

    const check = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT id, name, price, stock_quantity FROM items WHERE id = @id AND business_id = @business_id');

    if (check.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }
    const before = check.recordset[0];

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
      request.input('price', sql.Decimal(10, 2), parseFloat(price));
    }
    if (tax_rate !== undefined) {
      sets.push('tax_rate = @tax_rate');
      request.input('tax_rate', sql.Decimal(5, 2), tax_rate != null ? parseFloat(tax_rate) : null);
    }
    if (stock_quantity !== undefined) {
      sets.push('stock_quantity = @stock_quantity');
      request.input('stock_quantity', sql.Decimal(10, 2), stock_quantity != null ? parseFloat(stock_quantity) : null);
    }
    if (unit !== undefined) {
      sets.push('unit = @unit');
      request.input('unit', sql.NVarChar(20), unit || 'piece');
    }
    const result = await request.query(`
      UPDATE items
      SET ${sets.join(', ')}
      OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.barcode, INSERTED.category,
             INSERTED.price, INSERTED.tax_rate, INSERTED.stock_quantity, INSERTED.low_stock_threshold, INSERTED.unit, INSERTED.is_active, INSERTED.created_at
      WHERE id = @id AND business_id = @business_id
    `);

    const updated = result.recordset[0];
    const actor = { user_id: req.user.user_id, user_name: req.user.name || null };

    if (price !== undefined && parseFloat(price) !== parseFloat(before.price)) {
      audit.logItemPriceChanged(actor, updated, parseFloat(before.price), parseFloat(price));
    }
    if (stock_quantity !== undefined && parseFloat(stock_quantity) !== parseFloat(before.stock_quantity)) {
      audit.logItemStockAdjusted(actor, updated, before.stock_quantity, parseFloat(stock_quantity));
    }

    return res.json(updated);
  } catch (err) {
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

  if (!label || !String(label).trim()) {
    return res.status(400).json({ error: 'label is required' });
  }
  if (price !== undefined && price !== null && (isNaN(parseFloat(price)) || parseFloat(price) < 0)) {
    return res.status(400).json({ error: 'price must be a non-negative number' });
  }

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

// GET /api/items/:id/recipe — list the recipe rows (with raw-material details).
router.get('/:id/recipe', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('item_id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT ir.id, ir.item_id, ir.raw_material_id, ir.quantity,
               rm.name AS raw_material_name, rm.unit AS raw_material_unit,
               rm.stock_quantity, rm.low_stock_threshold
        FROM item_recipes ir
        JOIN items i ON i.id = ir.item_id
        JOIN raw_materials rm ON rm.id = ir.raw_material_id
        WHERE ir.item_id = @item_id AND i.business_id = @business_id AND rm.is_active = 1
        ORDER BY rm.name ASC
      `);
    return res.json(result.recordset);
  } catch (err) {
    logger.error({ err }, 'Get recipe error');
    return res.status(500).json({ error: 'Failed to fetch recipe' });
  }
});

// PUT /api/items/:id/recipe — replace the item's whole recipe.
// Body: { rows: [{ raw_material_id, quantity }, ...] }
router.put('/:id/recipe', requireAuth, ownerOnly, async (req, res) => {
  const { rows } = req.body;
  if (!Array.isArray(rows)) {
    return res.status(400).json({ error: 'rows array is required' });
  }
  for (const r of rows) {
    if (!r.raw_material_id || r.quantity == null || isNaN(parseFloat(r.quantity)) || parseFloat(r.quantity) <= 0) {
      return res.status(400).json({ error: 'each row needs a raw_material_id and a quantity > 0' });
    }
  }

  try {
    await poolConnect;
    if (!(await loadOwnedItem(req.params.id, req.user.business_id))) {
      return res.status(404).json({ error: 'Item not found' });
    }

    // Validate all referenced raw materials belong to this business.
    if (rows.length > 0) {
      const request = pool.request().input('business_id', sql.UniqueIdentifier, req.user.business_id);
      const ids = [...new Set(rows.map((r) => r.raw_material_id))];
      const params = ids.map((id, i) => { request.input(`r${i}`, sql.UniqueIdentifier, id); return `@r${i}`; });
      const check = await request.query(`
        SELECT id FROM raw_materials
        WHERE business_id = @business_id AND is_active = 1 AND id IN (${params.join(', ')})
      `);
      if (check.recordset.length !== ids.length) {
        return res.status(400).json({ error: 'One or more raw materials were not found' });
      }
    }

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      await transaction.request()
        .input('item_id', sql.UniqueIdentifier, req.params.id)
        .query('DELETE FROM item_recipes WHERE item_id = @item_id');

      for (const r of rows) {
        await transaction.request()
          .input('item_id', sql.UniqueIdentifier, req.params.id)
          .input('raw_material_id', sql.UniqueIdentifier, r.raw_material_id)
          .input('quantity', sql.Decimal(12, 4), parseFloat(r.quantity))
          .query(`
            INSERT INTO item_recipes (item_id, raw_material_id, quantity)
            VALUES (@item_id, @raw_material_id, @quantity)
          `);
      }
      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Update recipe error');
    return res.status(500).json({ error: 'Failed to update recipe' });
  }
});

module.exports = router;
