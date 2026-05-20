const express = require('express');
const bcrypt = require('bcryptjs');
const { pool, poolConnect, sql } = require('../db');
const { signToken } = require('../auth');

const router = express.Router();

const VALID_BUSINESS_TYPES = ['retail', 'restaurant_with_tables', 'restaurant_no_tables'];

// POST /api/register
router.post('/register', async (req, res) => {
  const {
    business_name,
    business_type,
    address,
    phone,
    inventory_enabled,
    has_barcode_scanner,
    owner_name,
    owner_phone,
    pin,
  } = req.body;

  // Basic validation
  if (!business_name || !business_type || !phone || !owner_name || !owner_phone || !pin) {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  if (!VALID_BUSINESS_TYPES.includes(business_type)) {
    return res.status(400).json({ error: `business_type must be one of: ${VALID_BUSINESS_TYPES.join(', ')}` });
  }
  if (!/^\d{4}$/.test(pin)) {
    return res.status(400).json({ error: 'PIN must be exactly 4 digits' });
  }
  if (!/^\d{10}$/.test(phone) || !/^\d{10}$/.test(owner_phone)) {
    return res.status(400).json({ error: 'Phone must be a 10-digit number' });
  }

  try {
    await poolConnect;
    const pinHash = await bcrypt.hash(pin, 10);
    const transaction = pool.transaction();
    await transaction.begin();

    try {
      // Insert business
      const businessResult = await transaction.request()
        .input('name', sql.NVarChar(200), business_name)
        .input('business_type', sql.NVarChar(50), business_type)
        .input('address', sql.NVarChar(500), address || null)
        .input('phone', sql.NVarChar(20), phone)
        .input('inventory_enabled', sql.Bit, inventory_enabled ? 1 : 0)
        .input('has_barcode_scanner', sql.Bit, has_barcode_scanner ? 1 : 0)
        .query(`
          INSERT INTO businesses (name, business_type, address, phone, inventory_enabled, has_barcode_scanner)
          OUTPUT INSERTED.id
          VALUES (@name, @business_type, @address, @phone, @inventory_enabled, @has_barcode_scanner)
        `);

      const businessId = businessResult.recordset[0].id;

      // Insert owner user
      await transaction.request()
        .input('business_id', sql.UniqueIdentifier, businessId)
        .input('name', sql.NVarChar(200), owner_name)
        .input('phone', sql.NVarChar(20), owner_phone)
        .input('pin_hash', sql.NVarChar(255), pinHash)
        .query(`
          INSERT INTO users (business_id, name, phone, pin_hash, role)
          VALUES (@business_id, @name, @phone, @pin_hash, 'owner')
        `);

      await transaction.commit();
      return res.json({ success: true, message: 'Registration successful. Account pending verification.' });
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    console.error('Register error:', err.message);
    return res.status(500).json({ error: 'Registration failed' });
  }
});

// POST /api/login
router.post('/login', async (req, res) => {
  const { phone, pin } = req.body;

  if (!phone || !pin) {
    return res.status(400).json({ error: 'Phone and PIN are required' });
  }

  try {
    await poolConnect;

    // Look up user by phone
    const userResult = await pool.request()
      .input('phone', sql.NVarChar(20), phone)
      .query(`
        SELECT u.id, u.business_id, u.name, u.phone, u.pin_hash, u.role,
               b.name AS business_name, b.business_type, b.is_verified,
               b.inventory_enabled, b.has_barcode_scanner, b.address
        FROM users u
        JOIN businesses b ON u.business_id = b.id
        WHERE u.phone = @phone
      `);

    if (userResult.recordset.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const row = userResult.recordset[0];

    if (!row.is_verified) {
      return res.status(403).json({ error: 'Your account is pending verification. Please wait.' });
    }

    const pinMatch = await bcrypt.compare(pin, row.pin_hash);
    if (!pinMatch) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = signToken({
      user_id: row.id,
      business_id: row.business_id,
      role: row.role,
    });

    return res.json({
      success: true,
      token,
      user: {
        id: row.id,
        name: row.name,
        phone: row.phone,
        role: row.role,
      },
      business: {
        id: row.business_id,
        name: row.business_name,
        business_type: row.business_type,
        address: row.address,
        inventory_enabled: !!row.inventory_enabled,
        has_barcode_scanner: !!row.has_barcode_scanner,
      },
    });
  } catch (err) {
    console.error('Login error:', err.message);
    return res.status(500).json({ error: 'Login failed' });
  }
});

module.exports = router;
