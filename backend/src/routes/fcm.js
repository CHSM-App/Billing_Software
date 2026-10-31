const { Router } = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');

const router = Router();

// POST /api/fcm/token  — register or refresh a device FCM token
router.post('/token', requireAuth, async (req, res) => {
  const { token } = req.body;
  if (!token || typeof token !== 'string') {
    return res.status(400).json({ error: 'token is required' });
  }

  try {
    await poolConnect;
    // Upsert: if token already exists update its user/business, else insert
    await pool.request()
      .input('token',       sql.NVarChar(500),      token)
      .input('user_id',     sql.UniqueIdentifier,   req.user.user_id)
      .input('business_id', sql.UniqueIdentifier,   req.user.business_id)
      .query(`
        MERGE fcm_tokens AS target
        USING (SELECT @token AS token) AS source
          ON target.token = source.token
        WHEN MATCHED THEN
          UPDATE SET user_id = @user_id, business_id = @business_id, created_at = GETUTCDATE()
        WHEN NOT MATCHED THEN
          INSERT (token, user_id, business_id)
          VALUES (@token, @user_id, @business_id);
      `);
    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'FCM token upsert error');
    return res.status(500).json({ error: 'Failed to save token' });
  }
});

// POST /api/fcm/token/remove  — remove a token on logout
router.post('/token/remove', requireAuth, async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'token is required' });

  try {
    await poolConnect;
    await pool.request()
      .input('token',       sql.NVarChar(500),    token)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`DELETE FROM fcm_tokens WHERE token = @token AND business_id = @business_id`);
    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'FCM token delete error');
    return res.status(500).json({ error: 'Failed to remove token' });
  }
});

// Per-person notification switches (migration 067). Each user only ever reads
// and writes their own row.
const PREF_KEYS = ['notify_low_stock', 'notify_online_orders'];

// GET /api/fcm/prefs
router.get('/prefs', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.user.user_id)
      .query(`SELECT notify_low_stock, notify_online_orders FROM users WHERE id = @id`);
    const row = result.recordset[0];
    if (!row) return res.status(404).json({ error: 'User not found' });
    return res.json({
      notify_low_stock: !!row.notify_low_stock,
      notify_online_orders: !!row.notify_online_orders,
    });
  } catch (err) {
    logger.error({ err }, 'FCM prefs read error');
    return res.status(500).json({ error: 'Failed to load notification settings' });
  }
});

// PUT /api/fcm/prefs  — { notify_low_stock?: bool, notify_online_orders?: bool }
router.put('/prefs', requireAuth, async (req, res) => {
  const fields = PREF_KEYS.filter((k) => req.body?.[k] !== undefined);
  if (fields.length === 0) return res.status(400).json({ error: 'No settings to update' });
  if (fields.some((k) => typeof req.body[k] !== 'boolean')) {
    return res.status(400).json({ error: 'Settings must be true or false' });
  }

  try {
    await poolConnect;
    const r = pool.request().input('id', sql.UniqueIdentifier, req.user.user_id);
    fields.forEach((k) => r.input(k, sql.Bit, req.body[k] ? 1 : 0));
    await r.query(`UPDATE users SET ${fields.map((k) => `${k} = @${k}`).join(', ')} WHERE id = @id`);
    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'FCM prefs update error');
    return res.status(500).json({ error: 'Failed to save notification settings' });
  }
});

module.exports = router;
