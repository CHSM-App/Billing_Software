'use strict';
// =============================================================================
// Public customer self-ordering by table QR code.  Mounted at /order — NO staff
// auth.  A permanent QR sticker on each table encodes an unguessable qr_token.
//
//   GET  /order/:qrToken               -> customer menu HTML page (no app)
//   GET  /order/:qrToken/menu          -> JSON menu (items + variants + images)
//   GET  /order/:qrToken/current       -> the diner's running order on this table
//   POST /order/:qrToken/send-otp      -> WhatsApp OTP to verify the phone
//   POST /order/:qrToken/verify-otp    -> returns a short-lived ORDER TOKEN
//   POST /order/:qrToken               -> place an order (needs order token)
//
// Identity: the OTP-verified phone is the diner. verify-otp returns a JWT
// (typ:'order') bound to phone+table+business, valid for the length of a meal.
// Re-scanning reuses that token, so "add more items" needs no second OTP until
// it expires or the bill is paid.  Orders merge onto the table's one open draft.
//
// Security notes:
//   * qr_token is long + random, so a customer cannot edit the URL to reach
//     another table.
//   * prices are ALWAYS recomputed server-side from items/item_variants — the
//     client price is never trusted.
//   * item images are exposed here ONLY (never on the staff /api/items route).
//   * geolocation gate is provisioned in the schema but intentionally NOT
//     enforced yet.
// =============================================================================

const express = require('express');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const path = require('path');
const fs = require('fs');
const { pool, poolConnect, sql } = require('../db');
const logger = require('../logger');
const { broadcast } = require('../realtime');
const { sendOtp, verifyOtp, normalisePhone } = require('../whatsapp');

const router = express.Router();

// The customer menu HTML shell, shipped with the code (survives CI deploys).
const ORDER_PAGE_PATH = path.join(__dirname, '..', 'static', 'order', 'index.html');
// Log at boot whether the page is present + its size, so a bad deploy is obvious
// in the logs instead of surfacing as a mysterious 404 per request.
try {
  const st = fs.statSync(ORDER_PAGE_PATH);
  logger.info({ path: ORDER_PAGE_PATH, bytes: st.size }, 'order page shell found');
} catch (e) {
  logger.error({ path: ORDER_PAGE_PATH, err: e.message }, 'order page shell MISSING at boot');
}

const ORDER_SECRET = process.env.JWT_ACCESS_SECRET;
const ORDER_TOKEN_TTL = '4h';            // roughly the length of a dine-in visit
const MAX_LINE_QTY = 50;                  // per-line sanity cap
const MAX_LINES_PER_ORDER = 40;           // per-order sanity cap

// A brisk limiter so a leaked link can't be used to hammer the endpoints.
const orderLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please slow down.' },
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Resolve a qr_token to its table + business, only when self-ordering is on.
// Returns null when the token is unknown or the shop has the feature disabled.
async function resolveTable(qrToken) {
  await poolConnect;
  const result = await pool.request()
    .input('qr_token', sql.NVarChar(32), qrToken)
    .query(`
      SELECT t.id AS table_id, t.table_number, t.business_id, t.status AS table_status,
             bs.name AS shop_name, bs.logo_url, bs.self_order_enabled
      FROM tables t
      JOIN businesses bs ON bs.id = t.business_id
      WHERE t.qr_token = @qr_token
    `);
  if (result.recordset.length === 0) return null;
  const row = result.recordset[0];
  if (!row.self_order_enabled) return null;
  return row;
}

// Public receipt token for the bill (same scheme as the POS bills route):
// 16 URL-safe base62 chars, unguessable.
function generateReceiptToken() {
  return crypto.randomBytes(12).toString('base64url').slice(0, 16);
}

function signOrderToken({ phone, tableId, businessId }) {
  return jwt.sign(
    { typ: 'order', phone, table_id: tableId, business_id: businessId },
    ORDER_SECRET,
    { expiresIn: ORDER_TOKEN_TTL },
  );
}

// Verify an order token and confirm it was minted for THIS table. Returns the
// decoded payload or null.
function verifyOrderToken(token, tableId) {
  try {
    const p = jwt.verify(token || '', ORDER_SECRET);
    if (p.typ !== 'order' || p.table_id !== tableId) return null;
    return p;
  } catch (_) {
    return null;
  }
}

function readBearer(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

// Find the table's current open draft bill, or null. Includes customer_phone so
// callers can tell whether an incoming order belongs to the same diner.
async function findOpenDraft(request, businessId, tableId) {
  const r = await request
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('table_id', sql.UniqueIdentifier, tableId)
    .query(`
      SELECT TOP 1 id, bill_number, customer_phone
      FROM bills
      WHERE business_id = @business_id AND table_id = @table_id AND status = 'draft'
      ORDER BY created_at DESC
    `);
  return r.recordset[0] || null;
}

// Has the order token already produced a bill that is now FINALIZED? Enforces
// "one OTP = one bill": a bill on this table for this diner's phone, created at
// or after the token was issued (iat), whose status is no longer 'draft'. If so
// the token is spent and the diner must re-verify to start a new bill.
async function tokenAlreadyBilled(businessId, tableId, payload) {
  if (!payload || !payload.iat) return false;
  // JWT iat is seconds since epoch; bills.created_at is a UTC datetime.
  const issuedAt = new Date(payload.iat * 1000);
  const r = await pool.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('table_id', sql.UniqueIdentifier, tableId)
    .input('phone', sql.NVarChar(20), payload.phone)
    .input('issued_at', sql.DateTime2, issuedAt)
    .query(`
      SELECT TOP 1 id
      FROM bills
      WHERE business_id = @business_id AND table_id = @table_id
        AND customer_phone = @phone
        AND status = 'finalized'
        AND created_at >= DATEADD(minute, -1, @issued_at)
    `);
  return r.recordset.length > 0;
}

// ---------------------------------------------------------------------------
// GET /order/:qrToken  — serve the customer menu page (static HTML shell)
// ---------------------------------------------------------------------------
router.get('/:qrToken', orderLimiter, async (req, res) => {
  // The page is a static shell; it fetches /menu and /current with JS. We still
  // validate the token here so an invalid QR shows a friendly page, not a blank.
  try {
    const table = await resolveTable(req.params.qrToken);
    if (!table) {
      return res
        .status(404)
        .send('<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;text-align:center;padding:3rem"><h2>Menu not available</h2><p>This QR code is invalid, expired, or online ordering is turned off for this restaurant.</p></body>');
    }
    // Served from src/static (tracked + deployed with the code), NOT public/ —
    // the landing-page CI build empties public/ (Vite emptyOutDir), which would
    // otherwise wipe this page on every deploy. See src/static/order/index.html.
    //
    // Read + send the bytes ourselves instead of res.sendFile: under iisnode,
    // sendFile's internal `send` can 404 on a file that exists (path/stat quirks
    // via the named-pipe FS), and it swallows the real error. fs.readFile gives
    // us the true errno and a reliable send.
    return fs.readFile(ORDER_PAGE_PATH, (err, buf) => {
      if (err) {
        logger.error({ err, path: ORDER_PAGE_PATH }, 'Order page file read failed');
        return res.status(500).send('Menu page is temporarily unavailable.');
      }
      res.set('Content-Type', 'text/html; charset=utf-8');
      res.set('Cache-Control', 'no-cache');
      return res.send(buf);
    });
  } catch (err) {
    logger.error({ err }, 'Serve order page error');
    return res.status(500).send('Something went wrong.');
  }
});

// ---------------------------------------------------------------------------
// GET /order/:qrToken/menu  — JSON menu with variants and customer-only images
// ---------------------------------------------------------------------------
router.get('/:qrToken/menu', orderLimiter, async (req, res) => {
  try {
    const table = await resolveTable(req.params.qrToken);
    if (!table) return res.status(404).json({ error: 'Menu not available' });

    const itemsResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, table.business_id)
      .query(`
        SELECT id, name, category, price, tax_rate, image_url
        FROM items
        WHERE business_id = @business_id AND is_active = 1
        ORDER BY category ASC, name ASC
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
      shop_name: table.shop_name,
      shop_logo: table.logo_url || null,
      table_number: table.table_number,
      items,
    });
  } catch (err) {
    logger.error({ err }, 'Get order menu error');
    return res.status(500).json({ error: 'Failed to load menu' });
  }
});

// ---------------------------------------------------------------------------
// GET /order/:qrToken/current  — the diner's running order on this table
// Requires the order token so one diner can't read another table's bill.
// ---------------------------------------------------------------------------
router.get('/:qrToken/current', orderLimiter, async (req, res) => {
  try {
    const table = await resolveTable(req.params.qrToken);
    if (!table) return res.status(404).json({ error: 'Menu not available' });

    const payload = verifyOrderToken(readBearer(req), table.table_id);
    if (!payload) return res.json({ verified: false, items: [], total: 0 });

    const draft = await findOpenDraft(pool.request(), table.business_id, table.table_id);

    // A token is "spent" once it has produced a bill (open or already finalized).
    // If this token already created a bill on this table and that bill is no
    // longer an open draft owned by this diner, the diner must re-verify by OTP
    // to start a fresh bill (one OTP = one bill).
    const spent = await tokenAlreadyBilled(table.business_id, table.table_id, payload);
    const hasOwnDraft = draft && draft.customer_phone === payload.phone;
    if (!hasOwnDraft && spent) {
      return res.json({ verified: false, reason: 'completed', items: [], total: 0 });
    }
    if (!draft || !hasOwnDraft) {
      // Verified, but no running order of their own yet (fresh session, or the
      // table currently hosts someone else). Nothing to show; ordering rules are
      // enforced at POST time.
      return res.json({ verified: true, items: [], total: 0 });
    }

    const itemsResult = await pool.request()
      .input('bill_id', sql.UniqueIdentifier, draft.id)
      .query(`
        SELECT item_name, quantity, unit_price, line_total, kitchen_status,
               source, diner_phone
        FROM bill_items
        WHERE bill_id = @bill_id
        ORDER BY id ASC
      `);

    const items = itemsResult.recordset.map((i) => ({
      item_name: i.item_name,
      quantity: Number(i.quantity),
      line_total: Number(i.line_total),
      kitchen_status: i.kitchen_status,
      mine: i.source === 'customer' && i.diner_phone === payload.phone,
    }));
    const total = items.reduce((s, i) => s + i.line_total, 0);

    return res.json({ verified: true, bill_number: draft.bill_number, items, total });
  } catch (err) {
    logger.error({ err }, 'Get current order error');
    return res.status(500).json({ error: 'Failed to load your order' });
  }
});

// ---------------------------------------------------------------------------
// POST /order/:qrToken/send-otp  — { phone }
// ---------------------------------------------------------------------------
router.post('/:qrToken/send-otp', orderLimiter, async (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ error: 'phone is required' });
  try {
    const table = await resolveTable(req.params.qrToken);
    if (!table) return res.status(404).json({ error: 'Menu not available' });

    const result = await sendOtp(phone, 'order');
    return res.json({
      message: 'OTP sent.',
      ...(result.dev_otp ? { dev_otp: result.dev_otp } : {}),
    });
  } catch (err) {
    logger.error({ err }, 'Order send-otp error');
    return res.status(500).json({ error: err.message || 'Failed to send OTP' });
  }
});

// ---------------------------------------------------------------------------
// POST /order/:qrToken/verify-otp  — { phone, otp } -> order token
// ---------------------------------------------------------------------------
router.post('/:qrToken/verify-otp', orderLimiter, async (req, res) => {
  const { phone, otp } = req.body || {};
  if (!phone || !otp) return res.status(400).json({ error: 'phone and otp are required' });
  try {
    const table = await resolveTable(req.params.qrToken);
    if (!table) return res.status(404).json({ error: 'Menu not available' });

    const ok = await verifyOtp(phone, otp, 'order');
    if (!ok) return res.status(401).json({ error: 'Invalid or expired OTP' });

    const token = signOrderToken({
      phone: normalisePhone(phone),
      tableId: table.table_id,
      businessId: table.business_id,
    });
    return res.json({ order_token: token });
  } catch (err) {
    logger.error({ err }, 'Order verify-otp error');
    return res.status(500).json({ error: 'Failed to verify OTP' });
  }
});

// ---------------------------------------------------------------------------
// POST /order/:qrToken  — place an order (needs a valid order token)
// body: { items: [{ item_id, variant_id?, quantity }], name? }
// ---------------------------------------------------------------------------
router.post('/:qrToken', orderLimiter, async (req, res) => {
  const { items, name } = req.body || {};
  if (!Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }
  if (items.length > MAX_LINES_PER_ORDER) {
    return res.status(400).json({ error: 'Too many items in one order' });
  }

  let table;
  try {
    table = await resolveTable(req.params.qrToken);
  } catch (err) {
    logger.error({ err }, 'Place order resolve error');
    return res.status(500).json({ error: 'Failed to place order' });
  }
  if (!table) return res.status(404).json({ error: 'Menu not available' });

  const payload = verifyOrderToken(readBearer(req), table.table_id);
  if (!payload) {
    return res.status(401).json({ error: 'Please verify your phone number again.' });
  }

  const transaction = new sql.Transaction(pool);
  try {
    await poolConnect;

    // Validate + normalise requested lines up front (cheap, before the tx).
    const cleaned = [];
    for (const li of items) {
      const qty = Number(li.quantity);
      if (!li.item_id || !Number.isFinite(qty) || qty <= 0 || qty > MAX_LINE_QTY) {
        return res.status(400).json({ error: 'Invalid item or quantity' });
      }
      cleaned.push({ item_id: li.item_id, variant_id: li.variant_id || null, quantity: qty });
    }

    await transaction.begin();

    // Price every line server-side from the current menu. Active items only,
    // scoped to this business. A variant price (when set) overrides the item's.
    const itemIds = [...new Set(cleaned.map((l) => l.item_id))];
    const inNames = itemIds.map((_, i) => `@it${i}`);
    const priceReq = transaction.request()
      .input('business_id', sql.UniqueIdentifier, table.business_id);
    itemIds.forEach((id, i) => priceReq.input(`it${i}`, sql.UniqueIdentifier, id));
    const priceResult = await priceReq.query(`
      SELECT id, name, price, tax_rate
      FROM items
      WHERE business_id = @business_id AND is_active = 1 AND id IN (${inNames.join(',')})
    `);
    const itemMap = {};
    for (const r of priceResult.recordset) itemMap[r.id] = r;

    const variantIds = [...new Set(cleaned.map((l) => l.variant_id).filter(Boolean))];
    const variantMap = {};
    if (variantIds.length > 0) {
      const vNames = variantIds.map((_, i) => `@vr${i}`);
      const vReq = transaction.request()
        .input('business_id', sql.UniqueIdentifier, table.business_id);
      variantIds.forEach((id, i) => vReq.input(`vr${i}`, sql.UniqueIdentifier, id));
      const vResult = await vReq.query(`
        SELECT v.id, v.item_id, v.label, v.price
        FROM item_variants v
        JOIN items i ON i.id = v.item_id
        WHERE i.business_id = @business_id AND v.is_active = 1 AND v.id IN (${vNames.join(',')})
      `);
      for (const r of vResult.recordset) variantMap[r.id] = r;
    }

    // Build priced lines.
    const priced = [];
    for (const l of cleaned) {
      const item = itemMap[l.item_id];
      if (!item) throw { httpStatus: 400, message: 'An item is no longer available' };
      let unitPrice = Number(item.price);
      let itemName = item.name;
      if (l.variant_id) {
        const v = variantMap[l.variant_id];
        if (!v || v.item_id !== item.id) throw { httpStatus: 400, message: 'A selected option is no longer available' };
        if (v.price != null) unitPrice = Number(v.price);
        itemName = `${item.name} (${v.label})`;
      }
      priced.push({
        item_id: l.item_id,
        variant_id: l.variant_id,
        item_name: itemName,
        quantity: l.quantity,
        unit_price: unitPrice,
        tax_rate: item.tax_rate,
        line_total: +(unitPrice * l.quantity).toFixed(2),
      });
    }

    // Find or create the table's open draft bill. A new draft is stamped to the
    // business owner's user id (bills.created_by_user_id is NOT NULL) and marks
    // the table occupied.
    let draft = await findOpenDraft(transaction.request(), table.business_id, table.table_id);

    if (draft) {
      // A running order already exists on this table. Only the SAME diner (same
      // OTP-verified phone) may add more to it — a different customer must not
      // silently merge into someone else's bill.
      if (draft.customer_phone !== payload.phone) {
        throw {
          httpStatus: 409,
          code: 'table_busy',
          message: 'This table already has a running order. Please ask staff for help.',
        };
      }
    } else {
      // No open draft → this order would START a new bill.
      // 1) If the table is 'billed', the previous bill is finalized and awaiting
      //    payment at the counter — block until staff clears/settles it.
      if (table.table_status === 'billed') {
        throw {
          httpStatus: 409,
          code: 'table_billed',
          message: 'This table is being settled at the counter. Please wait or ask staff.',
        };
      }
      // 2) One OTP = one bill: if this token already produced a (now finalized)
      //    bill, it is spent — force a fresh OTP before starting another bill.
      const spent = await tokenAlreadyBilled(table.business_id, table.table_id, payload);
      if (spent) {
        throw {
          httpStatus: 401,
          code: 'reverify',
          message: 'Please verify your phone number again to place a new order.',
        };
      }
    }

    if (!draft) {
      const ownerRes = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, table.business_id)
        .query(`SELECT TOP 1 id FROM users WHERE business_id = @business_id AND role = 'owner' ORDER BY created_at ASC`);
      if (ownerRes.recordset.length === 0) {
        throw { httpStatus: 500, message: 'Restaurant is not set up for ordering' };
      }
      const ownerId = ownerRes.recordset[0].id;

      // Bill number: INV-#### using the same scheme as the POS.
      const numRes = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, table.business_id)
        .query(`
          SELECT (SELECT COUNT(*) FROM bills WHERE business_id = @business_id) AS cnt,
                 (SELECT bill_prefix FROM businesses WHERE id = @business_id) AS bill_prefix
        `);
      const prefix = (numRes.recordset[0].bill_prefix || 'INV').trim() || 'INV';
      const billNumber = `${prefix}-` + String(numRes.recordset[0].cnt + 1).padStart(4, '0');

      const createRes = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, table.business_id)
        .input('bill_number', sql.NVarChar(50), billNumber)
        .input('table_id', sql.UniqueIdentifier, table.table_id)
        .input('customer_name', sql.NVarChar(200), name || null)
        .input('customer_phone', sql.NVarChar(20), payload.phone)
        .input('created_by', sql.UniqueIdentifier, ownerId)
        .input('receipt_token', sql.NVarChar(16), generateReceiptToken())
        .query(`
          INSERT INTO bills (business_id, bill_number, table_id, customer_name, customer_phone,
                             subtotal, tax_amount, total, payment_mode, status, created_by_user_id,
                             receipt_token)
          OUTPUT INSERTED.id, INSERTED.bill_number
          VALUES (@business_id, @bill_number, @table_id, @customer_name, @customer_phone,
                  0, 0, 0, 'cash', 'draft', @created_by, @receipt_token)
        `);
      draft = createRes.recordset[0];

      // Mark the table occupied.
      await transaction.request()
        .input('table_id', sql.UniqueIdentifier, table.table_id)
        .input('business_id', sql.UniqueIdentifier, table.business_id)
        .query(`UPDATE tables SET status = 'occupied' WHERE id = @table_id AND business_id = @business_id AND status = 'empty'`);
    }

    // Insert the priced lines as customer-sourced, pending in the kitchen.
    for (const l of priced) {
      await transaction.request()
        .input('bill_id', sql.UniqueIdentifier, draft.id)
        .input('item_id', sql.UniqueIdentifier, l.item_id)
        .input('variant_id', sql.UniqueIdentifier, l.variant_id)
        .input('item_name', sql.NVarChar(200), l.item_name)
        .input('quantity', sql.Decimal(10, 2), l.quantity)
        .input('unit_price', sql.Decimal(10, 2), l.unit_price)
        .input('tax_rate', sql.Decimal(5, 2), l.tax_rate)
        .input('line_total', sql.Decimal(10, 2), l.line_total)
        .input('diner_phone', sql.NVarChar(20), payload.phone)
        .input('diner_name', sql.NVarChar(200), name || null)
        .query(`
          INSERT INTO bill_items (bill_id, item_id, variant_id, item_name, quantity,
                                  unit_price, tax_rate, line_total, kitchen_status,
                                  source, diner_phone, diner_name)
          VALUES (@bill_id, @item_id, @variant_id, @item_name, @quantity,
                  @unit_price, @tax_rate, @line_total, 'pending',
                  'customer', @diner_phone, @diner_name)
        `);
    }

    // Recompute bill totals from ALL its lines (staff + customer).
    await transaction.request()
      .input('bill_id', sql.UniqueIdentifier, draft.id)
      .query(`
        UPDATE bills
        SET subtotal = agg.sub, total = agg.sub, tax_amount = 0
        FROM bills b
        CROSS APPLY (
          SELECT ISNULL(SUM(line_total), 0) AS sub FROM bill_items WHERE bill_id = @bill_id
        ) agg
        WHERE b.id = @bill_id
      `);

    await transaction.commit();

    // Live refresh: kitchen (new dishes), tables (now occupied), drafts list.
    broadcast(table.business_id, { type: 'kitchen' });
    broadcast(table.business_id, { type: 'tables' });
    broadcast(table.business_id, { type: 'drafts' });

    return res.status(201).json({ success: true, bill_number: draft.bill_number });
  } catch (err) {
    try { await transaction.rollback(); } catch (_) {}
    if (err && err.httpStatus) {
      return res.status(err.httpStatus).json({
        error: err.message,
        ...(err.code ? { code: err.code } : {}),
      });
    }
    logger.error({ err }, 'Place customer order error');
    return res.status(500).json({ error: 'Failed to place order' });
  }
});

module.exports = router;
