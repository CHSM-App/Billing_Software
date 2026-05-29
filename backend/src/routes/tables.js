const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can perform this action' });
  }
  next();
}

const VALID_STATUSES = ['empty', 'occupied', 'billed'];

// GET /api/tables
router.get('/', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT t.id, t.business_id, t.table_number, t.floor_x, t.floor_y, t.status, t.created_at,
               b.id AS active_bill_id
        FROM tables t
        LEFT JOIN bills b
          ON b.table_id = t.id
          AND b.status NOT IN ('voided', 'finalized')
          AND b.business_id = t.business_id
        WHERE t.business_id = @business_id
        ORDER BY t.table_number ASC
      `);

    return res.json(result.recordset);
  } catch (err) {
    logger.error({ err }, 'Get tables error');
    return res.status(500).json({ error: 'Failed to fetch tables' });
  }
});

// POST /api/tables
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  const { table_number, floor_x, floor_y } = req.body;

  if (!table_number) {
    return res.status(400).json({ error: 'table_number is required' });
  }

  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('table_number', sql.NVarChar(20), table_number)
      .input('floor_x', sql.Decimal(10, 2), floor_x != null ? parseFloat(floor_x) : 0)
      .input('floor_y', sql.Decimal(10, 2), floor_y != null ? parseFloat(floor_y) : 0)
      .query(`
        INSERT INTO tables (business_id, table_number, floor_x, floor_y, status)
        OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.table_number,
               INSERTED.floor_x, INSERTED.floor_y, INSERTED.status, INSERTED.created_at
        VALUES (@business_id, @table_number, @floor_x, @floor_y, 'empty')
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    logger.error({ err }, 'Create table error');
    return res.status(500).json({ error: 'Failed to create table' });
  }
});

// PUT /api/tables/:id
router.put('/:id', requireAuth, async (req, res) => {
  const { table_number, floor_x, floor_y, status } = req.body;

  if (table_number === undefined && floor_x === undefined && floor_y === undefined && status === undefined) {
    return res.status(400).json({ error: 'Provide at least one field to update' });
  }
  if (status !== undefined && !VALID_STATUSES.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${VALID_STATUSES.join(', ')}` });
  }

  try {
    await poolConnect;

    const check = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT id FROM tables WHERE id = @id AND business_id = @business_id');

    if (check.recordset.length === 0) {
      return res.status(404).json({ error: 'Table not found' });
    }

    const sets = [];
    const request = pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (table_number !== undefined) {
      sets.push('table_number = @table_number');
      request.input('table_number', sql.NVarChar(20), table_number);
    }
    if (floor_x !== undefined) {
      sets.push('floor_x = @floor_x');
      request.input('floor_x', sql.Decimal(10, 2), parseFloat(floor_x));
    }
    if (floor_y !== undefined) {
      sets.push('floor_y = @floor_y');
      request.input('floor_y', sql.Decimal(10, 2), parseFloat(floor_y));
    }
    if (status !== undefined) {
      sets.push('status = @status');
      request.input('status', sql.NVarChar(20), status);
    }

    const result = await request.query(`
      UPDATE tables
      SET ${sets.join(', ')}
      OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.table_number,
             INSERTED.floor_x, INSERTED.floor_y, INSERTED.status, INSERTED.created_at
      WHERE id = @id AND business_id = @business_id
    `);

    return res.json(result.recordset[0]);
  } catch (err) {
    logger.error({ err }, 'Update table error');
    return res.status(500).json({ error: 'Failed to update table' });
  }
});

// DELETE /api/tables/:id
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    // Block delete if an active (non-voided, non-finalized) bill references this table
    const activeBill = await pool.request()
      .input('table_id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id FROM bills
        WHERE table_id = @table_id
          AND business_id = @business_id
          AND status NOT IN ('voided', 'finalized')
      `);

    if (activeBill.recordset.length > 0) {
      return res.status(409).json({ error: 'Cannot delete table with an active bill' });
    }

    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        DELETE FROM tables
        WHERE id = @id AND business_id = @business_id
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Table not found' });
    }
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete table error');
    return res.status(500).json({ error: 'Failed to delete table' });
  }
});

module.exports = router;
