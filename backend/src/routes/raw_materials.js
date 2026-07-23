const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can manage raw materials' });
  }
  next();
}

const RM_OUTPUT =
  'INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.unit, ' +
  'INSERTED.stock_quantity, INSERTED.low_stock_threshold, INSERTED.is_active, INSERTED.created_at';

// GET /api/raw-materials — list active raw materials for the business.
router.get('/', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, business_id, name, unit, stock_quantity, low_stock_threshold, is_active, created_at
        FROM raw_materials
        WHERE business_id = @business_id AND is_active = 1
        ORDER BY name ASC
      `);
    return res.json(result.recordset);
  } catch (err) {
    logger.error({ err }, 'Get raw materials error');
    return res.status(500).json({ error: 'Failed to fetch raw materials' });
  }
});

// POST /api/raw-materials
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  const { name, unit, stock_quantity, low_stock_threshold } = req.body;

  if (!name || !String(name).trim()) {
    return res.status(400).json({ error: 'name is required' });
  }

  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('name', sql.NVarChar(200), String(name).trim())
      .input('unit', sql.NVarChar(20), unit || 'piece')
      .input('stock_quantity', sql.Decimal(10, 2), stock_quantity != null ? parseFloat(stock_quantity) : null)
      .input('low_stock_threshold', sql.Decimal(10, 2), low_stock_threshold != null ? parseFloat(low_stock_threshold) : null)
      .query(`
        INSERT INTO raw_materials (business_id, name, unit, stock_quantity, low_stock_threshold)
        OUTPUT ${RM_OUTPUT}
        VALUES (@business_id, @name, @unit, @stock_quantity, @low_stock_threshold)
      `);
    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    logger.error({ err }, 'Create raw material error');
    return res.status(500).json({ error: 'Failed to create raw material' });
  }
});

// PUT /api/raw-materials/:id
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  const { name, unit, stock_quantity, low_stock_threshold } = req.body;

  if (name === undefined && unit === undefined && stock_quantity === undefined && low_stock_threshold === undefined) {
    return res.status(400).json({ error: 'Provide at least one field to update' });
  }

  try {
    await poolConnect;
    const sets = [];
    const request = pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (name !== undefined) {
      sets.push('name = @name');
      request.input('name', sql.NVarChar(200), String(name).trim());
    }
    if (unit !== undefined) {
      sets.push('unit = @unit');
      request.input('unit', sql.NVarChar(20), unit || 'piece');
    }
    if (stock_quantity !== undefined) {
      sets.push('stock_quantity = @stock_quantity');
      request.input('stock_quantity', sql.Decimal(10, 2), stock_quantity != null ? parseFloat(stock_quantity) : null);
    }
    if (low_stock_threshold !== undefined) {
      sets.push('low_stock_threshold = @low_stock_threshold');
      request.input('low_stock_threshold', sql.Decimal(10, 2), low_stock_threshold != null ? parseFloat(low_stock_threshold) : null);
    }

    const result = await request.query(`
      UPDATE raw_materials
      SET ${sets.join(', ')}
      OUTPUT ${RM_OUTPUT}
      WHERE id = @id AND business_id = @business_id AND is_active = 1
    `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Raw material not found' });
    }
    return res.json(result.recordset[0]);
  } catch (err) {
    logger.error({ err }, 'Update raw material error');
    return res.status(500).json({ error: 'Failed to update raw material' });
  }
});

// DELETE /api/raw-materials/:id — soft delete. Blocked while still used by a recipe.
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const inUse = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .query('SELECT TOP 1 1 AS used FROM item_recipes WHERE raw_material_id = @id');
    if (inUse.recordset.length > 0) {
      return res.status(409).json({ error: 'This raw material is used in a recipe. Remove it from all recipes first.' });
    }

    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('UPDATE raw_materials SET is_active = 0 WHERE id = @id AND business_id = @business_id AND is_active = 1');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Raw material not found' });
    }
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete raw material error');
    return res.status(500).json({ error: 'Failed to delete raw material' });
  }
});

module.exports = router;
