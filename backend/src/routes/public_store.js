'use strict';
// =============================================================================
// Public online store.  Mounted at /store — NO staff auth.
//
// One shareable link per business (businesses.store_token), unlike the per-table
// QR flow in public_order.js:
//
//   GET  /store/:token               -> customer shop page (no app)
//   GET  /store/:token/menu          -> JSON catalog + the shop's store settings
//   GET  /store/:token/orders        -> this customer's recent orders + status
//   POST /store/:token/send-otp      -> WhatsApp OTP to verify the phone
//   POST /store/:token/verify-otp    -> returns a short-lived STORE TOKEN
//   POST /store/:token               -> place an order (needs the store token)
//
// A placed order does NOT become a bill. It lands in online_orders as 'pending'
// and the shop accepts or rejects it from the app (routes/online_orders.js).
// A table diner is standing in front of the staff; an internet customer is not,
// and must not be able to write rows into a shop's books unattended.
//
// Security notes:
//   * store_token is long + random — the link cannot be guessed or edited into
//     another shop's store.
//   * prices are ALWAYS recomputed server-side (see menuPricing.js). The
//     delivery charge comes from the business row, never from the request.
//   * payment is out-of-band: the customer scans the shop's own UPI QR and types
//     the transaction reference. We cannot verify it, so it is recorded as
//     'claimed' and the owner confirms it when accepting.
// =============================================================================

const express = require('express');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const path = require('path');
const fs = require('fs');
const { pool, poolConnect, sql } = require('../db');
const logger = require('../logger');
const { broadcast } = require('../realtime');
const { sendOtp, verifyOtp, normalisePhone } = require('../whatsapp');
const { cleanLines, priceLines } = require('../menuPricing');
const { sendOnlineOrderNotification } = require('../fcm');

const router = express.Router();

// The customer shop page, shipped with the code (survives CI deploys).
const STORE_PAGE_PATH = path.join(__dirname, '..', 'static', 'store', 'index.html');
// Log at boot whether the page is present + its size, so a bad deploy is obvious
// in the logs instead of surfacing as a mysterious 404 per request.
try {
  const st = fs.statSync(STORE_PAGE_PATH);
  logger.info({ path: STORE_PAGE_PATH, bytes: st.size }, 'store page shell found');
} catch (e) {
  logger.error({ path: STORE_PAGE_PATH, err: e.message }, 'store page shell MISSING at boot');
}

const STORE_SECRET = process.env.JWT_ACCESS_SECRET;
const STORE_TOKEN_TTL = '4h';
// A verified number may keep at most this many orders waiting on the shop, so a
// single customer cannot bury the owner's queue.
const MAX_PENDING_PER_PHONE = 3;
const MAX_ADDRESS_LEN = 500;
const MAX_NOTE_LEN = 500;
const MAX_TXN_LEN = 64;

// A brisk limiter so a shared link can't be used to hammer the endpoints.
const storeLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please slow down.' },
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const round2 = (n) => +(Number(n) || 0).toFixed(2);

// Resolve a store_token to its business, only when the store is switched on.
// Returns null when the token is unknown or the shop has the feature disabled.
async function resolveStore(storeToken) {
  await poolConnect;
  const result = await pool.request()
    .input('store_token', sql.NVarChar(32), storeToken)
    .query(`
      SELECT id AS business_id, name AS shop_name, address, phone, logo_url,
             store_enabled, store_delivery_enabled,
             store_delivery_charge, store_payment_qr_url, store_upi_id,
             store_advance_percent, store_payment_required
      FROM businesses
      WHERE store_token = @store_token
    `);
  if (result.recordset.length === 0) return null;
  const row = result.recordset[0];
  if (!row.store_enabled) return null;
  return row;
}

function signStoreToken({ phone, businessId }) {
  return jwt.sign(
    { typ: 'store', phone, business_id: businessId },
    STORE_SECRET,
    { expiresIn: STORE_TOKEN_TTL },
  );
}

// Verify a store token and confirm it was minted for THIS shop.
function verifyStoreToken(token, businessId) {
  try {
    const p = jwt.verify(token || '', STORE_SECRET);
    if (p.typ !== 'store' || p.business_id !== businessId) return null;
    return p;
  } catch (_) {
    return null;
  }
}

function readBearer(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

// The store config the customer page needs to render checkout. Deliberately
// narrow: no internal ids, no anything the page does not draw.
//
// Pickup is not in here because it is never off — every store lets a customer
// walk in and collect. Only `delivery_enabled` varies, and it is what decides
// whether checkout shows a choice or just tells them to collect.
function storeConfig(store) {
  return {
    delivery_enabled: !!store.store_delivery_enabled,
    delivery_charge: Number(store.store_delivery_charge) || 0,
    payment_qr_url: store.store_payment_qr_url || null,
    // The VPA, so checkout can build a upi:// intent with the amount already
    // in it. Public by design — a VPA is what a shop prints on its counter QR.
    upi_id: store.store_upi_id || null,
    advance_percent: Number(store.store_advance_percent) || 0,
    payment_required: !!store.store_payment_required,
  };
}

// SQL Server raises 2627 / 2601 when the (business_id, order_number) unique
// constraint collides — two customers submitting in the same instant.
function isDuplicateKeyError(err) {
  return err && (err.number === 2627 || err.number === 2601);
}

// ---------------------------------------------------------------------------
// GET /store/:token  — serve the customer shop page (static HTML shell)
// ---------------------------------------------------------------------------
router.get('/:token', storeLimiter, async (req, res) => {
  try {
    const store = await resolveStore(req.params.token);
    if (!store) {
      return res
        .status(404)
        .send('<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;text-align:center;padding:3rem"><h2>Store not available</h2><p>This link is invalid, or online ordering is turned off for this shop.</p></body>');
    }
    // Read + send the bytes ourselves instead of res.sendFile: under iisnode,
    // sendFile's internal `send` can 404 on a file that exists (path/stat quirks
    // via the named-pipe FS), and it swallows the real error.
    return fs.readFile(STORE_PAGE_PATH, (err, buf) => {
      if (err) {
        logger.error({ err, path: STORE_PAGE_PATH }, 'Store page file read failed');
        return res.status(500).send('Store page is temporarily unavailable.');
      }
      res.set('Content-Type', 'text/html; charset=utf-8');
      res.set('Cache-Control', 'no-cache');
      return res.send(buf);
    });
  } catch (err) {
    logger.error({ err }, 'Serve store page error');
    return res.status(500).send('Something went wrong.');
  }
});

// ---------------------------------------------------------------------------
// GET /store/:token/menu  — catalog + store settings
// ---------------------------------------------------------------------------
router.get('/:token/menu', storeLimiter, async (req, res) => {
  try {
    const store = await resolveStore(req.params.token);
    if (!store) return res.status(404).json({ error: 'Store not available' });

    const itemsResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, store.business_id)
      .query(`
        SELECT id, name, major_category, category, price, tax_rate, image_url
        FROM items
        WHERE business_id = @business_id AND is_active = 1
        ORDER BY major_category ASC, category ASC, name ASC
      `);

    const items = itemsResult.recordset;
    if (items.length > 0) {
      const ids = items.map((_, i) => `@p${i}`);
      const vReq = pool.request();
      items.forEach((it, i) => vReq.input(`p${i}`, sql.UniqueIdentifier, it.id));
      const vResult = await vReq.query(`
        SELECT id, item_id, label, price, sort_order
        FROM item_variants
        WHERE item_id IN (${ids.join(',')}) AND is_active = 1
        ORDER BY sort_order ASC, label ASC
      `);
      const byItem = {};
      for (const v of vResult.recordset) (byItem[v.item_id] ||= []).push(v);
      for (const it of items) it.variants = byItem[it.id] || [];
    }

    return res.json({
      shop_name: store.shop_name,
      shop_logo: store.logo_url || null,
      shop_address: store.address || null,
      shop_phone: store.phone || null,
      store: storeConfig(store),
      items,
    });
  } catch (err) {
    logger.error({ err }, 'Get store menu error');
    return res.status(500).json({ error: 'Failed to load the store' });
  }
});

// ---------------------------------------------------------------------------
// GET /store/:token/orders  — this customer's recent orders and their status
// Requires the store token, and is scoped to that token's verified phone, so a
// customer can only ever read their own orders.
// ---------------------------------------------------------------------------
router.get('/:token/orders', storeLimiter, async (req, res) => {
  try {
    const store = await resolveStore(req.params.token);
    if (!store) return res.status(404).json({ error: 'Store not available' });

    const payload = verifyStoreToken(readBearer(req), store.business_id);
    if (!payload) return res.json({ verified: false, orders: [] });

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, store.business_id)
      .input('phone', sql.NVarChar(20), payload.phone)
      .query(`
        SELECT TOP 10 id, order_number, status, reject_reason, fulfilment,
               subtotal, delivery_charge, total, amount_due, paid_amount,
               payment_status, created_at
        FROM online_orders
        WHERE business_id = @business_id AND customer_phone = @phone
        ORDER BY created_at DESC
      `);

    const orders = result.recordset;
    if (orders.length > 0) {
      const ids = orders.map((_, i) => `@o${i}`);
      const iReq = pool.request();
      orders.forEach((o, i) => iReq.input(`o${i}`, sql.UniqueIdentifier, o.id));
      const iResult = await iReq.query(`
        SELECT order_id, item_name, quantity, line_total
        FROM online_order_items
        WHERE order_id IN (${ids.join(',')})
      `);
      const byOrder = {};
      for (const it of iResult.recordset) (byOrder[it.order_id] ||= []).push(it);
      for (const o of orders) o.items = byOrder[o.id] || [];
    }

    return res.json({ verified: true, orders });
  } catch (err) {
    logger.error({ err }, 'Get store orders error');
    return res.status(500).json({ error: 'Failed to load your orders' });
  }
});

// ---------------------------------------------------------------------------
// POST /store/:token/send-otp  — { phone }
// ---------------------------------------------------------------------------
router.post('/:token/send-otp', storeLimiter, async (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ error: 'phone is required' });
  try {
    const store = await resolveStore(req.params.token);
    if (!store) return res.status(404).json({ error: 'Store not available' });

    // Reuses purpose 'order' — the same customer-ordering OTP as the table flow,
    // so no new purpose value (and no CHECK-constraint migration) is needed.
    const result = await sendOtp(phone, 'order');
    return res.json({
      message: 'OTP sent.',
      ...(result.dev_otp ? { dev_otp: result.dev_otp } : {}),
    });
  } catch (err) {
    logger.error({ err }, 'Store send-otp error');
    return res.status(500).json({ error: err.message || 'Failed to send OTP' });
  }
});

// ---------------------------------------------------------------------------
// POST /store/:token/verify-otp  — { phone, otp } -> store token
// ---------------------------------------------------------------------------
router.post('/:token/verify-otp', storeLimiter, async (req, res) => {
  const { phone, otp } = req.body || {};
  if (!phone || !otp) return res.status(400).json({ error: 'phone and otp are required' });
  try {
    const store = await resolveStore(req.params.token);
    if (!store) return res.status(404).json({ error: 'Store not available' });

    const ok = await verifyOtp(phone, otp, 'order');
    if (!ok) return res.status(401).json({ error: 'Invalid or expired OTP' });

    return res.json({
      store_token: signStoreToken({
        phone: normalisePhone(phone),
        businessId: store.business_id,
      }),
    });
  } catch (err) {
    logger.error({ err }, 'Store verify-otp error');
    return res.status(500).json({ error: 'Failed to verify OTP' });
  }
});

// ---------------------------------------------------------------------------
// POST /store/:token  — place an order (needs a valid store token)
// body: { items: [{ item_id, variant_id?, quantity }], name?, fulfilment,
//         address?, note?, payment_txn_id? }
// ---------------------------------------------------------------------------
router.post('/:token', storeLimiter, async (req, res) => {
  const { items, name, fulfilment, address, note, payment_txn_id,
          payment_choice } = req.body || {};

  const { lines: cleaned, error: lineError } = cleanLines(items);
  if (lineError) return res.status(400).json({ error: lineError });

  let store;
  try {
    store = await resolveStore(req.params.token);
  } catch (err) {
    logger.error({ err }, 'Place store order resolve error');
    return res.status(500).json({ error: 'Failed to place order' });
  }
  if (!store) return res.status(404).json({ error: 'Store not available' });

  const payload = verifyStoreToken(readBearer(req), store.business_id);
  if (!payload) {
    return res.status(401).json({ error: 'Please verify your phone number again.' });
  }

  // --- fulfilment ------------------------------------------------------------
  // Pickup always passes. Delivery is the only one a shop can turn off, and the
  // check has to live here as well as in the page: the page is a browser and a
  // browser can post whatever it likes.
  const cfg = storeConfig(store);
  if (fulfilment !== 'pickup' && fulfilment !== 'delivery') {
    return res.status(400).json({ error: 'Choose pickup or delivery' });
  }
  if (fulfilment === 'delivery' && !cfg.delivery_enabled) {
    return res.status(400).json({
      code: 'delivery_unavailable',
      error: 'This shop does not deliver — please choose pickup.',
    });
  }

  const cleanAddress = typeof address === 'string' ? address.trim() : '';
  if (fulfilment === 'delivery' && !cleanAddress) {
    return res.status(400).json({ error: 'A delivery address is required' });
  }
  if (cleanAddress.length > MAX_ADDRESS_LEN) {
    return res.status(400).json({ error: 'Delivery address is too long' });
  }
  const cleanNote = (typeof note === 'string' ? note.trim() : '').slice(0, MAX_NOTE_LEN);
  const txnId = (typeof payment_txn_id === 'string' ? payment_txn_id.trim() : '')
    .slice(0, MAX_TXN_LEN);

  // pool.transaction(), matching routes/bills.js — the same handle the rest of
  // the codebase uses for a multi-statement write.
  const transaction = pool.transaction();
  let started = false;
  try {
    await poolConnect;

    // Queue guard before doing any work: a verified number may only have
    // MAX_PENDING_PER_PHONE orders waiting on the shop at once.
    const pendingRes = await pool.request()
      .input('business_id', sql.UniqueIdentifier, store.business_id)
      .input('phone', sql.NVarChar(20), payload.phone)
      .query(`
        SELECT COUNT(*) AS cnt
        FROM online_orders
        WHERE business_id = @business_id AND customer_phone = @phone AND status = 'pending'
      `);
    if ((pendingRes.recordset[0].cnt || 0) >= MAX_PENDING_PER_PHONE) {
      return res.status(429).json({
        code: 'too_many_pending',
        error: 'You already have orders waiting for the shop to confirm.',
      });
    }

    await transaction.begin();
    started = true;

    // The browser's prices are never trusted — re-price from the live catalog.
    const priced = await priceLines(
      () => transaction.request(),
      store.business_id,
      cleaned,
    );

    // Money. The delivery charge comes from the business row, NOT the request.
    const subtotal = round2(priced.reduce((s, l) => s + l.line_total, 0));
    const deliveryCharge = fulfilment === 'delivery' ? round2(cfg.delivery_charge) : 0;
    const total = round2(subtotal + deliveryCharge);
    // What the shop REQUIRES up front. Stays the advance whatever the customer
    // chooses to pay, so "did they meet the shop's condition?" has one answer.
    const amountDue = round2((total * cfg.advance_percent) / 100);

    // Payment. We cannot verify a typed UPI reference, so its presence only
    // moves the order to 'claimed'; the owner confirms it when accepting.
    if (cfg.payment_required && amountDue > 0 && !txnId) {
      throw {
        httpStatus: 400,
        code: 'payment_required',
        message: 'This shop needs the payment reference before confirming the order.',
      };
    }

    // A customer may settle the whole bill now instead of just the advance. The
    // request sends the CHOICE, never the figure — both amounts are re-derived
    // here, so a browser cannot claim to have paid an amount of its own
    // invention. Only offered when the shop actually collects online at all.
    const payFull = payment_choice === 'full' && amountDue > 0;
    const claimed = payFull ? total : amountDue;

    const paymentStatus = txnId ? 'claimed' : 'unpaid';
    const paidAmount = txnId ? claimed : 0;

    // Order number: ORD-#### in its own per-business series, so a rejected
    // order never burns a bill number.
    // ponytail: COUNT+1 races under simultaneous checkout exactly as the bill
    // numbering does; the unique index catches it and the customer retries.
    // Swap to a per-business counter table if that retry is ever seen in logs.
    const numRes = await transaction.request()
      .input('business_id', sql.UniqueIdentifier, store.business_id)
      .query(`SELECT COUNT(*) AS cnt FROM online_orders WHERE business_id = @business_id`);
    const orderNumber = 'ORD-' + String(numRes.recordset[0].cnt + 1).padStart(4, '0');

    const createRes = await transaction.request()
      .input('business_id', sql.UniqueIdentifier, store.business_id)
      .input('order_number', sql.NVarChar(50), orderNumber)
      .input('customer_name', sql.NVarChar(200), (name || '').trim() || null)
      .input('customer_phone', sql.NVarChar(20), payload.phone)
      .input('fulfilment', sql.NVarChar(20), fulfilment)
      .input('address', sql.NVarChar(500), cleanAddress || null)
      .input('note', sql.NVarChar(500), cleanNote || null)
      .input('subtotal', sql.Decimal(10, 2), subtotal)
      .input('delivery_charge', sql.Decimal(10, 2), deliveryCharge)
      .input('total', sql.Decimal(10, 2), total)
      .input('amount_due', sql.Decimal(10, 2), amountDue)
      .input('paid_amount', sql.Decimal(10, 2), paidAmount)
      .input('payment_txn_id', sql.NVarChar(64), txnId || null)
      .input('payment_status', sql.NVarChar(20), paymentStatus)
      .query(`
        INSERT INTO online_orders (business_id, order_number, customer_name, customer_phone,
                                   fulfilment, address, note, subtotal, delivery_charge, total,
                                   amount_due, paid_amount, payment_txn_id, payment_status, status)
        OUTPUT INSERTED.id, INSERTED.order_number
        VALUES (@business_id, @order_number, @customer_name, @customer_phone,
                @fulfilment, @address, @note, @subtotal, @delivery_charge, @total,
                @amount_due, @paid_amount, @payment_txn_id, @payment_status, 'pending')
      `);
    const order = createRes.recordset[0];

    for (const l of priced) {
      await transaction.request()
        .input('order_id', sql.UniqueIdentifier, order.id)
        .input('item_id', sql.UniqueIdentifier, l.item_id)
        .input('variant_id', sql.UniqueIdentifier, l.variant_id)
        .input('item_name', sql.NVarChar(200), l.item_name)
        .input('quantity', sql.Decimal(10, 2), l.quantity)
        .input('unit_price', sql.Decimal(12, 4), l.unit_price)
        .input('tax_rate', sql.Decimal(5, 2), l.tax_rate)
        .input('line_total', sql.Decimal(10, 2), l.line_total)
        .query(`
          INSERT INTO online_order_items (order_id, item_id, variant_id, item_name,
                                          quantity, unit_price, tax_rate, line_total)
          VALUES (@order_id, @item_id, @variant_id, @item_name,
                  @quantity, @unit_price, @tax_rate, @line_total)
        `);
    }

    await transaction.commit();

    // Tell the shop. The WS ping refreshes any open queue screen; the push is
    // the ONE visible notification this product sends, because an order nobody
    // notices is an order the shop loses.
    broadcast(store.business_id, { type: 'store' });
    sendOnlineOrderNotification(pool, sql, store.business_id, {
      orderNumber: order.order_number,
      customerName: (name || '').trim() || null,
      total,
      itemCount: priced.length,
    }).catch((err) => logger.error({ err }, 'Online order push failed'));

    return res.status(201).json({
      success: true,
      order_number: order.order_number,
      total,
      amount_due: amountDue,
      paid_amount: paidAmount,
    });
  } catch (err) {
    if (started) { try { await transaction.rollback(); } catch (_) {} }
    if (err && err.httpStatus) {
      return res.status(err.httpStatus).json({
        error: err.message,
        ...(err.code ? { code: err.code } : {}),
      });
    }
    if (isDuplicateKeyError(err)) {
      return res.status(409).json({
        code: 'order_number_clash',
        error: 'Someone ordered at the same moment. Please tap Place Order again.',
      });
    }
    logger.error({ err }, 'Place store order error');
    return res.status(500).json({ error: 'Failed to place order' });
  }
});

module.exports = router;
