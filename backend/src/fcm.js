'use strict';
// Firebase Admin SDK — sends FCM push notifications.
// Initialised lazily so the app still starts if FIREBASE_SERVICE_ACCOUNT is missing.

let _messaging = null;

function getMessaging() {
  if (_messaging) return _messaging;

  const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountRaw) return null;

  try {
    const admin = require('firebase-admin');
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(JSON.parse(serviceAccountRaw)),
      });
    }
    _messaging = admin.messaging();
    return _messaging;
  } catch (err) {
    console.error('[FCM] Failed to initialise Firebase Admin:', err.message);
    return null;
  }
}

/**
 * Send ONE notification covering all items that just crossed below their
 * low-stock threshold in a single bill. Uses multicast so all device tokens
 * are reached in one API call.
 *
 * @param {object} pool
 * @param {object} sql
 * @param {string} businessId
 * @param {Array<{name: string, remaining: number}>} lowItems  — items that crossed threshold
 */
async function sendLowStockNotification(pool, sql, businessId, lowItems) {
  if (!lowItems || lowItems.length === 0) return;

  const messaging = getMessaging();
  if (!messaging) return;

  let tokens;
  try {
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`SELECT token FROM fcm_tokens WHERE business_id = @business_id`);
    tokens = result.recordset.map((r) => r.token);
  } catch (err) {
    console.error('[FCM] Failed to fetch tokens:', err.message);
    return;
  }

  if (tokens.length === 0) return;

  const title = lowItems.length === 1
    ? 'Low Stock Alert'
    : `Low Stock Alert — ${lowItems.length} items`;

  const body = lowItems.length === 1
    ? `${lowItems[0].name} is running low — only ${lowItems[0].remaining} left.`
    : lowItems.map((i) => `${i.name} (${i.remaining} left)`).join(', ');

  const message = {
    notification: { title, body },
    data: {
      type: 'low_stock',
      count: String(lowItems.length),
      items: JSON.stringify(lowItems),
    },
    android: { notification: { channelId: 'low_stock', priority: 'high' } },
    apns: { payload: { aps: { sound: 'default' } } },
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);

    // Remove stale tokens
    const staleTokens = [];
    response.responses.forEach((r, i) => {
      if (!r.success) {
        const code = r.error?.errorInfo?.code;
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token'
        ) {
          staleTokens.push(tokens[i]);
        } else if (r.error) {
          console.error('[FCM] Send error:', r.error.message);
        }
      }
    });

    for (const token of staleTokens) {
      try {
        await pool.request()
          .input('token', sql.NVarChar(500), token)
          .query(`DELETE FROM fcm_tokens WHERE token = @token`);
      } catch (_) {}
    }
  } catch (err) {
    console.error('[FCM] sendEachForMulticast error:', err.message);
  }
}

module.exports = { sendLowStockNotification };
