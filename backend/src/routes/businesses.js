const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const audit = require('../audit');
const logger = require('../logger');

const router = express.Router();

// Only the owner of the business may read or modify the profile.
function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Owner access required' });
  }
  return next();
}

// Validate GSTIN format: 2-digit state + 10-char PAN + 1 entity + 1 checksum + Z
// Example: 27ABCDE1234F1Z5
const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/;
// PAN: 5 letters + 4 digits + 1 letter
const PAN_RE = /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/;
// Pincode: 6 digits
const PIN_RE = /^[0-9]{6}$/;
// FSSAI license number: exactly 14 digits
const FSSAI_RE = /^[0-9]{14}$/;

// ---------------------------------------------------------------------------
// GET /api/businesses/profile
// Returns the full business profile for the authenticated user's business.
// ---------------------------------------------------------------------------
router.get('/profile', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.user.business_id)
      .input('user_id', sql.UniqueIdentifier, req.user.user_id)
      .query(`
        SELECT
          b.id, b.name, b.business_type, b.address, b.phone,
          b.inventory_enabled, b.has_barcode_scanner,
          b.self_order_enabled,
          b.gst_number, b.pan_number, b.fssai_number, b.email, b.website,
          b.city, b.state, b.pincode, b.logo_url,
          b.bill_prefix, b.bill_footer_note,
          b.gst_enabled, b.default_sac_code,
          b.round_off_enabled,
          b.created_at,
          u.name  AS owner_name,
          u.phone AS owner_phone
        FROM businesses b
        LEFT JOIN users u ON u.id = @user_id
        WHERE b.id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Business not found' });
    }

    const row = result.recordset[0];
    const formatted = _formatBusiness(row);
    // Owner account info — shown read-only in the app (not editable here).
    formatted.owner_name = row.owner_name || null;
    formatted.owner_phone = row.owner_phone || null;
    return res.json(formatted);
  } catch (err) {
    logger.error({ err }, 'Get business profile error');
    return res.status(500).json({ error: 'Failed to fetch business profile' });
  }
});

// ---------------------------------------------------------------------------
// PUT /api/businesses/profile
// Updates editable business profile fields.
// Owner-only. Business type and is_verified are immutable via this endpoint.
// ---------------------------------------------------------------------------
router.put('/profile', requireAuth, ownerOnly, async (req, res) => {
  const {
    name,
    address,
    phone,
    email,
    website,
    city,
    state,
    pincode,
    gst_number,
    pan_number,
    fssai_number,
    logo_url,
    bill_prefix,
    bill_footer_note,
    self_order_enabled,
    inventory_enabled,
    has_barcode_scanner,
    gst_enabled,
    default_sac_code,
    round_off_enabled,
  } = req.body;

  // ── Validation ────────────────────────────────────────────────────────────

  if (name !== undefined && (!name || name.trim().length === 0)) {
    return res.status(400).json({ error: 'Business name cannot be empty' });
  }
  if (phone !== undefined && !/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Phone must be a 10-digit number' });
  }
  if (email !== undefined && email !== null && email !== '') {
    // Simple RFC-ish check: local@domain.tld
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return res.status(400).json({ error: 'Invalid email address' });
    }
  }
  if (gst_number !== undefined && gst_number !== null && gst_number !== '') {
    if (!GSTIN_RE.test(gst_number)) {
      return res.status(400).json({ error: 'Invalid GSTIN format (e.g. 27ABCDE1234F1Z5)' });
    }
  }
  if (pan_number !== undefined && pan_number !== null && pan_number !== '') {
    if (!PAN_RE.test(pan_number)) {
      return res.status(400).json({ error: 'Invalid PAN format (e.g. ABCDE1234F)' });
    }
  }
  if (fssai_number !== undefined && fssai_number !== null && fssai_number !== '') {
    if (!FSSAI_RE.test(fssai_number)) {
      return res.status(400).json({ error: 'Invalid FSSAI number — must be exactly 14 digits' });
    }
  }
  if (pincode !== undefined && pincode !== null && pincode !== '') {
    if (!PIN_RE.test(pincode)) {
      return res.status(400).json({ error: 'Invalid pincode — must be 6 digits' });
    }
  }
  if (bill_prefix !== undefined && bill_prefix !== null) {
    const trimmed = bill_prefix.trim();
    if (trimmed.length === 0 || trimmed.length > 10) {
      return res.status(400).json({ error: 'Bill prefix must be 1–10 characters' });
    }
    if (!/^[A-Za-z0-9\-/]+$/.test(trimmed)) {
      return res.status(400).json({ error: 'Bill prefix may only contain letters, numbers, hyphens, or slashes' });
    }
  }
  if (bill_footer_note !== undefined && bill_footer_note !== null &&
      bill_footer_note.length > 500) {
    return res.status(400).json({ error: 'Bill footer note must be 500 characters or less' });
  }

  // ── Build dynamic SET clause ──────────────────────────────────────────────

  // Only update fields that were explicitly sent in the request body.
  const updatable = {
    name,
    address,
    phone,
    email,
    website,
    city,
    state,
    pincode,
    gst_number,
    pan_number,
    fssai_number,
    logo_url,
    bill_prefix,
    bill_footer_note,
    self_order_enabled,
    inventory_enabled,
    has_barcode_scanner,
    gst_enabled,
    default_sac_code,
    round_off_enabled,
  };

  const fields = Object.entries(updatable).filter(([, v]) => v !== undefined);
  if (fields.length === 0) {
    return res.status(400).json({ error: 'No fields provided to update' });
  }

  try {
    await poolConnect;

    // Snapshot old values for audit (only the fields being changed)
    const oldResult = await pool.request()
      .input('id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT
          name, address, phone, email, website,
          city, state, pincode, gst_number, pan_number, fssai_number,
          logo_url, bill_prefix, bill_footer_note,
          gst_enabled, default_sac_code, round_off_enabled
        FROM businesses WHERE id = @id
      `);

    if (oldResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Business not found' });
    }

    const old = oldResult.recordset[0];

    // Check GSTIN uniqueness (only when changing it)
    if (gst_number !== undefined && gst_number !== null && gst_number !== '' &&
        gst_number !== old.gst_number) {
      const dupCheck = await pool.request()
        .input('gst', sql.NVarChar(15), gst_number)
        .input('id',  sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT 1 FROM businesses
          WHERE gst_number = @gst AND id != @id
        `);
      if (dupCheck.recordset.length > 0) {
        return res.status(409).json({ error: 'This GSTIN is already registered with another business' });
      }
    }

    // Build parameterised UPDATE
    const req2 = pool.request();
    req2.input('id', sql.UniqueIdentifier, req.user.business_id);

    const setClauses = fields.map(([key, value]) => {
      const sqlType = _sqlTypeFor(key);
      // BIT columns take a normalised 0/1; text columns treat '' as NULL.
      const isBit = key === 'self_order_enabled' ||
          key === 'inventory_enabled' || key === 'has_barcode_scanner' ||
          key === 'gst_enabled' || key === 'round_off_enabled';
      const normalised = isBit
        ? (value ? 1 : 0)
        : (value === '' ? null : value);
      req2.input(key, sqlType, normalised);
      return `${key} = @${key}`;
    });

    await req2.query(`
      UPDATE businesses
      SET ${setClauses.join(', ')}
      WHERE id = @id
    `);

    // Fetch updated row to return
    const updated = await pool.request()
      .input('id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT
          id, name, business_type, address, phone,
          inventory_enabled, has_barcode_scanner,
          self_order_enabled,
          gst_number, pan_number, fssai_number, email, website,
          city, state, pincode, logo_url,
          bill_prefix, bill_footer_note,
          gst_enabled, default_sac_code, round_off_enabled,
          created_at
        FROM businesses WHERE id = @id
      `);

    const newBusiness = _formatBusiness(updated.recordset[0]);

    // Audit — only the changed fields
    const oldSnapshot = {};
    const newSnapshot = {};
    for (const [key] of fields) {
      oldSnapshot[key] = old[key] ?? null;
      newSnapshot[key] = (newBusiness[key] ?? null);
    }

    audit.logBusinessProfileUpdated(
      { user_id: req.user.user_id, user_name: req.user.name, business_id: req.user.business_id },
      oldSnapshot,
      newSnapshot,
    );

    return res.json(newBusiness);
  } catch (err) {
    logger.error({ err }, 'Update business profile error');
    return res.status(500).json({ error: 'Failed to update business profile' });
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function _formatBusiness(row) {
  return {
    id:                  row.id,
    name:                row.name,
    business_type:       row.business_type,
    address:             row.address ?? null,
    phone:               row.phone,
    inventory_enabled:   !!row.inventory_enabled,
    has_barcode_scanner: !!row.has_barcode_scanner,
    self_order_enabled:  !!row.self_order_enabled,
    gst_number:          row.gst_number ?? null,
    pan_number:          row.pan_number ?? null,
    fssai_number:        row.fssai_number ?? null,
    email:               row.email ?? null,
    website:             row.website ?? null,
    city:                row.city ?? null,
    state:               row.state ?? null,
    pincode:             row.pincode ?? null,
    logo_url:            row.logo_url ?? null,
    bill_prefix:         row.bill_prefix ?? 'INV',
    bill_footer_note:    row.bill_footer_note ?? null,
    gst_enabled:         !!row.gst_enabled,
    default_sac_code:    row.default_sac_code ?? null,
    round_off_enabled:   !!row.round_off_enabled,
    created_at:          row.created_at,
  };
}

/** Maps column name to the correct mssql type for parameterised queries. */
function _sqlTypeFor(key) {
  const map = {
    name:             sql.NVarChar(200),
    address:          sql.NVarChar(500),
    phone:            sql.NVarChar(20),
    email:            sql.NVarChar(200),
    website:          sql.NVarChar(500),
    city:             sql.NVarChar(100),
    state:            sql.NVarChar(100),
    pincode:          sql.NVarChar(10),
    gst_number:       sql.NVarChar(15),
    pan_number:       sql.NVarChar(10),
    fssai_number:     sql.NVarChar(20),
    logo_url:         sql.NVarChar(1000),
    bill_prefix:      sql.NVarChar(10),
    bill_footer_note: sql.NVarChar(500),
    self_order_enabled: sql.Bit,
    inventory_enabled: sql.Bit,
    has_barcode_scanner: sql.Bit,
    gst_enabled:       sql.Bit,
    default_sac_code:  sql.NVarChar(10),
    round_off_enabled: sql.Bit,
  };
  return map[key] ?? sql.NVarChar(500);
}

module.exports = router;
