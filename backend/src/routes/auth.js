const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { pool, poolConnect, sql } = require('../db');
const crypto = require('crypto');
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require('../auth');
const { loginLimiter, registerLimiter, refreshLimiter } = require('../middleware/rateLimiter');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const audit = require('../audit');
const whatsapp = require('../whatsapp');

const router = express.Router();

const VALID_BUSINESS_TYPES = ['retail', 'restaurant_with_tables', 'restaurant_no_tables'];

// How many consecutive PIN failures before locking the account
const MAX_FAILED_ATTEMPTS = 10;
// How long to lock the account after MAX_FAILED_ATTEMPTS (milliseconds)
const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 minutes

// POST /api/register
router.post('/register', registerLimiter, async (req, res) => {
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

      // Fire-and-forget — alert admin about new onboarding request
      whatsapp.sendOnboardingAlert({
        businessName: business_name,
        ownerName:    owner_name,
        phone:        owner_phone,
        businessType: business_type,
      }).catch(err => logger.warn({ err }, 'Onboarding alert failed'));

      return res.json({ success: true, message: 'Registration successful. Account pending verification.' });
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    logger.error({ err }, 'Register error');
    return res.status(500).json({ error: 'Registration failed' });
  }
});

// POST /api/send-otp
// Sends a WhatsApp OTP to the given phone number.
// purpose: 'register' (before registration) | 'forgot_pin' (reset PIN)
router.post('/send-otp', registerLimiter, async (req, res) => {
  const { phone, purpose } = req.body;

  if (!phone || !purpose) {
    return res.status(400).json({ error: 'phone and purpose are required' });
  }
  if (!['register', 'forgot_pin'].includes(purpose)) {
    return res.status(400).json({ error: 'purpose must be "register" or "forgot_pin"' });
  }
  if (!/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Phone must be a 10-digit number' });
  }

  try {
    await poolConnect;
    const existing = await pool.request()
      .input('phone', sql.NVarChar(20), phone)
      .query(`SELECT id FROM users WHERE phone = @phone`);

    if (purpose === 'register' && existing.recordset.length > 0) {
      return res.status(409).json({ error: 'An account with this phone number already exists.' });
    }
    if (purpose === 'forgot_pin' && existing.recordset.length === 0) {
      return res.status(404).json({ error: 'No account found with this phone number.' });
    }
  } catch (err) {
    logger.error({ err }, 'send-otp phone lookup error');
    return res.status(500).json({ error: 'Failed to send OTP' });
  }

  try {
    const result = await whatsapp.sendOtp(phone, purpose);
    return res.json({
      success: true,
      message: 'OTP sent successfully.',
      // Only expose dev_otp in non-production environments
      ...(result.dev_otp ? { dev_otp: result.dev_otp } : {}),
    });
  } catch (err) {
    logger.error({ err }, 'send-otp error');
    return res.status(500).json({ error: err.message || 'Failed to send OTP' });
  }
});

// POST /api/verify-otp
// Verifies OTP for a given phone+purpose. Returns a short-lived verified token
// that the client must present when calling /register or /reset-pin.
router.post('/verify-otp', async (req, res) => {
  const { phone, otp, purpose } = req.body;

  if (!phone || !otp || !purpose) {
    return res.status(400).json({ error: 'phone, otp, and purpose are required' });
  }

  const valid = await whatsapp.verifyOtp(phone, otp, purpose);
  if (!valid) {
    return res.status(400).json({ error: 'Invalid or expired OTP' });
  }

  // Issue a short-lived signed token so the next step (register / reset-pin)
  // knows this phone was verified without storing extra session state.
  const verifiedToken = jwt.sign(
    { verified_phone: phone, purpose },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '15m' }
  );

  return res.json({ success: true, verified_token: verifiedToken });
});

// POST /api/reset-pin
// Resets the owner's PIN after OTP verification.
// Requires the verified_token issued by /verify-otp with purpose=forgot_pin.
router.post('/reset-pin', async (req, res) => {
  const { verified_token, new_pin } = req.body;

  if (!verified_token || !new_pin) {
    return res.status(400).json({ error: 'verified_token and new_pin are required' });
  }
  if (!/^\d{4}$/.test(new_pin)) {
    return res.status(400).json({ error: 'PIN must be exactly 4 digits' });
  }

  let payload;
  try {
    payload = jwt.verify(verified_token, process.env.JWT_ACCESS_SECRET);
  } catch {
    return res.status(401).json({ error: 'Invalid or expired verification token' });
  }

  if (payload.purpose !== 'forgot_pin' || !payload.verified_phone) {
    return res.status(400).json({ error: 'Token is not valid for PIN reset' });
  }

  try {
    await poolConnect;
    const pinHash = await bcrypt.hash(new_pin, 10);

    const result = await pool.request()
      .input('phone',    sql.NVarChar(20),  payload.verified_phone)
      .input('pin_hash', sql.NVarChar(255), pinHash)
      .query(`
        UPDATE users
        SET pin_hash = @pin_hash, failed_attempts = 0, locked_until = NULL
        WHERE phone = @phone
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.json({ success: true, message: 'PIN reset successfully.' });
  } catch (err) {
    logger.error({ err }, 'reset-pin error');
    return res.status(500).json({ error: 'PIN reset failed' });
  }
});

// POST /api/login
router.post('/login', loginLimiter, async (req, res) => {
  const { phone, pin } = req.body;

  if (!phone || !pin) {
    return res.status(400).json({ error: 'Phone and PIN are required' });
  }

  try {
    await poolConnect;

    // Look up user by phone (include lockout fields)
    const userResult = await pool.request()
      .input('phone', sql.NVarChar(20), phone)
      .query(`
        SELECT u.id, u.business_id, u.name, u.phone, u.pin_hash, u.role,
               u.failed_attempts, u.locked_until,
               b.name AS business_name, b.business_type, b.is_verified,
               b.inventory_enabled, b.has_barcode_scanner, b.address
        FROM users u
        JOIN businesses b ON u.business_id = b.id
        WHERE u.phone = @phone
      `);

    if (userResult.recordset.length === 0) {
      return res.status(404).json({ error: 'phone_not_found' });
    }

    const row = userResult.recordset[0];

    if (!row.is_verified) {
      return res.status(403).json({ error: 'Your account is pending verification. Please wait.' });
    }

    // Check account lockout
    if (row.locked_until && new Date(row.locked_until) > new Date()) {
      const retryAfterSec = Math.ceil((new Date(row.locked_until) - Date.now()) / 1000);
      res.set('Retry-After', retryAfterSec);
      return res.status(423).json({
        error: 'Account temporarily locked due to too many failed attempts.',
        retry_after_seconds: retryAfterSec,
      });
    }

    const pinMatch = await bcrypt.compare(pin, row.pin_hash);

    if (!pinMatch) {
      // Increment failure counter; lock if threshold reached
      const newAttempts = (row.failed_attempts || 0) + 1;
      const lockedUntil = newAttempts >= MAX_FAILED_ATTEMPTS
        ? new Date(Date.now() + LOCKOUT_DURATION_MS)
        : null;

      await pool.request()
        .input('id', sql.UniqueIdentifier, row.id)
        .input('failed_attempts', sql.Int, newAttempts)
        .input('locked_until', sql.DateTime2, lockedUntil)
        .query(`
          UPDATE users
          SET failed_attempts = @failed_attempts, locked_until = @locked_until
          WHERE id = @id
        `);

      if (lockedUntil) {
        audit.logUserLocked(row.business_id, row.id, row.name);
        const retryAfterSec = Math.ceil(LOCKOUT_DURATION_MS / 1000);
        res.set('Retry-After', retryAfterSec);
        return res.status(423).json({
          error: 'Account locked due to too many failed attempts. Try again in 15 minutes.',
          retry_after_seconds: retryAfterSec,
        });
      }

      audit.logLoginFailed(row.business_id, phone);
      return res.status(401).json({
        error: 'Invalid credentials',
        attempts_remaining: MAX_FAILED_ATTEMPTS - newAttempts,
      });
    }

    // PIN correct — reset lockout counters
    await pool.request()
      .input('id', sql.UniqueIdentifier, row.id)
      .query(`UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = @id`);

    const tokenPayload = {
      user_id: row.id,
      business_id: row.business_id,
      role: row.role,
    };
    const accessToken = signAccessToken(tokenPayload);
    const refreshToken = signRefreshToken(tokenPayload);

    // Store hashed refresh token in DB — each login starts a new token family
    const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days
    await pool.request()
      .input('user_id', sql.UniqueIdentifier, row.id)
      .input('business_id', sql.UniqueIdentifier, row.business_id)
      .input('token_hash', sql.NVarChar(64), tokenHash)
      .input('expires_at', sql.DateTime2, expiresAt)
      .query(`
        INSERT INTO refresh_tokens (user_id, business_id, token_hash, family_id, expires_at)
        VALUES (@user_id, @business_id, @token_hash, NEWID(), @expires_at)
      `);

    audit.logUserLogin(row.business_id, row.id, row.name);

    return res.json({
      success: true,
      access_token: accessToken,
      refresh_token: refreshToken,
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
    logger.error({ err }, 'Login error');
    return res.status(500).json({ error: 'Login failed' });
  }
});

// POST /api/refresh
// Issues a new access token using the stored refresh token.
// The refresh token itself is NOT rotated — it stays valid until it expires
// (30 days). This prevents spurious logouts caused by race conditions,
// interrupted saves, or app backgrounding mid-rotation.
router.post('/refresh', refreshLimiter, async (req, res) => {
  const { refresh_token } = req.body;
  if (!refresh_token) {
    return res.status(400).json({ error: 'refresh_token is required' });
  }

  let payload;
  try {
    payload = verifyRefreshToken(refresh_token);
  } catch {
    return res.status(401).json({ error: 'Invalid or expired refresh token' });
  }

  try {
    await poolConnect;
    const tokenHash = crypto.createHash('sha256').update(refresh_token).digest('hex');

    const result = await pool.request()
      .input('token_hash', sql.NVarChar(64), tokenHash)
      .input('now', sql.DateTime2, new Date())
      .query(`
        SELECT id FROM refresh_tokens
        WHERE token_hash = @token_hash
          AND revoked = 0
          AND expires_at > @now
      `);

    if (result.recordset.length === 0) {
      return res.status(401).json({ error: 'Invalid or expired refresh token' });
    }

    // Issue a new access token — refresh token stays unchanged
    const newAccessToken = signAccessToken({
      user_id:     payload.user_id,
      business_id: payload.business_id,
      role:        payload.role,
    });

    return res.json({ access_token: newAccessToken });
  } catch (err) {
    logger.error({ err }, 'Refresh error');
    return res.status(500).json({ error: 'Token refresh failed' });
  }
});

// POST /api/logout
// Revokes only the refresh token for this specific device/session.
router.post('/logout', async (req, res) => {
  const { refresh_token } = req.body;
  if (!refresh_token) {
    return res.status(400).json({ error: 'refresh_token is required' });
  }

  try {
    await poolConnect;
    const tokenHash = crypto.createHash('sha256').update(refresh_token).digest('hex');

    await pool.request()
      .input('token_hash', sql.NVarChar(64), tokenHash)
      .query(`UPDATE refresh_tokens SET revoked = 1 WHERE token_hash = @token_hash`);

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Logout error');
    return res.status(500).json({ error: 'Logout failed' });
  }
});

// POST /api/logout-all
// Revokes every active refresh token for the authenticated user.
// Use this to sign out of all devices at once.
router.post('/logout-all', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    await pool.request()
      .input('user_id', sql.UniqueIdentifier, req.user.user_id)
      .query(`UPDATE refresh_tokens SET revoked = 1 WHERE user_id = @user_id AND revoked = 0`);

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Logout-all error');
    return res.status(500).json({ error: 'Logout failed' });
  }
});

module.exports = router;
