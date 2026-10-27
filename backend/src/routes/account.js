'use strict';

/**
 * Account deletion endpoints — called by the public landing page form.
 * No app JWT required. Identity is proven entirely via WhatsApp OTP.
 *
 * Flow:
 *   1. POST /api/account/deletion/request
 *        • Accepts phone number
 *        • Sends WhatsApp OTP (purpose = 'delete_account')
 *        • Always returns 200 (no user enumeration)
 *
 *   2. POST /api/account/deletion/confirm
 *        • Accepts { phone, otp, reason? }
 *        • Verifies OTP
 *        • Creates account_deletion_requests row (scheduled_for = now + 30 days)
 *        • Writes audit log
 *        • Returns scheduled_for date
 *
 *   3. POST /api/account/deletion/cancel
 *        • Accepts { phone, otp }
 *        • Verifies OTP (fresh OTP required — no stale token reuse)
 *        • Marks pending request as cancelled
 *        • Writes audit log
 */

const express = require('express');
const jwt     = require('jsonwebtoken');
const { pool, poolConnect, sql } = require('../db');
const logger    = require('../logger');
const audit     = require('../audit');
const whatsapp  = require('../whatsapp');
const { deletionLimiter, otpSendLimiter, otpPhoneDailyLimiter, otpVerifyLimiter } = require('../middleware/rateLimiter');
const { requireAuth } = require('../auth');
const { TERMS_VERSION } = require('../legal');

const router = express.Router();

const DELETION_DELAY_DAYS = 30;
const OTP_PURPOSE = 'delete_account';

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/account/deletion/request
// Sends a WhatsApp OTP to the supplied phone number.
// Always returns 200 regardless of whether the phone exists — prevents
// attackers from enumerating which phones have Vittam accounts.
// ─────────────────────────────────────────────────────────────────────────────

router.post('/deletion/request', deletionLimiter, otpSendLimiter, otpPhoneDailyLimiter, async (req, res) => {
  const { phone } = req.body;

  if (!phone || !/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'A valid 10-digit phone number is required.' });
  }

  try {
    await poolConnect;

    // Check the phone belongs to an owner — but don't reveal this to the caller
    const userResult = await pool.request()
      .input('phone', sql.NVarChar(20), phone)
      .query(`
        SELECT u.id
        FROM users u
        WHERE u.phone = @phone AND u.role = 'owner'
      `);

    if (userResult.recordset.length === 0) {
      // Return success anyway — no enumeration
      logger.info({ phone }, '[account-deletion] request for unknown phone — silently ignored');
      return res.json({ success: true, message: 'If an account exists for this number, an OTP has been sent.' });
    }

    // Send OTP — failures are logged inside whatsapp.sendOtp, never exposed here
    try {
      const result = await whatsapp.sendOtp(phone, OTP_PURPOSE);
      return res.json({
        success: true,
        message: 'If an account exists for this number, an OTP has been sent.',
        ...(result.dev_otp ? { dev_otp: result.dev_otp } : {}),
      });
    } catch (err) {
      logger.error({ err, phone }, '[account-deletion] OTP send failed');
      return res.status(500).json({ error: 'Failed to send OTP. Please try again.' });
    }
  } catch (err) {
    logger.error({ err }, '[account-deletion] request error');
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/account/deletion/confirm
// Verifies the OTP and creates a pending deletion request.
// ─────────────────────────────────────────────────────────────────────────────

router.post('/deletion/confirm', deletionLimiter, otpVerifyLimiter, async (req, res) => {
  const { phone, otp, reason } = req.body;

  if (!phone || !/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'A valid 10-digit phone number is required.' });
  }
  if (!otp || !/^\d{6}$/.test(String(otp))) {
    return res.status(400).json({ error: 'OTP must be a 6-digit number.' });
  }

  try {
    await poolConnect;

    // Verify OTP
    const otpValid = await whatsapp.verifyOtp(phone, String(otp), OTP_PURPOSE);
    if (!otpValid) {
      return res.status(400).json({ error: 'Invalid or expired OTP.' });
    }

    // Fetch owner user
    const userResult = await pool.request()
      .input('phone', sql.NVarChar(20), phone)
      .query(`
        SELECT u.id AS user_id, u.name, u.business_id
        FROM users u
        WHERE u.phone = @phone AND u.role = 'owner'
      `);

    if (userResult.recordset.length === 0) {
      // OTP was valid but no owner found — shouldn't normally happen
      return res.status(404).json({ error: 'No owner account found for this phone number.' });
    }

    const { user_id, name, business_id } = userResult.recordset[0];

    // Check for an existing pending request
    const existingResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, business_id)
      .query(`
        SELECT id, scheduled_for
        FROM account_deletion_requests
        WHERE business_id = @business_id AND status = 'pending'
      `);

    if (existingResult.recordset.length > 0) {
      const existing = existingResult.recordset[0];
      return res.status(409).json({
        error: 'A deletion request already exists for this account.',
        scheduled_for: existing.scheduled_for,
      });
    }

    const now = new Date();
    const scheduledFor = new Date(now.getTime() + DELETION_DELAY_DAYS * 24 * 60 * 60 * 1000);

    await pool.request()
      .input('business_id',     sql.UniqueIdentifier, business_id)
      .input('requested_by',    sql.UniqueIdentifier, user_id)
      .input('phone',           sql.NVarChar(20),     phone)
      .input('reason',          sql.NVarChar(500),    reason ? String(reason).slice(0, 500) : null)
      .input('otp_verified_at', sql.DateTime2,        now)
      .input('scheduled_for',   sql.DateTime2,        scheduledFor)
      .query(`
        INSERT INTO account_deletion_requests
          (business_id, requested_by, phone, reason, otp_verified_at, scheduled_for)
        VALUES
          (@business_id, @requested_by, @phone, @reason, @otp_verified_at, @scheduled_for)
      `);

    // Audit log — non-fatal
    await audit.logAccountDeletionRequested(business_id, user_id, name, scheduledFor);

    logger.info({ business_id, user_id, scheduled_for: scheduledFor }, '[account-deletion] deletion request created');

    return res.json({
      success: true,
      message: `Your account is scheduled for deletion on ${scheduledFor.toDateString()}. You can cancel this request before that date.`,
      scheduled_for: scheduledFor,
    });
  } catch (err) {
    logger.error({ err }, '[account-deletion] confirm error');
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/account/deletion/cancel
// Cancels a pending deletion request. Requires a fresh OTP to prevent
// someone other than the owner from cancelling the request.
// ─────────────────────────────────────────────────────────────────────────────

router.post('/deletion/cancel', deletionLimiter, otpVerifyLimiter, async (req, res) => {
  const { phone, otp } = req.body;

  if (!phone || !/^\d{10}$/.test(phone)) {
    return res.status(400).json({ error: 'A valid 10-digit phone number is required.' });
  }
  if (!otp || !/^\d{6}$/.test(String(otp))) {
    return res.status(400).json({ error: 'OTP must be a 6-digit number.' });
  }

  try {
    await poolConnect;

    // Verify fresh OTP
    const otpValid = await whatsapp.verifyOtp(phone, String(otp), OTP_PURPOSE);
    if (!otpValid) {
      return res.status(400).json({ error: 'Invalid or expired OTP.' });
    }

    // Find the owner
    const userResult = await pool.request()
      .input('phone', sql.NVarChar(20), phone)
      .query(`
        SELECT u.id AS user_id, u.name, u.business_id
        FROM users u
        WHERE u.phone = @phone AND u.role = 'owner'
      `);

    if (userResult.recordset.length === 0) {
      return res.status(404).json({ error: 'No owner account found for this phone number.' });
    }

    const { user_id, name, business_id } = userResult.recordset[0];

    // Find the pending request
    const requestResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, business_id)
      .query(`
        SELECT id FROM account_deletion_requests
        WHERE business_id = @business_id AND status = 'pending'
      `);

    if (requestResult.recordset.length === 0) {
      return res.status(404).json({ error: 'No pending deletion request found for this account.' });
    }

    const requestId = requestResult.recordset[0].id;

    await pool.request()
      .input('id', sql.UniqueIdentifier, requestId)
      .query(`
        UPDATE account_deletion_requests
        SET status = 'cancelled'
        WHERE id = @id
      `);

    await audit.logAccountDeletionCancelled(business_id, user_id, name);

    logger.info({ business_id, user_id, request_id: requestId }, '[account-deletion] deletion request cancelled');

    return res.json({
      success: true,
      message: 'Your account deletion request has been cancelled. Your account is safe.',
    });
  } catch (err) {
    logger.error({ err }, '[account-deletion] cancel error');
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/account/accept-terms   (app JWT required — unlike the routes above)
// Body: { terms_version }
// The "Agree" on the updated-terms screen an existing owner sees while
// GET /license says terms_required. The body's version must equal the server's
// (src/legal.js): it proves the screen showed the current version, and a
// client can never record a version of its own choosing. The acceptance is
// always for the token's own user — there is no user id in the body.
// ─────────────────────────────────────────────────────────────────────────────
router.post('/accept-terms', requireAuth, async (req, res) => {
  if (!TERMS_VERSION || req.body?.terms_version !== TERMS_VERSION) {
    return res.status(409).json({
      // `error` is the readable text (the app shows it); `code` is for logic.
      error: 'These terms have changed. Please reopen the app to see the current version.',
      code: 'terms_version_mismatch',
      terms_version: TERMS_VERSION,
    });
  }

  const { user_id, business_id } = req.user;
  try {
    await poolConnect;

    // Role from the DB, not the token: only the OWNER agrees for the business.
    const userResult = await pool.request()
      .input('user_id', sql.UniqueIdentifier, user_id)
      .input('business_id', sql.UniqueIdentifier, business_id)
      .query(`
        SELECT name, role FROM users
        WHERE id = @user_id AND business_id = @business_id AND is_active = 1
      `);
    const user = userResult.recordset[0];
    if (!user || user.role !== 'owner') {
      return res.status(403).json({ error: 'Only the business owner can accept the terms.' });
    }

    // Insert-if-absent: accepting the same version twice (double tap, two
    // devices) is a success that writes nothing new.
    let inserted = 0;
    try {
      const result = await pool.request()
        .input('user_id', sql.UniqueIdentifier, user_id)
        .input('business_id', sql.UniqueIdentifier, business_id)
        .input('terms_version', sql.NVarChar(20), TERMS_VERSION)
        .input('ip_address', sql.NVarChar(45), req.ip || null)
        .query(`
          INSERT INTO terms_acceptances (user_id, business_id, terms_version, source, ip_address)
          SELECT @user_id, @business_id, @terms_version, 'reaccept', @ip_address
          WHERE NOT EXISTS (
            SELECT 1 FROM terms_acceptances
            WHERE user_id = @user_id AND terms_version = @terms_version
          )
        `);
      inserted = result.rowsAffected?.[0] ?? 0;
    } catch (err) {
      // 2627/2601 = the unique index lost a race with a parallel request that
      // already recorded this exact acceptance — same outcome as NOT EXISTS.
      if (err.number !== 2627 && err.number !== 2601) throw err;
    }

    if (inserted > 0) {
      await audit.logTermsAccepted(business_id, user_id, user.name, TERMS_VERSION, 'reaccept');
    }
    return res.json({ success: true, terms_version: TERMS_VERSION });
  } catch (err) {
    logger.error({ err }, '[terms] accept error');
    return res.status(500).json({ error: 'Could not save your acceptance. Please try again.' });
  }
});

module.exports = router;
