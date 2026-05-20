const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can manage items' });
  }
  next();
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
    console.error('Get top-sold error:', err.message);
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
    console.error('Get categories error:', err.message);
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
      request.input('barcode', sql.NVarChar(100), barcode);
      where += ' AND barcode = @barcode';
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
      SELECT id, business_id, name, barcode, category, price, tax_rate, stock_quantity, is_active, created_at
      FROM items
      WHERE ${where}
      ORDER BY name ASC
    `);

    // Barcode lookup returns single item
    if (barcode) {
      if (result.recordset.length === 0) {
        return res.status(404).json({ error: 'Item not found' });
      }
      return res.json(result.recordset[0]);
    }

    return res.json(result.recordset);
  } catch (err) {
    console.error('Get items error:', err.message);
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
        SELECT id, business_id, name, barcode, category, price, tax_rate, stock_quantity, is_active, created_at
        FROM items
        WHERE id = @id AND business_id = @business_id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }
    return res.json(result.recordset[0]);
  } catch (err) {
    console.error('Get item error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch item' });
  }
});

// POST /api/items
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  const { name, barcode, category, price, tax_rate, stock_quantity } = req.body;

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
      .query(`
        INSERT INTO items (business_id, name, barcode, category, price, tax_rate, stock_quantity)
        OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.barcode, INSERTED.category,
               INSERTED.price, INSERTED.tax_rate, INSERTED.stock_quantity, INSERTED.is_active, INSERTED.created_at
        VALUES (@business_id, @name, @barcode, @category, @price, @tax_rate, @stock_quantity)
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    console.error('Create item error:', err.message);
    return res.status(500).json({ error: 'Failed to create item' });
  }
});

// PUT /api/items/:id
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  const { name, barcode, category, price, tax_rate, stock_quantity } = req.body;

  if (!name && price === undefined && !category && barcode === undefined && tax_rate === undefined && stock_quantity === undefined) {
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
      .query('SELECT id FROM items WHERE id = @id AND business_id = @business_id');

    if (check.recordset.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
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

    const result = await request.query(`
      UPDATE items
      SET ${sets.join(', ')}
      OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.barcode, INSERTED.category,
             INSERTED.price, INSERTED.tax_rate, INSERTED.stock_quantity, INSERTED.is_active, INSERTED.created_at
      WHERE id = @id AND business_id = @business_id
    `);

    return res.json(result.recordset[0]);
  } catch (err) {
    console.error('Update item error:', err.message);
    return res.status(500).json({ error: 'Failed to update item' });
  }
});

// DELETE /api/items/:id — soft delete
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        UPDATE items SET is_active = 0
        WHERE id = @id AND business_id = @business_id
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }
    return res.json({ success: true });
  } catch (err) {
    console.error('Delete item error:', err.message);
    return res.status(500).json({ error: 'Failed to delete item' });
  }
});

module.exports = router;
