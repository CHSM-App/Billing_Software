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
  // Disabled: we show no notifications to any role. Low-stock is surfaced in-app
  // (stock screens / badges), not via push. Kept as a no-op so callers don't
  // need to change.
  return;
  // eslint-disable-next-line no-unreachable
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

  // DATA-ONLY, silent message: no `notification` block, no sound, no channel —
  // so nothing is shown to the kitchen (or any) device. The client uses the
  // `type: kitchen_order` data payload solely to refresh the kitchen queue in
  // real time. High priority + content-available so it still wakes the app.
  const message = {
    data: {
      type: 'kitchen_order',
      is_new: String(!!order.isNew),
      table: order.tableLabel || '',
    },
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '5' },
      payload: { aps: { 'content-available': 1 } },
    },
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

/**
 * Silently notify ALL of a business's devices that a dish's kitchen status
 * changed, so any open Kitchen view (cashier, server, or chef) refreshes in real
 * time. Data-only — nothing is shown. Reuses the `kitchen_order` type the client
 * already listens for (it just bumps the refresh signal).
 *
 * @param {object} pool
 * @param {object} sql
 * @param {string} businessId
 */
async function sendKitchenStatusChanged(pool, sql, businessId) {
  const messaging = getMessaging();
  if (!messaging) return;

  let tokens;
  try {
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`SELECT token FROM fcm_tokens WHERE business_id = @business_id`);
    tokens = result.recordset.map((r) => r.token);
  } catch (err) {
    console.error('[FCM] Failed to fetch tokens (status change):', err.message);
    return;
  }
  if (tokens.length === 0) return;

  const message = {
    data: { type: 'kitchen_order', is_new: 'false', table: '' },
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '5' },
      payload: { aps: { 'content-available': 1 } },
    },
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
    console.error('[FCM] status-change multicast error:', err.message);
  }
}

/**
 * Notify the shop that an online-store order is waiting for a decision.
 *
 * This is the ONE VISIBLE notification the product sends. Everything else in
 * this file is a silent data ping on purpose (see sendKitchenNotification), but
 * an online order arrives with nobody looking at the app — a silent refresh of a
 * screen that is not open is an order the shop loses. So this one carries a real
 * `notification` block, its own channel and a sound.
 *
 * Targets owners and cashiers only: they are the roles allowed to accept or
 * reject (see routes/online_orders.js), so pinging a server or the kitchen would
 * be noise they can do nothing about.
 *
 * @param {object} pool
 * @param {object} sql
 * @param {string} businessId
 * @param {{ orderNumber: string, customerName?: string|null, total: number,
 *           itemCount: number }} order
 */
async function sendOnlineOrderNotification(pool, sql, businessId, order = {}) {
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
        WHERE ft.business_id = @business_id AND u.role IN ('owner', 'cashier')
      `);
    tokens = result.recordset.map((r) => r.token);
  } catch (err) {
    console.error('[FCM] Failed to fetch online-order tokens:', err.message);
    return;
  }

  if (tokens.length === 0) return;

  const parts = [
    `${order.itemCount} item${order.itemCount === 1 ? '' : 's'}`,
    `Rs.${order.total}`,
  ];
  if (order.customerName) parts.push(order.customerName);

  const message = {
    notification: {
      title: `New online order ${order.orderNumber || ''}`.trim(),
      body: parts.join(' · '),
    },
    data: {
      type: 'online_order',
      order_number: order.orderNumber || '',
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'online_orders',
        priority: 'high',
        sound: 'default',
        // Pairs with the FLUTTER_NOTIFICATION_CLICK intent-filter in the app's
        // AndroidManifest: it is what makes a TAP open the app on the order
        // queue instead of wherever the user last was.
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
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
          console.error('[FCM] Online order send error:', r.error.message);
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
    console.error('[FCM] online order multicast error:', err.message);
  }
}

module.exports = {
  sendLowStockNotification,
  sendKitchenNotification,
  sendKitchenStatusChanged,
  sendOnlineOrderNotification,
};
