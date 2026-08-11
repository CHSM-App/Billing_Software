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
    const request = pool.request();
    request.input('business_id', sql.UniqueIdentifier, req.user.business_id);

    const result = await request.query(`
      SELECT
        status,
        expires_at,
        max_offline_days,
        grace_period_days,
        allow_mobile,
        allow_desktop,
        updated_at
      FROM subscriptions
      WHERE business_id = @business_id
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
