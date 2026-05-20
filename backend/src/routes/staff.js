const express = require('express');
const bcrypt = require('bcryptjs');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can manage staff' });
  }
  next();
}

// POST /api/staff
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  const { name, phone, pin } = req.body;

  if (!name || !phone || !pin) {
    return res.status(400).json({ error: 'name, phone, and pin are required' });
  }
  if (!/^\d{4}$/.test(pin)) {
    return res.status(400).json({ error: 'PIN must be exactly 4 digits' });
  }
  if (!/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Phone must be a 10-digit number' });
  }

  try {
    await poolConnect;
    const pinHash = await bcrypt.hash(pin, 10);

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('name', sql.NVarChar(200), name)
      .input('phone', sql.NVarChar(20), phone)
      .input('pin_hash', sql.NVarChar(255), pinHash)
      .query(`
        INSERT INTO users (business_id, name, phone, pin_hash, role)
        OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.phone, INSERTED.role, INSERTED.created_at
        VALUES (@business_id, @name, @phone, @pin_hash, 'cashier')
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    console.error('Add staff error:', err.message);
    return res.status(500).json({ error: 'Failed to add staff' });
  }
});

// GET /api/staff
router.get('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, business_id, name, phone, role, created_at
        FROM users
        WHERE business_id = @business_id AND role = 'cashier'
        ORDER BY created_at ASC
      `);

    return res.json(result.recordset);
  } catch (err) {
    console.error('Get staff error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch staff' });
  }
});

// DELETE /api/staff/:id
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        DELETE FROM users
        WHERE id = @id AND business_id = @business_id AND role = 'cashier'
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Staff member not found' });
    }
    return res.json({ success: true });
  } catch (err) {
    console.error('Delete staff error:', err.message);
    return res.status(500).json({ error: 'Failed to delete staff' });
  }
});

// PUT /api/staff/:id
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  const { name, phone, pin } = req.body;

  if (!name && !phone && !pin) {
    return res.status(400).json({ error: 'Provide at least one field to update' });
  }
  if (pin && !/^\d{4}$/.test(pin)) {
    return res.status(400).json({ error: 'PIN must be exactly 4 digits' });
  }
  if (phone && !/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Phone must be a 10-digit number' });
  }

  try {
    await poolConnect;

    // Check the staff member exists and belongs to this business
    const check = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id FROM users
        WHERE id = @id AND business_id = @business_id AND role = 'cashier'
      `);

    if (check.recordset.length === 0) {
      return res.status(404).json({ error: 'Staff member not found' });
    }

    // Build SET clause dynamically from provided fields
    const sets = [];
    const request = pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (name) {
      sets.push('name = @name');
      request.input('name', sql.NVarChar(200), name);
    }
    if (phone) {
      sets.push('phone = @phone');
      request.input('phone', sql.NVarChar(20), phone);
    }
    if (pin) {
      const pinHash = await bcrypt.hash(pin, 10);
      sets.push('pin_hash = @pin_hash');
      request.input('pin_hash', sql.NVarChar(255), pinHash);
    }

    const result = await request.query(`
      UPDATE users
      SET ${sets.join(', ')}
      OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.phone, INSERTED.role, INSERTED.created_at
      WHERE id = @id AND business_id = @business_id AND role = 'cashier'
    `);

    return res.json(result.recordset[0]);
  } catch (err) {
    console.error('Update staff error:', err.message);
    return res.status(500).json({ error: 'Failed to update staff' });
  }
});

module.exports = router;
