const express = require('express');
const bcrypt = require('bcryptjs');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const audit = require('../audit');

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

    const created = result.recordset[0];

    audit.logStaffAdded(
      { business_id: req.user.business_id, user_id: req.user.user_id, user_name: req.user.name || null },
      created,
    );

    return res.status(201).json(created);
  } catch (err) {
    logger.error({ err }, 'Add staff error');
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
    logger.error({ err }, 'Get staff error');
    return res.status(500).json({ error: 'Failed to fetch staff' });
  }
});

// DELETE /api/staff/:id
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    // Fetch before delete to snapshot name/phone for the audit log
    const snapshot = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT id, name, phone FROM users WHERE id = @id AND business_id = @business_id AND role = \'cashier\'');

    if (snapshot.recordset.length === 0) {
      return res.status(404).json({ error: 'Staff member not found' });
    }

    await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('DELETE FROM users WHERE id = @id AND business_id = @business_id AND role = \'cashier\'');

    audit.logStaffDeleted(
      { business_id: req.user.business_id, user_id: req.user.user_id, user_name: req.user.name || null },
      snapshot.recordset[0],
    );

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete staff error');
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

    const updated = result.recordset[0];

    // Build a changes summary — never log the PIN hash
    const changes = {};
    if (name)  changes.name  = name;
    if (phone) changes.phone = phone;
    if (pin)   changes.pin_changed = true;

    audit.logStaffUpdated(
      { business_id: req.user.business_id, user_id: req.user.user_id, user_name: req.user.name || null },
      updated,
      changes,
    );

    return res.json(updated);
  } catch (err) {
    logger.error({ err }, 'Update staff error');
    return res.status(500).json({ error: 'Failed to update staff' });
  }
});

module.exports = router;
