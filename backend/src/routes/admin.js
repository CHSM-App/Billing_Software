'use strict';
// =============================================================================
// Internal admin dashboard — mounted at /admin (see server.js).
//
//   GET  /admin/:slug                 -> dashboard HTML (gated by ADMIN_URL_SLUG)
//   POST /admin/api/login             -> { username, password } -> admin JWT
//   GET  /admin/api/businesses        -> cross-business list (admin JWT)
//   PUT  /admin/api/businesses/:id    -> update subscription + flags (admin JWT)
//
// This is a platform-operator tool, entirely separate from the business-user
// JWT world. Two layers of protection:
//   1. The dashboard HTML is only reachable at the unguessable /admin/<slug>.
//   2. Every /admin/api/* call requires an admin session token (issued by
//      /admin/api/login after a username/password check), signed with
//      ADMIN_JWT_SECRET. The slug is NOT required on API calls (the token is).
//
// All credentials live in backend/.env:
//   ADMIN_URL_SLUG, ADMIN_USERNAME, ADMIN_PASSWORD, ADMIN_JWT_SECRET
// =============================================================================

const express = require('express');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const { pool, poolConnect, sql } = require('../db');
const logger = require('../logger');

const router = express.Router();

// The dashboard HTML shell, shipped with the code (survives CI deploys, which
// rebuild backend/public but never touch src/static).
const DASHBOARD_PATH = path.join(__dirname, '..', 'static', 'admin', 'index.html');
try {
  const st = fs.statSync(DASHBOARD_PATH);
  logger.info({ path: DASHBOARD_PATH, bytes: st.size }, 'admin dashboard shell found');
} catch (e) {
  logger.error({ path: DASHBOARD_PATH, err: e.message }, 'admin dashboard shell MISSING at boot');
}

const ADMIN_JWT_SECRET = process.env.ADMIN_JWT_SECRET;
const ADMIN_SESSION_TTL = '12h';

// Managed (non-owner) staff roles — must match routes/staff.js MANAGED_ROLES.
const MANAGED_ROLES_SQL = "'cashier', 'server', 'kitchen'";
const VALID_STATUSES = ['pending', 'active', 'suspended', 'expired'];
const VALID_WHATSAPP_MODES = ['deeplink', 'api'];

// ---------------------------------------------------------------------------
// Constant-time string comparison (avoids leaking length/timing on the secret).
// ---------------------------------------------------------------------------
function safeEqual(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) {
    // Still do a compare against self to keep timing uniform, then fail.
    crypto.timingSafeEqual(ba, ba);
    return false;
  }
  return crypto.timingSafeEqual(ba, bb);
}

// ---------------------------------------------------------------------------
// Admin session middleware — verifies the Bearer admin JWT.
// ---------------------------------------------------------------------------
function requireAdmin(req, res, next) {
  const header = req.headers['authorization'] || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const payload = jwt.verify(token, ADMIN_JWT_SECRET);
    if (payload.typ !== 'admin') throw new Error('wrong token type');
    req.admin = payload;
    return next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired admin session' });
  }
}

// ---------------------------------------------------------------------------
// GET /admin/:slug — serve the dashboard HTML if the slug matches.
// A wrong/missing slug returns 404 (indistinguishable from any other bad path)
// so the dashboard's existence isn't advertised.
// ---------------------------------------------------------------------------
router.get('/:slug', (req, res) => {
  if (!process.env.ADMIN_URL_SLUG || req.params.slug !== process.env.ADMIN_URL_SLUG) {
    return res.status(404).send('<h2>Not found</h2>');
  }
  // Read + send the bytes ourselves instead of res.sendFile: under iisnode,
  // sendFile's internal `send` can 404 on a file that exists (path/stat quirks
  // via the named-pipe FS) and swallow the real error — the request then falls
  // through to the SPA catch-all, so the browser loads the app shell and its
  // router prints "No routes matched /admin/…". fs.readFile is reliable and
  // surfaces the true errno. (Same fix the /order page uses.)
  return fs.readFile(DASHBOARD_PATH, (err, buf) => {
    if (err) {
      logger.error({ err, path: DASHBOARD_PATH }, 'Admin dashboard file read failed');
      return res.status(500).send('Admin dashboard is temporarily unavailable.');
    }
    res.set('Content-Type', 'text/html; charset=utf-8');
    res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
    return res.send(buf);
  });
});

// ---------------------------------------------------------------------------
// POST /admin/api/login — { username, password } -> { token }
// ---------------------------------------------------------------------------
router.post('/api/login', express.json(), (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ error: 'username and password are required' });
  }
  const okUser = safeEqual(username, process.env.ADMIN_USERNAME || '');
  const okPass = safeEqual(password, process.env.ADMIN_PASSWORD || '');
  // Evaluate both regardless of the first result to keep timing uniform.
  if (!okUser || !okPass) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  const token = jwt.sign({ typ: 'admin', sub: username }, ADMIN_JWT_SECRET, {
    expiresIn: ADMIN_SESSION_TTL,
  });
  return res.json({ token });
});

// ---------------------------------------------------------------------------
// GET /admin/api/businesses — full cross-business list for the dashboard.
// Joins businesses + owner user + subscription + live staff count.
// ---------------------------------------------------------------------------
router.get('/api/businesses', requireAdmin, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request().query(`
      SELECT
        b.id, b.name, b.business_type, b.phone, b.address,
        b.is_verified, b.whatsapp_mode, b.created_at, b.last_active_at,
        u.name  AS owner_name,
        u.phone AS owner_phone,
        s.status            AS sub_status,
        s.expires_at        AS sub_expires_at,
        s.max_offline_days  AS max_offline_days,
        s.grace_period_days AS grace_period_days,
        s.is_trial          AS is_trial,
        s.max_staff         AS max_staff,
        s.allow_mobile      AS allow_mobile,
        s.allow_desktop     AS allow_desktop,
        s.allow_online_store AS allow_online_store,
        (SELECT COUNT(*) FROM users su
           WHERE su.business_id = b.id
             AND su.role IN (${MANAGED_ROLES_SQL})) AS staff_count,
        (SELECT COUNT(*) FROM bills bl
           WHERE bl.business_id = b.id
             AND bl.status = 'finalized') AS bill_count,
        (SELECT COUNT(*) FROM items it
           WHERE it.business_id = b.id) AS item_count
      FROM businesses b
      LEFT JOIN users u ON u.business_id = b.id AND u.role = 'owner'
      LEFT JOIN subscriptions s ON s.business_id = b.id
      ORDER BY b.created_at DESC
    `);

    const businesses = result.recordset.map((r) => ({
      id:                r.id,
      name:              r.name,
      business_type:     r.business_type,
      phone:             r.phone,
      address:           r.address ?? null,
      is_verified:       !!r.is_verified,
      whatsapp_mode:     r.whatsapp_mode || 'deeplink',
      created_at:        r.created_at,
      last_active_at:    r.last_active_at ?? null,
      owner_name:        r.owner_name ?? null,
      owner_phone:       r.owner_phone ?? null,
      subscription: r.sub_status == null ? null : {
        status:            r.sub_status,
        expires_at:        r.sub_expires_at,
        max_offline_days:  r.max_offline_days,
        grace_period_days: r.grace_period_days,
        is_trial:          !!r.is_trial,
        max_staff:         r.max_staff,
        allow_mobile:      !!r.allow_mobile,
        allow_desktop:     !!r.allow_desktop,
        allow_online_store: r.allow_online_store == null ? true : !!r.allow_online_store,
      },
      staff_count:       r.staff_count,
      bill_count:        r.bill_count,
      item_count:        r.item_count,
    }));

    return res.json({ businesses });
  } catch (err) {
    logger.error({ err }, 'admin list businesses error');
    return res.status(500).json({ error: 'Failed to load businesses' });
  }
});

// ---------------------------------------------------------------------------
// PUT /admin/api/businesses/:id — update a business's subscription + flags.
// Body may include any of:
//   status, expires_at, max_offline_days, grace_period_days,
//   max_staff, allow_mobile, allow_desktop, allow_online_store (-> subscriptions, upserted)
//   whatsapp_mode, is_verified                  (-> businesses)
// Only the provided fields are changed. Mirrors the /api/license/admin/activate
// MERGE so a business with no subscription row still gets one created.
// ---------------------------------------------------------------------------
router.put('/api/businesses/:id', requireAdmin, express.json(), async (req, res) => {
  const businessId = req.params.id;
  const {
    status, expires_at, max_offline_days, grace_period_days,
    max_staff, allow_mobile, allow_desktop, allow_online_store, is_trial,
    whatsapp_mode, is_verified,
  } = req.body || {};

  // ── Validation ────────────────────────────────────────────────────────────
  if (status !== undefined && !VALID_STATUSES.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${VALID_STATUSES.join(', ')}` });
  }
  if (whatsapp_mode !== undefined && !VALID_WHATSAPP_MODES.includes(whatsapp_mode)) {
    return res.status(400).json({ error: `whatsapp_mode must be one of: ${VALID_WHATSAPP_MODES.join(', ')}` });
  }
  let expiresDate;
  if (expires_at !== undefined) {
    expiresDate = new Date(expires_at);
    if (isNaN(expiresDate.getTime())) {
      return res.status(400).json({ error: 'expires_at is not a valid date' });
    }
  }
  const intFields = { max_offline_days, grace_period_days, max_staff };
  for (const [k, v] of Object.entries(intFields)) {
    if (v !== undefined && (!Number.isInteger(v) || v < 0)) {
      return res.status(400).json({ error: `${k} must be a non-negative integer` });
    }
  }

  try {
    await poolConnect;

    // Confirm the business exists (so we don't silently upsert a subscription
    // for a non-existent business_id, which would also FK-fail).
    const bizCheck = await pool.request()
      .input('id', sql.UniqueIdentifier, businessId)
      .query(`SELECT id FROM businesses WHERE id = @id`);
    if (bizCheck.recordset.length === 0) {
      return res.status(404).json({ error: 'Business not found' });
    }

    // ── businesses fields (whatsapp_mode, is_verified) ──────────────────────
    const bizSets = [];
    const bizReq = pool.request().input('id', sql.UniqueIdentifier, businessId);
    if (whatsapp_mode !== undefined) {
      bizReq.input('whatsapp_mode', sql.NVarChar(20), whatsapp_mode);
      bizSets.push('whatsapp_mode = @whatsapp_mode');
    }
    if (is_verified !== undefined) {
      bizReq.input('is_verified', sql.Bit, is_verified ? 1 : 0);
      bizSets.push('is_verified = @is_verified');
    }
    if (bizSets.length > 0) {
      await bizReq.query(`UPDATE businesses SET ${bizSets.join(', ')} WHERE id = @id`);
    }

    // ── subscription fields (upsert via MERGE) ──────────────────────────────
    const subProvided = [status, expires_at, max_offline_days, grace_period_days,
      max_staff, allow_mobile, allow_desktop, allow_online_store, is_trial]
      .some((v) => v !== undefined);

    if (subProvided) {
      // Read current row so an upsert of a partial set keeps existing values
      // for the fields the admin didn't send.
      const cur = await pool.request()
        .input('id', sql.UniqueIdentifier, businessId)
        .query(`SELECT status, expires_at, max_offline_days, grace_period_days,
                       max_staff, allow_mobile, allow_desktop, allow_online_store, is_trial
                FROM subscriptions WHERE business_id = @id`);
      const c = cur.recordset[0] || {};

      // Resolve effective values (provided → keep current → sensible default).
      const effStatus          = status           !== undefined ? status           : (c.status ?? 'active');
      const effExpires         = expires_at       !== undefined ? expiresDate      : (c.expires_at ?? new Date(Date.now() + 365 * 24 * 60 * 60 * 1000));
      const effMaxOffline      = max_offline_days  !== undefined ? max_offline_days : (c.max_offline_days ?? 30);
      const effGrace           = grace_period_days !== undefined ? grace_period_days: (c.grace_period_days ?? 5);
      const effMaxStaff        = max_staff         !== undefined ? max_staff        : (c.max_staff ?? 10);
      const effAllowMobile     = allow_mobile      !== undefined ? (allow_mobile ? 1 : 0)  : (c.allow_mobile  != null ? c.allow_mobile  : 1);
      const effAllowDesktop    = allow_desktop     !== undefined ? (allow_desktop ? 1 : 0) : (c.allow_desktop != null ? c.allow_desktop : 1);
      const effAllowOnlineStore = allow_online_store !== undefined ? (allow_online_store ? 1 : 0) : (c.allow_online_store != null ? c.allow_online_store : 1);
      const effIsTrial         = is_trial          !== undefined ? (is_trial ? 1 : 0)      : (c.is_trial      != null ? c.is_trial      : 0);

      const mReq = pool.request()
        .input('business_id', sql.UniqueIdentifier, businessId)
        .input('status', sql.NVarChar(20), effStatus)
        .input('expires_at', sql.DateTime2, effExpires)
        .input('max_offline_days', sql.Int, effMaxOffline)
        .input('grace_period_days', sql.Int, effGrace)
        .input('max_staff', sql.Int, effMaxStaff)
        .input('allow_mobile', sql.Bit, effAllowMobile)
        .input('allow_desktop', sql.Bit, effAllowDesktop)
        .input('allow_online_store', sql.Bit, effAllowOnlineStore)
        .input('is_trial', sql.Bit, effIsTrial);

      await mReq.query(`
        MERGE subscriptions AS target
        USING (SELECT @business_id AS business_id) AS source
          ON target.business_id = source.business_id
        WHEN MATCHED THEN
          UPDATE SET
            status            = @status,
            expires_at        = @expires_at,
            max_offline_days  = @max_offline_days,
            grace_period_days = @grace_period_days,
            max_staff         = @max_staff,
            allow_mobile      = @allow_mobile,
            allow_desktop     = @allow_desktop,
            allow_online_store = @allow_online_store,
            is_trial          = @is_trial,
            updated_at        = GETUTCDATE()
        WHEN NOT MATCHED THEN
          INSERT (business_id, status, expires_at, max_offline_days, grace_period_days,
                  max_staff, allow_mobile, allow_desktop, allow_online_store, is_trial)
          VALUES (@business_id, @status, @expires_at, @max_offline_days, @grace_period_days,
                  @max_staff, @allow_mobile, @allow_desktop, @allow_online_store, @is_trial);
      `);

      // Activating a paid subscription should also verify the business, matching
      // /api/license/admin/activate's behaviour — unless the admin explicitly
      // sent is_verified in this same request.
      if (status === 'active' && is_verified === undefined) {
        await pool.request()
          .input('id', sql.UniqueIdentifier, businessId)
          .query(`UPDATE businesses SET is_verified = 1 WHERE id = @id`);
      }
    }

    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'admin update business error');
    return res.status(500).json({ error: 'Failed to update business' });
  }
});

module.exports = router;
