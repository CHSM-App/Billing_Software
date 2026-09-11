const { Router } = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = Router();

// ---------------------------------------------------------------------------
// GET /api/license
// Called by the app after login to fetch/refresh the license status.
// Returns subscription details so the app can store them locally.
// ---------------------------------------------------------------------------
router.get('/', requireAuth, async (req, res) => {
  try {
    await poolConnect;

    // Stamp last-active — this endpoint is hit on every app open / resume, so it
    // doubles as a heartbeat for "when was this business last using the app?"
    // (surfaced on the admin dashboard). Fire-and-forget: never delay or fail the
    // license check on account of it.
    pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`UPDATE businesses SET last_active_at = GETUTCDATE() WHERE id = @business_id`)
      .catch(() => {});

    const request = pool.request();
    request.input('business_id', sql.UniqueIdentifier, req.user.business_id);
    request.input('user_id', sql.UniqueIdentifier, req.user.user_id);

    const result = await request.query(`
      SELECT
        s.status,
        s.expires_at,
        s.max_offline_days,
        s.grace_period_days,
        s.allow_mobile,
        s.allow_desktop,
        s.allow_online_store,
        s.is_trial,
        s.updated_at,
        b.store_enabled,
        -- The caller's role AS IT IS NOW, not as their 8-hour access token
        -- claims. This endpoint is hit on every app open/resume, so it is where
        -- a device finds out its role was changed underneath it.
        (SELECT u.role FROM users u WHERE u.id = @user_id) AS current_role,
        -- COUNT, not the column: a deleted user yields 0 rather than NULL, so
        -- "disabled" and "gone" are the same definite answer and neither can be
        -- mistaken for "unknown".
        (SELECT COUNT(*) FROM users u
          WHERE u.id = @user_id AND u.is_active = 1) AS user_ok
      FROM subscriptions s
      JOIN businesses b ON b.id = s.business_id
      WHERE s.business_id = @business_id
    `);

    if (result.recordset.length === 0) {
      // No subscription row yet — business registered but not activated
      return res.status(403).json({
        error: 'no_subscription',
        message: 'Your subscription is not yet activated. Please contact support.'
      });
    }

    const sub = result.recordset[0];

    // Auto-expire: if expires_at has passed and status is still active, treat as expired
    const now = new Date();
    const expiresAt = new Date(sub.expires_at);
    if (sub.status === 'active' && expiresAt < now) {
      // Update status to expired in DB
      const updateReq = pool.request();
      updateReq.input('business_id', sql.UniqueIdentifier, req.user.business_id);
      await updateReq.query(`
        UPDATE subscriptions
        SET status = 'expired', updated_at = GETUTCDATE()
        WHERE business_id = @business_id
      `);
      sub.status = 'expired';
    }

    return res.json({
      status: sub.status,
      expires_at: sub.expires_at,
      max_offline_days: sub.max_offline_days,
      grace_period_days: sub.grace_period_days,
      allow_mobile: !!sub.allow_mobile,
      allow_desktop: !!sub.allow_desktop,
      // Platform-admin kill switch for the online store (migration 039),
      // separate from the OWNER's own businesses.store_enabled toggle. NULL
      // (no admin decision yet) reads as allowed — matches allow_mobile/
      // allow_desktop's own default-open behaviour.
      allow_online_store: sub.allow_online_store == null ? true : !!sub.allow_online_store,
      // Effective online-store switch = the owner's own toggle AND the admin
      // entitlement. /login sends this too, but only once; this endpoint is hit
      // on every app open/resume, so a change made from the admin dashboard, in
      // the DB, or on another device reaches this device without a re-login.
      store_enabled: !!sub.store_enabled &&
        (sub.allow_online_store == null ? true : !!sub.allow_online_store),
      // Null when the user row is gone (deleted staff) — the client treats
      // any mismatch with its cached role, including null, as "log out".
      current_role: sub.current_role ?? null,
      // False once an owner disables OR deletes the account. A device already
      // holding a valid access token has no other way to learn it was cut off.
      account_active: sub.user_ok > 0,
      is_trial: !!sub.is_trial,
      verified_at: new Date().toISOString()
    });
  } catch (err) {
    return res.status(500).json({ error: 'Server error' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/admin/license/activate
// Admin-only endpoint (protected by ADMIN_SECRET env variable).
// Used by you to activate or update a business subscription.
//
// Body: { business_id, expires_at, max_offline_days, grace_period_days, status }
// ---------------------------------------------------------------------------
router.post('/admin/activate', async (req, res) => {
  const adminSecret = req.headers['x-admin-secret'];
  if (!adminSecret || adminSecret !== process.env.ADMIN_SECRET) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const {
    business_id,
    expires_at,
    max_offline_days = 30,
    grace_period_days = 5,
    status = 'active',
    max_staff = 10,
    allow_mobile = true,
    allow_desktop = true
  } = req.body;

  if (!business_id || !expires_at) {
    return res.status(400).json({ error: 'business_id and expires_at are required' });
  }

  const validStatuses = ['pending', 'active', 'suspended', 'expired'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${validStatuses.join(', ')}` });
  }

  try {
    await poolConnect;
    const request = pool.request();
    request.input('business_id', sql.UniqueIdentifier, business_id);
    request.input('status', sql.NVarChar(20), status);
    request.input('expires_at', sql.DateTime2, new Date(expires_at));
    request.input('max_offline_days', sql.Int, max_offline_days);
    request.input('grace_period_days', sql.Int, grace_period_days);
    request.input('max_staff', sql.Int, max_staff);
    request.input('allow_mobile', sql.Bit, allow_mobile ? 1 : 0);
    request.input('allow_desktop', sql.Bit, allow_desktop ? 1 : 0);

    // Upsert subscription — insert if not exists, update if exists
    await request.query(`
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
          updated_at        = GETUTCDATE()
      WHEN NOT MATCHED THEN
        INSERT (business_id, status, expires_at, max_offline_days, grace_period_days,
                max_staff, allow_mobile, allow_desktop)
        VALUES (@business_id, @status, @expires_at, @max_offline_days, @grace_period_days,
                @max_staff, @allow_mobile, @allow_desktop);
    `);

    // Auto-verify the business when activating subscription
    if (status === 'active') {
      const verifyReq = pool.request();
      verifyReq.input('business_id', sql.UniqueIdentifier, business_id);
      await verifyReq.query(`
        UPDATE businesses SET is_verified = 1 WHERE id = @business_id
      `);
    }

    return res.json({ ok: true, business_id, status, expires_at });
  } catch (err) {
    return res.status(500).json({ error: 'Server error', detail: err.message });
  }
});

module.exports = router;
