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

module.exports = router;
