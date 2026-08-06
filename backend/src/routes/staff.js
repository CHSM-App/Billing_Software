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

// Staff roles this endpoint can create/manage:
//   'cashier' = finalizes bills, takes payment, can be voided by owner
//   'server'  = takes/builds orders (draft bills) and sends them to the kitchen;
//               cannot finalize or collect payment
//   'kitchen' = kitchen chef (Kitchen Display)
// Owners are managed elsewhere.
const MANAGED_ROLES = ['cashier', 'server', 'kitchen'];

// SQL fragment listing the manageable roles for WHERE ... role IN (...) clauses.
const MANAGED_ROLES_SQL = "'cashier', 'server', 'kitchen'";

// POST /api/staff
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  const { name, phone, pin, role } = req.body;
  const staffRole = role || 'cashier';

  if (!name || !phone || !pin) {
    return res.status(400).json({ error: 'name, phone, and pin are required' });
  }
  if (!MANAGED_ROLES.includes(staffRole)) {
    return res.status(400).json({ error: `role must be one of: ${MANAGED_ROLES.join(', ')}` });
  }
  if (!/^\d{4}$/.test(pin)) {
    return res.status(400).json({ error: 'PIN must be exactly 4 digits' });
  }
  if (!/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Phone must be a 10-digit number' });
  }

  try {
    await poolConnect;

    // Reject a phone that already belongs to another user (staff or owner) in
    // this business — phone is the login identity, so it must be unique.
    const existing = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('phone', sql.NVarChar(20), phone)
      .query(`
        SELECT TOP 1 id FROM users
        WHERE business_id = @business_id AND phone = @phone
      `);
    if (existing.recordset.length > 0) {
      return res.status(409).json({ error: 'This phone number is already registered.' });
    }

    const pinHash = await bcrypt.hash(pin, 10);

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('name', sql.NVarChar(200), name)
      .input('phone', sql.NVarChar(20), phone)
      .input('pin_hash', sql.NVarChar(255), pinHash)
      .input('role', sql.NVarChar(20), staffRole)
      .query(`
        INSERT INTO users (business_id, name, phone, pin_hash, role)
        OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.phone, INSERTED.role, INSERTED.created_at
        VALUES (@business_id, @name, @phone, @pin_hash, @role)
      `);

    const created = result.recordset[0];

    audit.logStaffAdded(
      { business_id: req.user.business_id, user_id: req.user.user_id, user_name: req.user.name || null },
      created,
    );

    return res.status(201).json(created);
  } catch (err) {
    // Unique-constraint violation (race between the check above and insert).
    if (err && (err.number === 2627 || err.number === 2601)) {
      return res.status(409).json({ error: 'This phone number is already registered.' });
    }
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
        WHERE business_id = @business_id AND role IN (${MANAGED_ROLES_SQL})
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
      .query(`SELECT id, name, phone FROM users WHERE id = @id AND business_id = @business_id AND role IN (${MANAGED_ROLES_SQL})`);

    if (snapshot.recordset.length === 0) {
      return res.status(404).json({ error: 'Staff member not found' });
    }

    // A staff member who created bills or expenses has financial records that
    // must NOT be deleted (their created_by_user_id FK is NO ACTION on purpose).
    // Block the delete with a clear message instead of a raw FK 500.
    const refs = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .query(`
        SELECT
          (SELECT COUNT(*) FROM bills    WHERE created_by_user_id = @id) AS bill_count,
          (SELECT COUNT(*) FROM expenses WHERE created_by_user_id = @id) AS expense_count
      `);
    const { bill_count, expense_count } = refs.recordset[0];
    if (bill_count > 0 || expense_count > 0) {
      return res.status(409).json({
        error: 'This staff member has billing/expense history and cannot be deleted. Deactivate the account instead.',
      });
    }

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      // Remove the user's device push tokens first — fcm_tokens.user_id is a
      // NO ACTION FK, so it blocks the user delete otherwise. refresh_tokens
      // cascade automatically. (A device token is safe to drop.)
      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`DELETE FROM fcm_tokens WHERE user_id = @id`);

      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`DELETE FROM users WHERE id = @id AND business_id = @business_id AND role IN (${MANAGED_ROLES_SQL})`);

      await transaction.commit();
    } catch (inner) {
      try { await transaction.rollback(); } catch (_) {}
      throw inner;
    }

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
  const { name, phone, pin, role } = req.body;

  if (!name && !phone && !pin && !role) {
    return res.status(400).json({ error: 'Provide at least one field to update' });
  }
  if (role && !MANAGED_ROLES.includes(role)) {
    return res.status(400).json({ error: `role must be one of: ${MANAGED_ROLES.join(', ')}` });
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
        WHERE id = @id AND business_id = @business_id AND role IN (${MANAGED_ROLES_SQL})
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
    if (role) {
      sets.push('role = @role');
      request.input('role', sql.NVarChar(20), role);
    }

    const result = await request.query(`
      UPDATE users
      SET ${sets.join(', ')}
      OUTPUT INSERTED.id, INSERTED.business_id, INSERTED.name, INSERTED.phone, INSERTED.role, INSERTED.created_at
      WHERE id = @id AND business_id = @business_id AND role IN (${MANAGED_ROLES_SQL})
    `);

    const updated = result.recordset[0];

    // Build a changes summary — never log the PIN hash
    const changes = {};
    if (name)  changes.name  = name;
    if (phone) changes.phone = phone;
    if (pin)   changes.pin_changed = true;
    if (role)  changes.role  = role;

    audit.logStaffUpdated(
      { business_id: req.user.business_id, user_id: req.user.user_id, user_name: req.user.name || null },
      updated,
      changes,
    );

    return res.json(updated);
  } catch (err) {
    if (err && (err.number === 2627 || err.number === 2601)) {
      return res.status(409).json({ error: 'This phone number is already registered.' });
    }
    logger.error({ err }, 'Update staff error');
    return res.status(500).json({ error: 'Failed to update staff' });
  }
});

module.exports = router;
