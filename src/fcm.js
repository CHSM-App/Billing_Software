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
 * Low-stock alert for owners. Called only when a bill moves items ACROSS their
 * threshold (see collectLowStock in routes/bills.js), never for every sale of an
 * already-low item.
 *
 * Anti-spam: the title carries the business's TOTAL low-stock count and the
 * message is tagged, so each send REPLACES the previous low-stock notification
 * instead of stacking — the tray holds one "Low stock — N items" at most.
 * Quiet (no sound): stock running low is not urgent the way an order is.
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
      .query(`
        SELECT ft.token
        FROM fcm_tokens ft
        JOIN users u ON u.id = ft.user_id
        WHERE ft.business_id = @business_id AND u.role = 'owner'
          AND u.notify_low_stock = 1
      `);
    tokens = result.recordset.map((r) => r.token);
  } catch (err) {
    console.error('[FCM] Failed to fetch tokens:', err.message);
    return;
  }

  if (tokens.length === 0) return;

  // Everything low right now, not just this bill's — the notification replaces
  // the last one, so it has to carry the running total.
  let lowCount = lowItems.length;
  try {
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`
        SELECT
          (SELECT COUNT(*) FROM item_variants v JOIN items i ON i.id = v.item_id
           WHERE i.business_id = @business_id AND i.is_active = 1 AND v.is_active = 1
             AND v.stock_quantity <= v.low_stock_threshold)
        + (SELECT COUNT(*) FROM items i
           WHERE i.business_id = @business_id AND i.is_active = 1
             AND i.stock_quantity <= i.low_stock_threshold
             AND NOT EXISTS (SELECT 1 FROM item_variants v
                             WHERE v.item_id = i.id AND v.is_active = 1)) AS low_count
      `);
    lowCount = Math.max(lowCount, Number(result.recordset[0]?.low_count) || 0);
  } catch (err) {
    console.error('[FCM] Failed to count low-stock items:', err.message);
  }

  const { title, body } = lowStockText(lowItems, lowCount);

  const message = {
    notification: { title, body },
    data: { type: 'low_stock', count: String(lowCount) },
    android: {
      notification: {
        channelId: 'low_stock',
        // Same tag = replaces the previous low-stock notification.
        tag: 'low_stock',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
    apns: { headers: { 'apns-collapse-id': 'low_stock' } },
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

/** Title shows the business-wide count; body names (up to 3 of) the items
 *  that just crossed. */
function lowStockText(lowItems, lowCount) {
  const title = lowCount === 1 ? 'Low stock' : `Low stock — ${lowCount} items`;
  const shown = lowItems.slice(0, 3).map((i) => `${i.name} (${i.remaining} left)`);
  const more = lowItems.length - shown.length;
  return { title, body: shown.join(', ') + (more > 0 ? ` …and ${more} more` : '') };
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
 * One of the two VISIBLE notifications the product sends (low stock is the
 * other, and that one is quiet). The kitchen pings are silent data on purpose
 * (see sendKitchenNotification), but
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
          AND u.notify_online_orders = 1
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

/**
 * A customer at a table sent dishes to the kitchen from the QR menu.
 *
 * The QR flow only ever pushed a WebSocket event, which reaches a device whose
 * app is open and holding a live socket — and no further. Backgrounded, the OS
 * suspends that socket, so an order placed while the counter phone was locked
 * arrived nowhere until someone opened the app. This is the wake-up, the same
 * way an online order gets one.
 *
 * Visible (a real `notification` block) and aimed at owners and cashiers, who
 * work the counter. The kitchen gets its own silent data ping instead — see
 * sendKitchenNotification — because its screen is already open in front of it.
 *
 * @param {object} pool
 * @param {object} sql
 * @param {string} businessId
 * @param {{ tableLabel: string, dinerName?: string|null, total: number,
 *           itemCount: number }} order
 */
async function sendTableOrderNotification(pool, sql, businessId, order = {}) {
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
          AND u.notify_online_orders = 1
      `);
    tokens = result.recordset.map((r) => r.token);
  } catch (err) {
    console.error('[FCM] Failed to fetch table-order tokens:', err.message);
    return;
  }
  if (tokens.length === 0) return;

  const parts = [
    `${order.itemCount} item${order.itemCount === 1 ? '' : 's'}`,
    `Rs.${order.total}`,
  ];
  if (order.dinerName) parts.push(order.dinerName);

  const message = {
    notification: {
      title: order.tableLabel ? `New order — ${order.tableLabel}` : 'New table order',
      body: parts.join(' · '),
    },
    // Distinct type so the app can refresh the TABLES view rather than the
    // online-order queue, which has nothing to do with this order.
    data: { type: 'table_order', table: order.tableLabel || '' },
    android: {
      priority: 'high',
      notification: {
        // Shares the orders channel: to a shop owner these are the same class
        // of alert, and a second channel would be a second thing to mute.
        channelId: 'online_orders',
        priority: 'high',
        sound: 'default',
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
          console.error('[FCM] Table order send error:', r.error.message);
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
    console.error('[FCM] table order multicast error:', err.message);
  }
}

/**
 * Tell every owner that a bill was voided, and by whom. A cashier can void
 * today's bills without asking (routes/bills.js DELETE), so this is what keeps
 * "take the cash, void the bill" visible to the person whose money it is.
 * Never awaited by the caller; never throws.
 *
 * @param {{ billNumber: string, total: number, voidedByUserId: string }} info
 */
async function sendBillVoidedNotification(pool, sql, businessId, info = {}) {
  const messaging = getMessaging();
  if (!messaging) return;

  let tokens;
  let byName = '';
  try {
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('user_id', sql.UniqueIdentifier, info.voidedByUserId || null)
      .query(`
        SELECT ft.token,
               (SELECT name FROM users WHERE id = @user_id) AS by_name
        FROM fcm_tokens ft
        JOIN users u ON u.id = ft.user_id
        WHERE ft.business_id = @business_id AND u.role = 'owner'
          AND ft.user_id <> ISNULL(@user_id, '00000000-0000-0000-0000-000000000000')
      `);
    tokens = result.recordset.map((r) => r.token);
    byName = result.recordset[0]?.by_name || '';
  } catch (err) {
    console.error('[FCM] Failed to fetch tokens:', err.message);
    return;
  }
  if (tokens.length === 0) return;

  const amount = Number(info.total || 0).toFixed(2);
  const message = {
    notification: {
      title: `Bill ${info.billNumber || ''} voided`.replace(/\s+/g, ' ').trim(),
      body: `Rs.${amount}${byName ? ` · by ${byName}` : ''}`,
    },
    data: { type: 'bill_voided' },
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    for (let i = 0; i < response.responses.length; i++) {
      const code = response.responses[i].error?.errorInfo?.code;
      if (code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token') {
        await pool.request()
          .input('token', sql.NVarChar(500), tokens[i])
          .query(`DELETE FROM fcm_tokens WHERE token = @token`)
          .catch(() => {});
      }
    }
  } catch (err) {
    console.error('[FCM] sendEachForMulticast error:', err.message);
  }
}

module.exports = {
  sendBillVoidedNotification,
  sendLowStockNotification,
  lowStockText,
  sendKitchenNotification,
  sendKitchenStatusChanged,
  sendOnlineOrderNotification,
  sendTableOrderNotification,
};
