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

/**
 * Notify the kitchen chef(s) that a new order arrived or items were added.
 * Targets only fcm_tokens belonging to users with the 'kitchen' role in this
 * business, so waiters/owners are not pinged for every order.
 *
 * @param {object} pool
 * @param {object} sql
 * @param {string} businessId
 * @param {{ tableLabel?: string, itemCount?: number, isNew?: boolean }} order
 */
async function sendKitchenNotification(pool, sql, businessId, order = {}) {
  const messaging = getMessaging();
  if (!messaging) return;

  let tokens;
  try {
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`
        SELECT ft.token
        FROM fcm_tokens ft
        JOIN users u ON u.id = ft.user_id
        WHERE ft.business_id = @business_id AND u.role = 'kitchen'
      `);
    tokens = result.recordset.map((r) => r.token);
  } catch (err) {
    console.error('[FCM] Failed to fetch kitchen tokens:', err.message);
    return;
  }

  if (tokens.length === 0) return;

  const where = order.tableLabel ? ` — ${order.tableLabel}` : '';
  const title = order.isNew ? `New order${where}` : `Order updated${where}`;
  const body = order.itemCount
    ? `${order.itemCount} item${order.itemCount === 1 ? '' : 's'} to prepare`
    : 'Open the kitchen view to see the order';

  const message = {
    notification: { title, body },
    data: {
      type: 'kitchen_order',
      is_new: String(!!order.isNew),
      table: order.tableLabel || '',
    },
    android: { notification: { channelId: 'kitchen', priority: 'high' } },
    apns: { payload: { aps: { sound: 'default' } } },
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
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
          console.error('[FCM] Kitchen send error:', r.error.message);
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
    console.error('[FCM] kitchen sendEachForMulticast error:', err.message);
  }
}

module.exports = { sendLowStockNotification, sendKitchenNotification };
