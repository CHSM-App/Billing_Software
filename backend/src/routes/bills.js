const express = require('express');
const crypto  = require('crypto');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const audit = require('../audit');
const { isValidDateString, todayUtc, dayRange, dateRange } = require('../dateUtils');
const { sendBillLink, normalisePhone } = require('../whatsapp');
const { sendLowStockNotification } = require('../fcm');
const { broadcast } = require('../realtime');
const { computeRoundOff, netUnitPrice } = require('../money');

// Base URL used in receipt links — no trailing slash
const RECEIPT_BASE = process.env.RECEIPT_BASE_URL || 'https://Vittam.vengurlatech.com';

function generateReceiptToken() {
  // 16 alphanumeric chars (base62) — ~95 bits of entropy, unguessable.
  // Deliberately avoids base64url's '-' and '_': some WhatsApp/link renderers
  // munge those (e.g. inserting a space before a leading '-'), producing a
  // broken receipt URL. Pure [A-Za-z0-9] survives every renderer intact.
  const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = crypto.randomBytes(16);
  let out = '';
  for (let i = 0; i < 16; i++) out += ALPHABET[bytes[i] % 62];
  return out;
}

const router = express.Router();

// Re-derive a bill's round_off from its (already persisted) total & discount so
// the final payable stays reconciled after a totals-changing edit. When rounding
// is disabled for the business it is forced to 0. ROUND(x, 0) in SQL Server is
// round-half-up for the non-negative payable (total - discount), matching the
// create path's computeRoundOff. subtotal/tax/discount/total are never touched.
async function recomputeRoundOff(transaction, billId, roundOffEnabled) {
  await transaction.request()
    .input('id', sql.UniqueIdentifier, billId)
    .input('enabled', sql.Bit, roundOffEnabled ? 1 : 0)
    .query(`
      UPDATE bills
      SET round_off = CASE
        WHEN @enabled = 1
        THEN ROUND(total - discount_amount, 0) - (total - discount_amount)
        ELSE 0
      END
      WHERE id = @id
    `);
}

// Build a parameterized IN clause for an array of UUIDs.
// Returns { clause: '@p0,@p1,...', bind: (request) => request }
// Usage: const { clause, bind } = inParams(ids); bind(request); ... WHERE id IN (${clause})
function inParams(ids, type) {
  const sqlType = type || sql.UniqueIdentifier;
  const names = ids.map((_, i) => `@p${i}`);
  const bind = (request) => {
    ids.forEach((id, i) => request.input(`p${i}`, sqlType, id));
    return request;
  };
  return { clause: names.join(','), bind };
}

// Finalizing a bill (and collecting payment) is reserved for cashiers and
// owners. A 'server' takes/builds orders as drafts and sends them to the
// kitchen, but cannot finalize or take payment.
function cashierOrOwner(req, res, next) {
  if (req.user.role !== 'cashier' && req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only a cashier or owner can finalize a bill or take payment' });
  }
  next();
}

// Load the variants referenced by a set of request line items, scoped to the
// business (via the parent item). Returns a map keyed by variant id. Line items
// without a variant_id are ignored. Runs inside the caller's transaction so the
// rows are locked consistently with the stock updates that follow.
async function loadVariantMap(transaction, businessId, items) {
  const variantIds = [...new Set(items.map((i) => i.variant_id).filter(Boolean))];
  if (variantIds.length === 0) return {};
  const { clause, bind } = inParams(variantIds);
  const result = await bind(transaction.request())
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`
      SELECT v.id, v.item_id, v.label, v.price, v.stock_quantity, v.low_stock_threshold
      FROM item_variants v
      JOIN items i ON i.id = v.item_id
      WHERE v.id IN (${clause}) AND i.business_id = @business_id AND v.is_active = 1
    `);
  const map = {};
  for (const row of result.recordset) map[row.id] = row;
  return map;
}

// Reject any line that bills a variant item WITHOUT choosing a size.
//
// A variant item's base `items.price` is a placeholder — the real prices live on
// its sizes (Chicken 65: base 230, but half 180 / Full 280). A line with no
// variant_id would silently bill that placeholder, charging the customer a price
// that isn't on the menu. The clients open a size picker, but a scanned
// item-level barcode used to skip it, so this is enforced server-side where
// every path (online, offline sync, QR ordering) must pass.
//
// Returns an error string when a line is invalid, or null when all lines are OK.
async function findMissingVariantError(transaction, businessId, items) {
  const noVariantIds = [
    ...new Set(items.filter((i) => !i.variant_id).map((i) => i.item_id).filter(Boolean)),
  ];
  if (noVariantIds.length === 0) return null;
  const { clause, bind } = inParams(noVariantIds);
  const result = await bind(transaction.request())
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`
      SELECT DISTINCT i.name
      FROM item_variants v
      JOIN items i ON i.id = v.item_id
      WHERE v.item_id IN (${clause}) AND i.business_id = @business_id AND v.is_active = 1
    `);
  if (result.recordset.length === 0) return null;
  const names = result.recordset.map((r) => r.name).join(', ');
  return `Select a size for: ${names}`;
}

// Resolve the price to charge for one line: the variant's own price when it has
// one, otherwise the parent item's.
//
// items.price is nullable for an item sold only through its sizes, so both can
// legitimately be null — and `parseFloat(null)` is NaN, which would propagate
// silently through subtotal/tax/total and store a corrupt bill. Returning null
// here lets the caller reject the line instead.
function resolveUnitPrice(dbItem, variant) {
  if (variant && variant.price != null) return parseFloat(variant.price);
  if (dbItem.price != null) return parseFloat(dbItem.price);
  return null;
}

// Resolve one line's net (pre-tax) unit price and tax rate from the item's
// stored price, honouring items.price_inclusive_tax.
//
// An exclusive-priced item quotes the net rate directly and tax is added on top.
// An inclusive-priced (MRP) item quotes the GROSS rate, so the net rate is
// back-calculated: net = gross / (1 + rate/100). Billing then proceeds
// identically for both — bill_items.unit_price always holds the NET rate, so
// subtotal, discount-on-net, tax_amount, round-off and the printed tax invoice
// need no special cases, and an inclusive line still totals to its MRP.
//
// Rounding is deliberately left to the caller's existing line/bill rounding: we
// return full precision here so qty x net + tax lands on the MRP rather than
// drifting a paisa per unit.
//
// When GST is off (or the item carries no rate) there is no tax to extract, so
// an inclusive price IS the net price and both branches agree.
function resolveNetPriceAndRate(dbItem, variant, gstEnabled) {
  const grossOrNet = resolveUnitPrice(dbItem, variant);
  const taxRate = gstEnabled && dbItem.tax_rate != null ? parseFloat(dbItem.tax_rate) : null;
  if (grossOrNet == null) return { unitPrice: null, taxRate };
  const inclusive = dbItem.price_inclusive_tax === true || dbItem.price_inclusive_tax === 1;
  return { unitPrice: netUnitPrice(grossOrNet, taxRate, inclusive), taxRate };
}

// Thrown when a line has no price on either the variant or its parent item —
// data that should be unreachable (a sized item's variants all carry prices),
// but billing NaN would be far worse than a clear 400.
class PricelessLineError extends Error {
  constructor(itemName) {
    super(`No price set for: ${itemName}`);
    this.itemName = itemName;
  }
}

// Load recipe rows for a set of line items, keyed by item_id. Each entry is a
// list of { raw_material_id, quantity, stock_quantity, low_stock_threshold, name }.
// Rows are read inside the transaction so raw-material stock is consistent with
// the deductions that follow.
async function loadRecipeMap(transaction, businessId, items) {
  const itemIds = [...new Set(items.map((i) => i.item_id).filter(Boolean))];
  if (itemIds.length === 0) return {};
  const { clause, bind } = inParams(itemIds);
  const result = await bind(transaction.request())
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`
      SELECT ir.item_id, ir.raw_material_id, ir.quantity,
             rm.name, rm.stock_quantity, rm.low_stock_threshold
      FROM item_recipes ir
      JOIN raw_materials rm ON rm.id = ir.raw_material_id
      JOIN items i ON i.id = ir.item_id
      WHERE ir.item_id IN (${clause}) AND i.business_id = @business_id
        AND rm.business_id = @business_id AND rm.is_active = 1
    `);
  const map = {};
  for (const row of result.recordset) {
    (map[row.item_id] = map[row.item_id] || []).push(row);
  }
  return map;
}

// Atomically decrement stock for one line item. When the line references a
// variant, the variant's stock is the target; otherwise the item's. Returns
// true if a row was updated (or stock is untracked/NULL), false on shortfall.
async function decrementLineStock(transaction, businessId, li, itemMap, variantMap) {
  if (li.variant_id) {
    const variant = variantMap[li.variant_id];
    if (!variant || variant.stock_quantity == null) return true; // untracked
    const r = await transaction.request()
      .input('variant_id', sql.UniqueIdentifier, li.variant_id)
      .input('qty', sql.Decimal(10, 2), li.quantity)
      .query(`
        UPDATE item_variants
        SET stock_quantity = stock_quantity - @qty
        WHERE id = @variant_id AND stock_quantity >= @qty
      `);
    return r.rowsAffected[0] > 0;
  }
  if (itemMap[li.item_id].stock_quantity == null) return true; // untracked
  const r = await transaction.request()
    .input('item_id', sql.UniqueIdentifier, li.item_id)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('qty', sql.Decimal(10, 2), li.quantity)
    .query(`
      UPDATE items
      SET stock_quantity = stock_quantity - @qty
      WHERE id = @item_id AND business_id = @business_id AND stock_quantity >= @qty
    `);
  return r.rowsAffected[0] > 0;
}

// Build the list of stock shortfalls for a set of line items, aggregating
// requested amounts per stock target so multiple lines hitting the same target
// are summed. Covers all three line kinds plus recipe raw materials. Returns an
// array of { item_name, requested, available, ... } — empty when everything fits.
// This is an early check; the atomic guarded UPDATEs remain the true gate.
function checkInsufficientStock(lineItems, itemMap, variantMap, recipeMap) {
  // Requested amount per target key; available amount per target key.
  const requested = {};   // key -> amount
  const available = {};    // key -> amount (null = untracked)
  const label = {};        // key -> display name for the error

  const setAvail = (key, val, name) => {
    if (!(key in available)) { available[key] = val; label[key] = name; }
  };

  for (const li of lineItems) {
    if (li.variant_id) {
      const key = `var:${li.variant_id}`;
      const v = variantMap[li.variant_id];
      setAvail(key, v ? v.stock_quantity : null, li.item_name);
      requested[key] = (requested[key] || 0) + parseFloat(li.quantity);
    } else {
      const key = `item:${li.item_id}`;
      setAvail(key, itemMap[li.item_id]?.stock_quantity ?? null, li.item_name);
      requested[key] = (requested[key] || 0) + parseFloat(li.quantity);
    }

    // Recipe raw materials consumed by this line's item.
    const rows = recipeMap[li.item_id] || [];
    for (const r of rows) {
      const key = `rm:${r.raw_material_id}`;
      setAvail(key, r.stock_quantity, r.name);
      requested[key] = (requested[key] || 0) + parseFloat(r.quantity) * parseFloat(li.quantity);
    }
  }

  const out = [];
  for (const key of Object.keys(requested)) {
    const avail = available[key];
    if (avail != null && requested[key] > parseFloat(avail)) {
      out.push({ item_name: label[key], requested: requested[key], available: parseFloat(avail) });
    }
  }
  return out;
}

// Deduct every raw-material line in an item's recipe. `recipeMap` is keyed by
// item_id -> [{ raw_material_id, quantity, stock_quantity }]. Returns true when
// all raw materials had enough stock (or were untracked), false on any shortfall.
async function decrementRecipe(transaction, li, recipeMap) {
  const rows = recipeMap[li.item_id];
  if (!rows || rows.length === 0) return true;
  for (const r of rows) {
    if (r.stock_quantity == null) continue; // untracked raw material
    const used = parseFloat(r.quantity) * parseFloat(li.quantity);
    const upd = await transaction.request()
      .input('id', sql.UniqueIdentifier, r.raw_material_id)
      .input('qty', sql.Decimal(10, 2), used)
      .query(`
        UPDATE raw_materials
        SET stock_quantity = stock_quantity - @qty
        WHERE id = @id AND stock_quantity >= @qty
      `);
    if (upd.rowsAffected[0] === 0) return false;
  }
  return true;
}

// Restore stock for a line item (used when voiding/replacing bill items).
// Mirrors decrementLineStock: variants restore the variant count, plain lines
// the item count. Also restores any recipe raw materials consumed by the line.
async function restoreLineStock(transaction, businessId, li) {
  if (li.variant_id) {
    await transaction.request()
      .input('variant_id', sql.UniqueIdentifier, li.variant_id)
      .input('qty', sql.Decimal(10, 2), li.quantity)
      .query('UPDATE item_variants SET stock_quantity = stock_quantity + @qty WHERE id = @variant_id AND stock_quantity IS NOT NULL');
  } else if (li.item_id) {
    await transaction.request()
      .input('item_id', sql.UniqueIdentifier, li.item_id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('qty', sql.Decimal(10, 2), li.quantity)
      .query('UPDATE items SET stock_quantity = stock_quantity + @qty WHERE id = @item_id AND business_id = @business_id AND stock_quantity IS NOT NULL');
  }

  // Restore recipe raw materials, if this item consumes any.
  if (li.item_id) {
    await transaction.request()
      .input('item_id', sql.UniqueIdentifier, li.item_id)
      .input('qty', sql.Decimal(10, 2), li.quantity)
      .query(`
        UPDATE rm
        SET rm.stock_quantity = rm.stock_quantity + (ir.quantity * @qty)
        FROM raw_materials rm
        JOIN item_recipes ir ON ir.raw_material_id = rm.id
        WHERE ir.item_id = @item_id AND rm.stock_quantity IS NOT NULL
      `);
  }
}

// Build the low-stock notification list: which stock targets crossed from
// above-threshold to at/below-threshold on this bill. Variant lines use the
// variant's own stock/threshold; plain lines use the item's. `requested` is the
// per-target aggregated quantity (keyed by variant id when present, else item id).
function collectLowStock(lineItems, itemMap, variantMap, requested) {
  const lowItems = [];
  const seen = new Set();
  for (const li of lineItems) {
    const isVariant = !!li.variant_id;
    const key = li.variant_id || li.item_id;
    if (!key || seen.has(key)) continue;
    seen.add(key);

    const src = isVariant ? variantMap[li.variant_id] : itemMap[li.item_id];
    if (!src || src.stock_quantity == null || src.low_stock_threshold == null) continue;

    const stockBefore = parseFloat(src.stock_quantity);
    const threshold   = parseFloat(src.low_stock_threshold);
    const stockAfter  = stockBefore - (requested[key] || 0);
    if (stockBefore > threshold && stockAfter <= threshold) {
      // Variant rows carry the "Name (Label)" snapshot on li.item_name.
      lowItems.push({ name: li.item_name, remaining: stockAfter });
    }
  }
  return lowItems;
}

// Generate bill number: INV-0001, INV-0002, ...
async function generateBillNumber(transaction, businessId) {
  const result = await transaction.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`
      SELECT (SELECT COUNT(*) FROM bills WHERE business_id = @business_id) AS cnt,
             (SELECT bill_prefix FROM businesses WHERE id = @business_id) AS bill_prefix
    `);
  const next = result.recordset[0].cnt + 1;
  const prefix = (result.recordset[0].bill_prefix || 'INV').trim() || 'INV';
  return `${prefix}-` + String(next).padStart(4, '0');
}

// Fetch full bill with line items
async function fetchBill(billId, businessId) {
  const billResult = await pool.request()
    .input('id', sql.UniqueIdentifier, billId)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`
      SELECT b.id, b.business_id, b.bill_number, b.table_id, b.customer_name, b.customer_phone,
             b.subtotal, b.tax_amount, b.discount_amount, b.total, b.round_off, b.payment_mode, b.status,
             b.payment_status, b.settled_at, b.settled_payment_mode,
             b.created_by_user_id, b.created_at, b.receipt_token,
             t.table_number
      FROM bills b
      LEFT JOIN tables t ON t.id = b.table_id
      WHERE b.id = @id AND b.business_id = @business_id
    `);

  if (billResult.recordset.length === 0) return null;
  const bill = billResult.recordset[0];

  const itemsResult = await pool.request()
    .input('bill_id', sql.UniqueIdentifier, billId)
    .query(`
      SELECT id, bill_id, item_id, variant_id, item_name, quantity, unit_price, tax_rate, hsn_code, line_total,
             kitchen_status, kitchen_done_at
      FROM bill_items
      WHERE bill_id = @bill_id
    `);

  bill.items = itemsResult.recordset;
  return bill;
}

// POST /api/bills
router.post('/', requireAuth, async (req, res) => {
  const { items, table_id, customer_name, customer_phone, payment_mode, status, client_bill_id, discount_amount, bill_number, round_off } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required and must not be empty' });
  }
  if (!payment_mode) {
    return res.status(400).json({ error: 'payment_mode is required' });
  }
  const validPaymentModes = ['cash', 'upi', 'card', 'credit', 'other'];
  if (!validPaymentModes.includes(payment_mode)) {
    return res.status(400).json({ error: `payment_mode must be one of: ${validPaymentModes.join(', ')}` });
  }
  const billStatus = status || 'finalized';
  if (!['draft', 'finalized'].includes(billStatus)) {
    return res.status(400).json({ error: 'status must be draft or finalized' });
  }
  // A server may only open/build orders (drafts); finalizing + taking payment is
  // reserved for cashiers and owners.
  if (billStatus === 'finalized' && req.user.role === 'server') {
    return res.status(403).json({ error: 'A server can only send orders to the kitchen; a cashier finalizes the bill and takes payment' });
  }
  // Credit (udhaari): the sale is finalized but unpaid — money is collected
  // later via the Credit tab. We must know *who* owes, so name + phone are
  // mandatory. A draft is never "on credit" (it's just an open order).
  const isCredit = billStatus === 'finalized' && payment_mode === 'credit';
  if (isCredit) {
    if (!customer_name || !customer_name.trim() || !customer_phone || !customer_phone.trim()) {
      return res.status(400).json({ error: 'Customer name and phone are required for a credit bill' });
    }
  }
  // Unpaid only for credit sales; everything else is paid at creation.
  const paymentStatus = isCredit ? 'unpaid' : 'paid';
  // client_bill_id must be a UUID v4 when supplied
  if (client_bill_id !== undefined && (typeof client_bill_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(client_bill_id))) {
    return res.status(400).json({ error: 'client_bill_id must be a valid UUID' });
  }
  // bill_number, when supplied (offline sync), preserves the number already
  // printed on the customer's receipt. Constrain it to a safe invoice-number
  // shape and length so it can't inject arbitrary data.
  if (bill_number !== undefined && bill_number !== null &&
      (typeof bill_number !== 'string' || !/^[A-Za-z0-9\-/]{1,50}$/.test(bill_number))) {
    return res.status(400).json({ error: 'bill_number must be alphanumeric (with - or /), up to 50 chars' });
  }
  // round_off, when supplied (offline sync), preserves the exact adjustment
  // already printed on the customer's receipt. Must be a small signed number
  // (a single-rupee rounding is always within [-1, 1)).
  if (round_off !== undefined && round_off !== null &&
      (typeof round_off !== 'number' || !Number.isFinite(round_off) ||
       round_off <= -1 || round_off >= 1)) {
    return res.status(400).json({ error: 'round_off must be a number in (-1, 1)' });
  }

  try {
    await poolConnect;

    // ── Idempotency gate ──────────────────────────────────────────────────────
    // If the client supplied a client_bill_id and we already have a bill with
    // that id for this business, the request is a duplicate (e.g. network
    // timeout followed by a retry).  Return the existing bill instead of
    // creating a second one.  HTTP 200 (not 201) signals "already existed".
    if (client_bill_id) {
      const existing = await pool.request()
        .input('business_id',    sql.UniqueIdentifier, req.user.business_id)
        .input('client_bill_id', sql.NVarChar(36),     client_bill_id)
        .query(`
          SELECT id FROM bills
          WHERE business_id = @business_id AND client_bill_id = @client_bill_id
        `);
      if (existing.recordset.length > 0) {
        const bill = await fetchBill(existing.recordset[0].id, req.user.business_id);
        logger.info({ client_bill_id, bill_id: bill.id }, 'duplicate bill submission — returning existing');
        return res.status(200).json(bill);
      }
    }
    // ─────────────────────────────────────────────────────────────────────────

    const transaction = pool.transaction();
    await transaction.begin();

    try {
      // Read inventory flag and item data inside the transaction so they are
      // consistent with the stock update that follows (no TOCTOU gap).
      const bizResult = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query('SELECT inventory_enabled, round_off_enabled, gst_enabled FROM businesses WHERE id = @business_id');
      const inventoryEnabled = bizResult.recordset[0]?.inventory_enabled;
      const roundOffEnabled = !!bizResult.recordset[0]?.round_off_enabled;
      // When GST is disabled for the business, tax is ignored entirely — even if
      // an item still carries a leftover tax_rate from when GST was on. Every
      // line's tax becomes 0 and no tax_amount accrues.
      const gstEnabled = !!bizResult.recordset[0]?.gst_enabled;

      const { clause: itemClause, bind: bindItems } = inParams(items.map((i) => i.item_id));
      const itemsData = await bindItems(transaction.request())
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT id, name, price, tax_rate, price_inclusive_tax, hsn_code, stock_quantity, low_stock_threshold
          FROM items
          WHERE id IN (${itemClause}) AND business_id = @business_id AND is_active = 1
        `);
      const itemMap = {};
      for (const row of itemsData.recordset) itemMap[row.id] = row;

      // Validate all items exist
      const missingItems = items.filter((i) => !itemMap[i.item_id]);
      if (missingItems.length > 0) {
        await transaction.rollback();
        return res.status(400).json({ error: `Item not found: ${missingItems[0].item_id}` });
      }

      // Load referenced variants (sizes) and validate they belong to their item.
      const variantMap = await loadVariantMap(transaction, req.user.business_id, items);
      const badVariant = items.find(
        (i) => i.variant_id && (!variantMap[i.variant_id] || variantMap[i.variant_id].item_id !== i.item_id),
      );
      if (badVariant) {
        await transaction.rollback();
        return res.status(400).json({ error: `Variant not found: ${badVariant.variant_id}` });
      }

      // A variant item must be billed with a size — never at its base price.
      const missingVariant = await findMissingVariantError(
        transaction, req.user.business_id, items);
      if (missingVariant) {
        await transaction.rollback();
        return res.status(400).json({ error: missingVariant });
      }

      // Recipe rows (raw materials) for any items that consume them.
      const recipeMap = await loadRecipeMap(transaction, req.user.business_id, items);

      // Calculate totals
      let subtotal = 0;
      let taxAmount = 0;
      const lineItems = items.map((i) => {
        const dbItem = itemMap[i.item_id];
        const variant = i.variant_id ? variantMap[i.variant_id] : null;
        const qty = parseFloat(i.quantity);
        // Variant price overrides item price when set; otherwise fall back.
        // GST off → tax ignored entirely (rate treated as null, line tax 0).
        // Inclusive-priced items are converted to their net rate here.
        const { unitPrice, taxRate } = resolveNetPriceAndRate(dbItem, variant, gstEnabled);
        if (unitPrice == null) throw new PricelessLineError(dbItem.name);
        const itemName = variant ? `${dbItem.name} (${variant.label})` : dbItem.name;
        const lineTax = taxRate ? qty * unitPrice * (taxRate / 100) : 0;
        const lineTotal = qty * unitPrice + lineTax;
        subtotal += qty * unitPrice;
        taxAmount += lineTax;
        return {
          item_id: dbItem.id,
          variant_id: variant ? variant.id : null,
          item_name: itemName,
          quantity: qty,
          unit_price: unitPrice,
          tax_rate: taxRate,
          hsn_code: dbItem.hsn_code || null,
          line_total: parseFloat(lineTotal.toFixed(2)),
        };
      });
      subtotal = parseFloat(subtotal.toFixed(2));
      taxAmount = parseFloat(taxAmount.toFixed(2));
      // Discount applies to the NET (pre-tax) subtotal; tax is then charged on
      // the discounted net. So clamp the discount to the subtotal and scale the
      // tax in proportion (bill-level: tax × discountedNet / subtotal). total is
      // subtotal + the discounted tax, so payable (total − discount) equals
      // discountedNet + discountedTax — the identity round-off/payable rely on.
      const discountAmount = parseFloat(Math.min(
        Math.max(parseFloat(discount_amount) || 0, 0),
        subtotal,
      ).toFixed(2));
      if (subtotal > 0 && discountAmount > 0) {
        taxAmount = parseFloat(
          (taxAmount * (subtotal - discountAmount) / subtotal).toFixed(2));
      }
      const total = parseFloat((subtotal + taxAmount).toFixed(2));

      // Invoice-level round-off. subtotal/tax/discount/total above are NEVER
      // modified; round_off is a separate signed adjustment on the final payable
      // (total - discount). Offline bills carry the exact round_off already
      // printed on the customer's receipt — preserve it verbatim; online bills
      // compute it server-side from the business's round_off_enabled setting.
      const roundOff = (round_off !== undefined && round_off !== null)
        ? parseFloat(Number(round_off).toFixed(2))
        : computeRoundOff(total - discountAmount, roundOffEnabled);

      // Centralized stock pre-check: validate ALL items before any writes.
      // itemMap rows were fetched inside this transaction (locked), so
      // stock_quantity here reflects the committed state at transaction start.
      // The atomic UPDATE below is still the final concurrency guard, but this
      // pre-check catches obvious shortfalls early and reports all failing items
      // at once rather than discovering them one-by-one mid-write.
      // Aggregate requested quantities per item — used for both stock validation
      // and the post-commit low-stock notification check below.
      // Aggregate requested quantities per stock target. The target is the
      // variant when present, otherwise the item — so a size's stock is checked
      // independently of the base item and its other sizes.
      // Per-target requested totals for the low-stock notification below.
      const stockKey = (li) => li.variant_id || li.item_id;
      const requested = {};
      for (const li of lineItems) {
        requested[stockKey(li)] = (requested[stockKey(li)] || 0) + li.quantity;
      }

      if (inventoryEnabled) {
        const insufficient = checkInsufficientStock(lineItems, itemMap, variantMap, recipeMap);
        if (insufficient.length > 0) {
          await transaction.rollback();
          return res.status(409).json({
            error: 'Insufficient stock',
            items: insufficient,
          });
        }
      }

      // Offline bills carry the number already printed on the customer's
      // receipt (bill_number) — keep it verbatim. Only bills created directly on
      // the server (no client number) get a fresh server sequence.
      const billNumber = (bill_number && bill_number.trim())
        ? bill_number.trim()
        : await generateBillNumber(transaction, req.user.business_id);
      const receiptToken = generateReceiptToken();

      // Insert bill
      const billResult = await transaction.request()
        .input('business_id',     sql.UniqueIdentifier, req.user.business_id)
        .input('bill_number',     sql.NVarChar(50),     billNumber)
        .input('table_id',        sql.UniqueIdentifier, table_id || null)
        .input('customer_name',   sql.NVarChar(200),    customer_name || null)
        .input('customer_phone',  sql.NVarChar(20),     customer_phone || null)
        .input('subtotal',        sql.Decimal(10, 2),   subtotal)
        .input('tax_amount',      sql.Decimal(10, 2),   taxAmount)
        .input('discount_amount', sql.Decimal(10, 2),   discountAmount)
        .input('total',           sql.Decimal(10, 2),   total)
        .input('round_off',       sql.Decimal(10, 2),   roundOff)
        .input('payment_mode',    sql.NVarChar(20),     payment_mode)
        .input('payment_status',  sql.NVarChar(20),     paymentStatus)
        .input('status',          sql.NVarChar(20),     billStatus)
        .input('created_by_user_id', sql.UniqueIdentifier, req.user.user_id)
        .input('client_bill_id',  sql.NVarChar(36),     client_bill_id || null)
        .input('receipt_token',   sql.NVarChar(16),     receiptToken)
        .query(`
          INSERT INTO bills (business_id, bill_number, table_id, customer_name, customer_phone,
                             subtotal, tax_amount, discount_amount, total, round_off, payment_mode, payment_status, status,
                             created_by_user_id, client_bill_id, receipt_token)
          OUTPUT INSERTED.id
          VALUES (@business_id, @bill_number, @table_id, @customer_name, @customer_phone,
                  @subtotal, @tax_amount, @discount_amount, @total, @round_off, @payment_mode, @payment_status, @status,
                  @created_by_user_id, @client_bill_id, @receipt_token)
        `);

      const billId = billResult.recordset[0].id;

      // Insert bill_items
      for (const li of lineItems) {
        await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, billId)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('variant_id', sql.UniqueIdentifier, li.variant_id || null)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit_price', sql.Decimal(12, 4), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('hsn_code', sql.NVarChar(10), li.hsn_code || null)
          .input('line_total', sql.Decimal(10, 2), li.line_total)
          .query(`
            INSERT INTO bill_items (bill_id, item_id, variant_id, item_name, quantity, unit_price, tax_rate, hsn_code, line_total)
            VALUES (@bill_id, @item_id, @variant_id, @item_name, @quantity, @unit_price, @tax_rate, @hsn_code, @line_total)
          `);
      }

      // Update table status if table_id provided
      if (table_id) {
        const tableStatus = billStatus === 'draft' ? 'occupied' : 'billed';
        await transaction.request()
          .input('table_id', sql.UniqueIdentifier, table_id)
          .input('business_id', sql.UniqueIdentifier, req.user.business_id)
          .input('table_status', sql.NVarChar(20), tableStatus)
          .query(`
            UPDATE tables SET status = @table_status
            WHERE id = @table_id AND business_id = @business_id
          `);
      }

      // Atomically decrement stock — final concurrency guard.
      // AND stock_quantity >= @qty prevents negative stock if another request
      // consumed inventory between our read above and this write.
      if (inventoryEnabled) {
        for (const li of lineItems) {
          const ok = await decrementLineStock(transaction, req.user.business_id, li, itemMap, variantMap);
          if (!ok) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id, variant_id: li.variant_id }],
            });
          }
          const recipeOk = await decrementRecipe(transaction, li, recipeMap);
          if (!recipeOk) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id }],
            });
          }
        }
      }

      await transaction.commit();

      // Collect stock targets that just crossed below their threshold (stock was
      // above before, at/below after). Bundle into one notification. For variant
      // lines the variant's own stock/threshold is used; otherwise the item's.
      if (inventoryEnabled) {
        (async () => {
          try {
            const lowItems = collectLowStock(lineItems, itemMap, variantMap, requested);
            logger.info({ lowItems }, '[FCM] sending low-stock notification');
            await sendLowStockNotification(pool, sql, req.user.business_id, lowItems);
          } catch (err) {
            logger.error({ err }, '[FCM] low-stock notification error');
          }
        })();
      }

      const created = await fetchBill(billId, req.user.business_id);

      // Real-time: a new draft appears on the kitchen queue and (depending on
      // whether it has a table) on the tables screen or the open-orders list.
      if (billStatus === 'draft') {
        broadcast(req.user.business_id, { type: 'kitchen' });
        broadcast(req.user.business_id,
          { type: created.table_id ? 'tables' : 'drafts' });
      }

      // Audit — fire-and-forget after the transaction commits
      audit.logBillCreated(
        { user_id: req.user.user_id, user_name: req.user.name || null },
        { id: billId, business_id: req.user.business_id, bill_number: billNumber, total, payment_mode, status: billStatus },
        lineItems,
      );

      return res.status(201).json(created);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    if (err instanceof PricelessLineError) {
      return res.status(400).json({ error: err.message });
    }
    logger.error({ err }, 'Create bill error');
    return res.status(500).json({ error: 'Failed to create bill' });
  }
});

// GET /api/bills
router.get('/', requireAuth, async (req, res) => {
  const { from, to, search } = req.query;

  try {
    await poolConnect;
    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    // Validate supplied date strings before touching the DB
    if (from && !isValidDateString(from)) {
      return res.status(400).json({ error: 'from must be a valid date in YYYY-MM-DD format' });
    }
    if (to && !isValidDateString(to)) {
      return res.status(400).json({ error: 'to must be a valid date in YYYY-MM-DD format' });
    }

    let where = 'b.business_id = @business_id';

    if (from && to) {
      // Explicit range: sargable DATETIME2 bounds (>= start of from-day, < start of day after to)
      const { start: fromDt, end: toDt } = dateRange(from, to);
      request.input('from_dt', sql.DateTime2, fromDt);
      request.input('to_dt',   sql.DateTime2, toDt);
      where += ' AND b.created_at >= @from_dt AND b.created_at < @to_dt';
    } else if (from) {
      // Only lower bound supplied — from that day onward
      const { start: fromDt } = dayRange(from);
      request.input('from_dt', sql.DateTime2, fromDt);
      where += ' AND b.created_at >= @from_dt';
    } else {
      // No range supplied — default to today (UTC calendar day)
      const dateStr = todayUtc();
      const { start: fromDt, end: toDt } = dayRange(dateStr);
      request.input('from_dt', sql.DateTime2, fromDt);
      request.input('to_dt',   sql.DateTime2, toDt);
      where += ' AND b.created_at >= @from_dt AND b.created_at < @to_dt';
    }
    if (search) {
      request.input('search', sql.NVarChar(100), `%${search}%`);
      where += ' AND (b.bill_number LIKE @search OR b.customer_phone LIKE @search)';
    }

    const billsResult = await request.query(`
      SELECT b.id, b.business_id, b.bill_number, b.table_id, b.customer_name, b.customer_phone,
             b.subtotal, b.tax_amount, b.discount_amount, b.total, b.round_off, b.payment_mode, b.status,
             b.created_by_user_id, b.created_at, b.receipt_token
      FROM bills b
      WHERE ${where}
      ORDER BY b.created_at DESC
    `);

    if (billsResult.recordset.length === 0) return res.json([]);

    const { clause: billClause, bind: bindBills } = inParams(billsResult.recordset.map((b) => b.id));
    const itemsResult = await bindBills(pool.request()).query(`
      SELECT id, bill_id, item_id, variant_id, item_name, quantity, unit_price, tax_rate, hsn_code, line_total,
             kitchen_status, kitchen_done_at
      FROM bill_items
      WHERE bill_id IN (${billClause})
    `);

    const itemsByBill = {};
    for (const item of itemsResult.recordset) {
      if (!itemsByBill[item.bill_id]) itemsByBill[item.bill_id] = [];
      itemsByBill[item.bill_id].push(item);
    }

    const bills = billsResult.recordset.map((b) => ({
      ...b,
      items: itemsByBill[b.id] || [],
    }));

    return res.json(bills);
  } catch (err) {
    logger.error({ err }, 'Get bills error');
    return res.status(500).json({ error: 'Failed to fetch bills' });
  }
});

// GET /api/bills/drafts
// Open orders that are NOT attached to a table — the "Open Orders" queue. A
// server can build these on the billing page; a cashier/owner picks them up and
// finalizes them. Table drafts are excluded (those live on the Tables screen).
// Declared before '/:id' so the literal path wins the route match.
router.get('/drafts', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const billsResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.id, b.business_id, b.bill_number, b.table_id, b.customer_name, b.customer_phone,
               b.subtotal, b.tax_amount, b.discount_amount, b.total, b.round_off, b.payment_mode, b.status,
               b.created_by_user_id, b.created_at, b.receipt_token
        FROM bills b
        WHERE b.business_id = @business_id
          AND b.status = 'draft'
          AND b.table_id IS NULL
        ORDER BY b.created_at DESC
      `);

    if (billsResult.recordset.length === 0) return res.json([]);

    const { clause: billClause, bind: bindBills } = inParams(billsResult.recordset.map((b) => b.id));
    const itemsResult = await bindBills(pool.request()).query(`
      SELECT id, bill_id, item_id, variant_id, item_name, quantity, unit_price, tax_rate, hsn_code, line_total,
             kitchen_status, kitchen_done_at
      FROM bill_items
      WHERE bill_id IN (${billClause})
    `);

    const itemsByBill = {};
    for (const item of itemsResult.recordset) {
      if (!itemsByBill[item.bill_id]) itemsByBill[item.bill_id] = [];
      itemsByBill[item.bill_id].push(item);
    }

    const bills = billsResult.recordset.map((b) => ({
      ...b,
      items: itemsByBill[b.id] || [],
    }));

    return res.json(bills);
  } catch (err) {
    logger.error({ err }, 'Get draft bills error');
    return res.status(500).json({ error: 'Failed to fetch draft bills' });
  }
});

// GET /api/bills/:id
// ---------------------------------------------------------------------------
// GET /api/bills/customers/search?q=<name or phone>&limit=8
//
// Past customers of this business, for the billing screen's name/phone
// autocomplete. Matches on either field so one endpoint serves both inputs.
//
// A customer is not a table here - they exist only as the name/phone recorded
// on past bills - so this aggregates those bills. The most recent name wins
// (people correct a typo on a later visit), and results are ordered by visit
// count so a regular appears before a one-off.
//
// Not owner-gated: a cashier taking an order needs it. It exposes nothing the
// cashier cannot already see on the bill history.
// ---------------------------------------------------------------------------
router.get('/customers/search', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const q = String(req.query.q || '').trim();
    if (q.length < 2) return res.json([]);

    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 8, 1), 20);

    // Digits-only copy so "98765 43210", "+91 9876543210" and "9876543210"
    // all match the same stored number.
    const digits = q.replace(/\D/g, '');

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('name_like', sql.NVarChar(200), `%${q}%`)
      .input('phone_like', sql.NVarChar(20), digits ? `%${digits}%` : '~no~match~')
      .query(`
        WITH matched AS (
          -- Every phone that has at least one bill matching the query.
          SELECT DISTINCT customer_phone
          FROM bills
          WHERE business_id = @business_id
            AND customer_phone IS NOT NULL
            AND LTRIM(RTRIM(customer_phone)) <> ''
            AND (customer_name LIKE @name_like OR customer_phone LIKE @phone_like)
        )
        SELECT TOP (${limit})
          -- Prefer the most recent name that MATCHES what was typed; fall back
          -- to the most recent name otherwise. Showing an unrelated name for
          -- the same phone (the person used two names) would look like a bug
          -- in an autocomplete: you type "Sh" and get back "Sagar".
          (SELECT TOP 1 b2.customer_name FROM bills b2
            WHERE b2.business_id = @business_id
              AND b2.customer_phone = b.customer_phone
              AND b2.customer_name IS NOT NULL
              AND LTRIM(RTRIM(b2.customer_name)) <> ''
            ORDER BY
              CASE WHEN b2.customer_name LIKE @name_like THEN 0 ELSE 1 END,
              b2.created_at DESC)          AS customer_name,
          b.customer_phone,
          -- Count ALL of that phone's bills, not just the matching rows: a
          -- name search would otherwise under-report a regular's visit count.
          COUNT(*)                         AS visits,
          MAX(b.created_at)                AS last_bill_at
        FROM bills b
        INNER JOIN matched m ON m.customer_phone = b.customer_phone
        WHERE b.business_id = @business_id
        GROUP BY b.customer_phone
        ORDER BY COUNT(*) DESC, MAX(b.created_at) DESC`);

    // The same person often appears as 9876543210 and 919876543210. Collapse on
    // the last 10 digits so the list does not offer the same customer twice.
    const seen = new Map();
    for (const r of result.recordset) {
      const phone = String(r.customer_phone || '').trim();
      const key = phone.replace(/\D/g, '').slice(-10) || phone;
      const existing = seen.get(key);
      if (!existing || Number(r.visits) > existing.visits) {
        seen.set(key, {
          customer_name: r.customer_name || '',
          customer_phone: phone,
          visits: Number(r.visits),
          last_bill_at: r.last_bill_at,
        });
      }
    }

    return res.json([...seen.values()]);
  } catch (err) {
    logger.error({ err }, 'customer search error');
    return res.status(500).json({ error: 'Failed to search customers' });
  }
});

router.get('/:id', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const bill = await fetchBill(req.params.id, req.user.business_id);
    if (!bill) return res.status(404).json({ error: 'Bill not found' });
    return res.json(bill);
  } catch (err) {
    logger.error({ err }, 'Get bill error');
    return res.status(500).json({ error: 'Failed to fetch bill' });
  }
});

// PUT /api/bills/:id/finalize
router.put('/:id/finalize', requireAuth, cashierOrOwner, async (req, res) => {
  try {
    await poolConnect;
    // The app finalizes a bill in two steps: create as draft, then finalize.
    // So the credit → unpaid decision has to happen HERE, not only at create.
    // A credit bill becomes a finalized-but-unpaid sale (money collected later
    // via the Credit tab); every other mode is paid on finalize.
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        UPDATE bills
        SET status = 'finalized',
            payment_status = CASE WHEN payment_mode = 'credit' THEN 'unpaid' ELSE 'paid' END
        OUTPUT INSERTED.id, INSERTED.table_id, INSERTED.bill_number,
               INSERTED.payment_mode, INSERTED.customer_name, INSERTED.customer_phone
        WHERE id = @id AND business_id = @business_id AND status = 'draft'
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Draft bill not found' });
    }

    // A credit finalize with no customer is unrecoverable in the Credit tab
    // (nothing to group by). The client enforces name+phone, but guard here too.
    const finalizedRow = result.recordset[0];
    if (finalizedRow.payment_mode === 'credit' &&
        (!finalizedRow.customer_name || !finalizedRow.customer_phone)) {
      logger.warn(
        { bill_id: req.params.id },
        'credit bill finalized without customer name/phone',
      );
    }

    const { table_id: tableId, bill_number: billNumber } = result.recordset[0];
    if (tableId) {
      await pool.request()
        .input('table_id', sql.UniqueIdentifier, tableId)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          UPDATE tables SET status = 'billed'
          WHERE id = @table_id AND business_id = @business_id
        `);
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);

    audit.logBillFinalized(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: billNumber },
    );

    // Real-time: a finalized order leaves the kitchen queue and frees/updates its
    // table or the open-orders list.
    broadcast(req.user.business_id, { type: 'kitchen' });
    broadcast(req.user.business_id, { type: bill.table_id ? 'tables' : 'drafts' });
    // A finalized credit bill adds to the debtor list — refresh the Credit tab.
    if (finalizedRow.payment_mode === 'credit') {
      broadcast(req.user.business_id, { type: 'credit' });
    }

    return res.json(bill);
  } catch (err) {
    logger.error({ err }, 'Finalize bill error');
    return res.status(500).json({ error: 'Failed to finalize bill' });
  }
});

// PUT /api/bills/:id/add-items
router.put('/:id/add-items', requireAuth, async (req, res) => {
  const { items } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }

  let addedLineItems = [];

  try {
    await poolConnect;

    const transaction = pool.transaction();
    await transaction.begin();

    try {
      // Read bill status, inventory flag, and item data inside the transaction
      // so they are consistent with the stock update that follows (no TOCTOU gap).
      const billCheck = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT b.id, b.status, bs.inventory_enabled, bs.round_off_enabled, bs.gst_enabled
          FROM bills b
          JOIN businesses bs ON bs.id = b.business_id
          WHERE b.id = @id AND b.business_id = @business_id
        `);

      if (billCheck.recordset.length === 0) {
        await transaction.rollback();
        return res.status(404).json({ error: 'Bill not found' });
      }
      if (billCheck.recordset[0].status !== 'draft') {
        await transaction.rollback();
        return res.status(409).json({ error: 'Can only add items to a draft bill' });
      }
      const inventoryEnabled = billCheck.recordset[0].inventory_enabled;
      const roundOffEnabled = !!billCheck.recordset[0].round_off_enabled;
      // GST off → tax ignored entirely, even for items with a leftover tax_rate.
      const gstEnabled = !!billCheck.recordset[0].gst_enabled;

      const { clause: itemClause2, bind: bindItems2 } = inParams(items.map((i) => i.item_id));
      const itemsData = await bindItems2(transaction.request())
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT id, name, price, tax_rate, price_inclusive_tax, hsn_code, stock_quantity, low_stock_threshold
          FROM items
          WHERE id IN (${itemClause2}) AND business_id = @business_id AND is_active = 1
        `);
      const itemMap = {};
      for (const row of itemsData.recordset) itemMap[row.id] = row;

      const missingItems2 = items.filter((i) => !itemMap[i.item_id]);
      if (missingItems2.length > 0) {
        await transaction.rollback();
        return res.status(400).json({ error: `Item not found: ${missingItems2[0].item_id}` });
      }

      const variantMap = await loadVariantMap(transaction, req.user.business_id, items);
      const badVariant2 = items.find(
        (i) => i.variant_id && (!variantMap[i.variant_id] || variantMap[i.variant_id].item_id !== i.item_id),
      );
      if (badVariant2) {
        await transaction.rollback();
        return res.status(400).json({ error: `Variant not found: ${badVariant2.variant_id}` });
      }

      // A variant item must be billed with a size — never at its base price.
      const missingVariant2 = await findMissingVariantError(
        transaction, req.user.business_id, items);
      if (missingVariant2) {
        await transaction.rollback();
        return res.status(400).json({ error: missingVariant2 });
      }

      const recipeMap = await loadRecipeMap(transaction, req.user.business_id, items);

      const lineItems = items.map((i) => {
        const dbItem = itemMap[i.item_id];
        const variant = i.variant_id ? variantMap[i.variant_id] : null;
        const qty = parseFloat(i.quantity);
        // GST off → tax ignored entirely (rate treated as null, line tax 0).
        // Inclusive-priced items are converted to their net rate here.
        const { unitPrice, taxRate } = resolveNetPriceAndRate(dbItem, variant, gstEnabled);
        if (unitPrice == null) throw new PricelessLineError(dbItem.name);
        const itemName = variant ? `${dbItem.name} (${variant.label})` : dbItem.name;
        const lineTax = taxRate ? qty * unitPrice * (taxRate / 100) : 0;
        return {
          item_id: dbItem.id,
          variant_id: variant ? variant.id : null,
          item_name: itemName,
          quantity: qty,
          unit_price: unitPrice,
          tax_rate: taxRate,
          hsn_code: dbItem.hsn_code || null,
          line_total: parseFloat((qty * unitPrice + lineTax).toFixed(2)),
        };
      });

      const stockKey2 = (li) => li.variant_id || li.item_id;
      const requested2 = {};
      for (const li of lineItems) {
        requested2[stockKey2(li)] = (requested2[stockKey2(li)] || 0) + li.quantity;
      }
      if (inventoryEnabled) {
        const insufficient2 = checkInsufficientStock(lineItems, itemMap, variantMap, recipeMap);
        if (insufficient2.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ error: 'Insufficient stock', items: insufficient2 });
        }
      }

      for (const li of lineItems) {
        await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('variant_id', sql.UniqueIdentifier, li.variant_id || null)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit_price', sql.Decimal(12, 4), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('hsn_code', sql.NVarChar(10), li.hsn_code || null)
          .input('line_total', sql.Decimal(10, 2), li.line_total)
          .query(`
            INSERT INTO bill_items (bill_id, item_id, variant_id, item_name, quantity, unit_price, tax_rate, hsn_code, line_total)
            VALUES (@bill_id, @item_id, @variant_id, @item_name, @quantity, @unit_price, @tax_rate, @hsn_code, @line_total)
          `);
      }

      // Recalculate totals from all bill_items. Discount applies to the NET
      // subtotal and tax is charged on the discounted net, so tax_amount is the
      // raw line tax scaled by discountedNet/subtotal (clamped so a discount can
      // never exceed the subtotal). total = subtotal + discounted tax, keeping
      // payable = total − discount reconciled. Uses the already-persisted
      // discount_amount (this path edits items, not the discount).
      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`
          UPDATE b SET
            subtotal   = agg.sub,
            tax_amount = ROUND(agg.raw_tax * (agg.sub - agg.disc) / NULLIF(agg.sub, 0), 2),
            total      = agg.sub + ROUND(agg.raw_tax * (agg.sub - agg.disc) / NULLIF(agg.sub, 0), 2)
          FROM bills b
          CROSS APPLY (
            SELECT
              CAST(SUM(bi.quantity * bi.unit_price) AS DECIMAL(18,4)) AS sub,
              CAST(SUM(bi.line_total - bi.quantity * bi.unit_price) AS DECIMAL(18,4)) AS raw_tax,
              CASE WHEN b.discount_amount >
                        CAST(SUM(bi.quantity * bi.unit_price) AS DECIMAL(18,4))
                   THEN CAST(SUM(bi.quantity * bi.unit_price) AS DECIMAL(18,4))
                   ELSE b.discount_amount END AS disc
            FROM bill_items bi WHERE bi.bill_id = @id
          ) agg
          WHERE b.id = @id
        `);

      // Re-derive round_off from the fresh total/discount so the final payable
      // stays reconciled after the edit. Off (0) when the business has rounding
      // disabled. ROUND(x,0) is round-half-up for the non-negative payable.
      await recomputeRoundOff(transaction, req.params.id, roundOffEnabled);

      // Atomic decrement — final concurrency guard.
      if (inventoryEnabled) {
        for (const li of lineItems) {
          const ok = await decrementLineStock(transaction, req.user.business_id, li, itemMap, variantMap);
          if (!ok) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id, variant_id: li.variant_id }],
            });
          }
          const recipeOk = await decrementRecipe(transaction, li, recipeMap);
          if (!recipeOk) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id }],
            });
          }
        }
      }

      addedLineItems = lineItems;
      await transaction.commit();

      // Collect targets that just crossed below their threshold, send one
      // notification. Handles variant lines via their own stock/threshold.
      if (inventoryEnabled) {
        (async () => {
          try {
            const lowItems = collectLowStock(lineItems, itemMap, variantMap, requested2);
            await sendLowStockNotification(pool, sql, req.user.business_id, lowItems);
          } catch (_) {}
        })();
      }
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);

    // Real-time: dishes were added to an existing order — refresh the kitchen.
    if (bill && bill.status === 'draft' && addedLineItems.length > 0) {
      broadcast(req.user.business_id, { type: 'kitchen' });
    }

    audit.logBillItemsAdded(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: bill.bill_number },
      addedLineItems,
    );

    return res.json(bill);
  } catch (err) {
    if (err instanceof PricelessLineError) {
      return res.status(400).json({ error: err.message });
    }
    logger.error({ err }, 'Add items error');
    return res.status(500).json({ error: 'Failed to add items' });
  }
});

// PUT /api/bills/:id/update-items — replace all items on a draft bill
router.put('/:id/update-items', requireAuth, async (req, res) => {
  const { items, customer_name, customer_phone, discount_amount } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }
  // Only overwrite a field when the key was actually sent, so callers that omit
  // them (e.g. the kitchen) never wipe existing details.
  const setCustomerName = Object.prototype.hasOwnProperty.call(req.body, 'customer_name');
  const setCustomerPhone = Object.prototype.hasOwnProperty.call(req.body, 'customer_phone');
  const setDiscount = Object.prototype.hasOwnProperty.call(req.body, 'discount_amount');

  let previousLineItems = [];
  let replacementLineItems = [];

  try {
    await poolConnect;

    const transaction = pool.transaction();
    await transaction.begin();

    try {
      // Read bill status, inventory flag, and item data inside the transaction
      // so they are consistent with the stock updates that follow (no TOCTOU gap).
      const billCheck = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT b.id, b.status, bs.inventory_enabled, bs.round_off_enabled, bs.gst_enabled
          FROM bills b
          JOIN businesses bs ON bs.id = b.business_id
          WHERE b.id = @id AND b.business_id = @business_id
        `);

      if (billCheck.recordset.length === 0) {
        await transaction.rollback();
        return res.status(404).json({ error: 'Bill not found' });
      }
      if (billCheck.recordset[0].status !== 'draft') {
        await transaction.rollback();
        return res.status(409).json({ error: 'Can only update items on a draft bill' });
      }
      const inventoryEnabled = billCheck.recordset[0].inventory_enabled;
      const roundOffEnabled = !!billCheck.recordset[0].round_off_enabled;
      // GST off → tax ignored entirely, even for items with a leftover tax_rate.
      const gstEnabled = !!billCheck.recordset[0].gst_enabled;

      const { clause: itemClause3, bind: bindItems3 } = inParams(items.map((i) => i.item_id));
      const itemsData = await bindItems3(transaction.request())
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT id, name, price, tax_rate, price_inclusive_tax, hsn_code, stock_quantity
          FROM items
          WHERE id IN (${itemClause3}) AND business_id = @business_id AND is_active = 1
        `);
      const itemMap = {};
      for (const row of itemsData.recordset) itemMap[row.id] = row;

      const missingItems3 = items.filter((i) => !itemMap[i.item_id]);
      if (missingItems3.length > 0) {
        await transaction.rollback();
        return res.status(400).json({ error: `Item not found: ${missingItems3[0].item_id}` });
      }

      const variantMap = await loadVariantMap(transaction, req.user.business_id, items);
      const badVariant3 = items.find(
        (i) => i.variant_id && (!variantMap[i.variant_id] || variantMap[i.variant_id].item_id !== i.item_id),
      );
      if (badVariant3) {
        await transaction.rollback();
        return res.status(400).json({ error: `Variant not found: ${badVariant3.variant_id}` });
      }

      // A variant item must be billed with a size — never at its base price.
      const missingVariant3 = await findMissingVariantError(
        transaction, req.user.business_id, items);
      if (missingVariant3) {
        await transaction.rollback();
        return res.status(400).json({ error: missingVariant3 });
      }

      const recipeMap = await loadRecipeMap(transaction, req.user.business_id, items);

      const lineItems = items.map((i) => {
        const dbItem = itemMap[i.item_id];
        const variant = i.variant_id ? variantMap[i.variant_id] : null;
        const qty = parseFloat(i.quantity);
        // GST off → tax ignored entirely (rate treated as null, line tax 0).
        // Inclusive-priced items are converted to their net rate here.
        const { unitPrice, taxRate } = resolveNetPriceAndRate(dbItem, variant, gstEnabled);
        if (unitPrice == null) throw new PricelessLineError(dbItem.name);
        const itemName = variant ? `${dbItem.name} (${variant.label})` : dbItem.name;
        const lineTax = taxRate ? qty * unitPrice * (taxRate / 100) : 0;
        return {
          item_id: dbItem.id,
          variant_id: variant ? variant.id : null,
          item_name: itemName,
          quantity: qty,
          unit_price: unitPrice,
          tax_rate: taxRate,
          hsn_code: dbItem.hsn_code || null,
          line_total: parseFloat((qty * unitPrice + lineTax).toFixed(2)),
        };
      });

      // Centralized stock pre-check for new items.
      // Note: old-item stock will be restored below before the new decrements,
      // so we check against current stock_quantity as a conservative lower bound.
      // The atomic UPDATE is still the final concurrency guard.
      if (inventoryEnabled) {
        const insufficient3 = checkInsufficientStock(lineItems, itemMap, variantMap, recipeMap);
        if (insufficient3.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ error: 'Insufficient stock', items: insufficient3 });
        }
      }

      // Snapshot old items for audit + stock restore. Kitchen fields are read
      // too so a dish the kitchen already marked ready keeps that status when the
      // waiter edits the order (this endpoint replaces all lines, so without this
      // the checkboxes would reset — see the kitchen-status carry-over below).
      const oldItemsResult = await transaction.request()
        .input('bill_id', sql.UniqueIdentifier, req.params.id)
        .query('SELECT item_id, variant_id, item_name, quantity, unit_price, kitchen_status, kitchen_done_at FROM bill_items WHERE bill_id = @bill_id');
      previousLineItems = oldItemsResult.recordset;

      // Build a per-dish pool of prior kitchen statuses keyed by identity
      // (item + variant + name). Each new line consumes one matching prior status
      // so an unchanged dish keeps "ready"; genuinely new dishes stay "pending".
      const kitchenPool = {};
      const dishKey = (li) => `${li.item_id || ''}|${li.variant_id || ''}|${li.item_name}`;
      for (const old of previousLineItems) {
        (kitchenPool[dishKey(old)] ||= []).push({
          kitchen_status: old.kitchen_status,
          kitchen_done_at: old.kitchen_done_at,
          quantity: parseFloat(old.quantity),
        });
      }
      const takeKitchenStatus = (li) => {
        const bucket = kitchenPool[dishKey(li)];
        if (bucket && bucket.length > 0) {
          const prev = bucket.shift();
          // If the waiter increased the quantity of an already-ready dish, the
          // extra portions still need cooking — send it back to pending.
          if (prev.kitchen_status === 'ready' && parseFloat(li.quantity) > prev.quantity) {
            return { kitchen_status: 'pending', kitchen_done_at: null };
          }
          return { kitchen_status: prev.kitchen_status, kitchen_done_at: prev.kitchen_done_at };
        }
        return { kitchen_status: 'pending', kitchen_done_at: null };
      };

      // Restore inventory for old items — increment is always safe, no guard needed.
      // restoreLineStock handles variants, plain items and recipes.
      if (inventoryEnabled) {
        for (const li of previousLineItems.filter((x) => x.item_id || x.variant_id)) {
          await restoreLineStock(transaction, req.user.business_id, li);
        }
      }

      // Delete existing line items
      await transaction.request()
        .input('bill_id', sql.UniqueIdentifier, req.params.id)
        .query('DELETE FROM bill_items WHERE bill_id = @bill_id');

      // Insert new line items, carrying over the prior kitchen status for any
      // dish that already existed on the order.
      for (const li of lineItems) {
        const k = takeKitchenStatus(li);
        await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('variant_id', sql.UniqueIdentifier, li.variant_id || null)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit_price', sql.Decimal(12, 4), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('hsn_code', sql.NVarChar(10), li.hsn_code || null)
          .input('line_total', sql.Decimal(10, 2), li.line_total)
          .input('kitchen_status', sql.NVarChar(20), k.kitchen_status)
          .input('kitchen_done_at', sql.DateTime2, k.kitchen_done_at)
          .query(`
            INSERT INTO bill_items (bill_id, item_id, variant_id, item_name, quantity, unit_price, tax_rate, hsn_code, line_total, kitchen_status, kitchen_done_at)
            VALUES (@bill_id, @item_id, @variant_id, @item_name, @quantity, @unit_price, @tax_rate, @hsn_code, @line_total, @kitchen_status, @kitchen_done_at)
          `);
      }

      // Recalculate totals, and update customer/discount fields when supplied.
      // Discount applies to the NET subtotal; tax is charged on the discounted
      // net (bill-level: rawTax × discountedNet/subtotal). The effective discount
      // for the tax scaling is the one being set now (clamped to the net), or the
      // already-persisted one when the discount isn't part of this edit.
      const totalsReq = transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id);
      const extraSets = [];
      if (setCustomerName) {
        totalsReq.input('customer_name', sql.NVarChar(200), customer_name || null);
        extraSets.push('customer_name = @customer_name');
      }
      if (setCustomerPhone) {
        totalsReq.input('customer_phone', sql.NVarChar(20), customer_phone || null);
        extraSets.push('customer_phone = @customer_phone');
      }
      if (setDiscount) {
        const discountAmount = Math.max(parseFloat(discount_amount) || 0, 0);
        totalsReq.input('discount_amount', sql.Decimal(10, 2), discountAmount);
        // Clamp the incoming discount to the NET subtotal (not gross line total).
        extraSets.push(
          'discount_amount = (SELECT CASE WHEN @discount_amount > SUM(quantity * unit_price) THEN SUM(quantity * unit_price) ELSE @discount_amount END FROM bill_items WHERE bill_id = @id)',
        );
      }
      // `disc` for the tax scaling: the new clamped discount when setting it,
      // otherwise the bill's current discount_amount. Both are clamped to net.
      const discExpr = setDiscount
        ? 'CASE WHEN @discount_amount > agg.sub THEN agg.sub ELSE @discount_amount END'
        : 'CASE WHEN b.discount_amount > agg.sub THEN agg.sub ELSE b.discount_amount END';
      await totalsReq.query(`
          UPDATE b SET
            subtotal   = agg.sub,
            tax_amount = ROUND(agg.raw_tax * (agg.sub - (${discExpr})) / NULLIF(agg.sub, 0), 2),
            total      = agg.sub + ROUND(agg.raw_tax * (agg.sub - (${discExpr})) / NULLIF(agg.sub, 0), 2)${extraSets.length ? ',\n            ' + extraSets.join(',\n            ') : ''}
          FROM bills b
          CROSS APPLY (
            SELECT
              CAST(SUM(bi.quantity * bi.unit_price) AS DECIMAL(18,4)) AS sub,
              CAST(SUM(bi.line_total - bi.quantity * bi.unit_price) AS DECIMAL(18,4)) AS raw_tax
            FROM bill_items bi WHERE bi.bill_id = @id
          ) agg
          WHERE b.id = @id
        `);

      // Re-derive round_off from the fresh total/discount so the final payable
      // stays reconciled after the edit.
      await recomputeRoundOff(transaction, req.params.id, roundOffEnabled);

      // Atomic decrement for new items — final concurrency guard.
      if (inventoryEnabled) {
        for (const li of lineItems) {
          const ok = await decrementLineStock(transaction, req.user.business_id, li, itemMap, variantMap);
          if (!ok) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id, variant_id: li.variant_id }],
            });
          }
          const recipeOk = await decrementRecipe(transaction, li, recipeMap);
          if (!recipeOk) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id }],
            });
          }
        }
      }

      replacementLineItems = lineItems;
      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);

    audit.logBillItemsUpdated(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: bill.bill_number },
      previousLineItems,
      replacementLineItems,
    );

    // Real-time: items/customer changed on a draft — refresh kitchen and the
    // relevant list (tables for a table order, open-orders otherwise).
    broadcast(req.user.business_id, { type: 'kitchen' });
    broadcast(req.user.business_id, { type: bill.table_id ? 'tables' : 'drafts' });

    return res.json(bill);
  } catch (err) {
    if (err instanceof PricelessLineError) {
      return res.status(400).json({ error: err.message });
    }
    logger.error({ err }, 'Update items error');
    return res.status(500).json({ error: 'Failed to update items' });
  }
});

// DELETE /api/bills/:id — void (cashier or owner)
router.delete('/:id', requireAuth, cashierOrOwner, async (req, res) => {
  try {
    await poolConnect;

    const billResult = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.id, b.status, b.table_id, b.bill_number, b.total,
               bs.inventory_enabled
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (billResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }
    const bill = billResult.recordset[0];

    // Quick pre-flight check before acquiring the transaction (saves round-trips
    // for the common case where a bill was already voided).
    if (bill.status === 'voided') {
      return res.status(409).json({ error: 'Bill is already voided' });
    }

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      // Atomic status flip — the WHERE clause is the true concurrency gate.
      // If two void requests race, only one will see rowsAffected = 1;
      // the other gets 0 and is rejected inside the transaction, preventing
      // any stock from being restored twice.
      const voidResult = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`
          UPDATE bills SET status = 'voided'
          WHERE id = @id AND status != 'voided'
        `);

      if (voidResult.rowsAffected[0] === 0) {
        await transaction.rollback();
        return res.status(409).json({ error: 'Bill is already voided' });
      }

      // Restore stock — only runs when the status flip above succeeded,
      // so it is impossible for stock to be restored more than once per bill.
      // Variant lines restore the variant's stock; plain lines the item's.
      if (bill.inventory_enabled) {
        const lineItems = await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .query('SELECT item_id, variant_id, item_name, quantity FROM bill_items WHERE bill_id = @bill_id AND (item_id IS NOT NULL OR variant_id IS NOT NULL)');

        for (const li of lineItems.recordset) {
          await restoreLineStock(transaction, req.user.business_id, li);
        }
      }

      // Free the table
      if (bill.table_id) {
        await transaction.request()
          .input('table_id', sql.UniqueIdentifier, bill.table_id)
          .input('business_id', sql.UniqueIdentifier, req.user.business_id)
          .query(`
            UPDATE tables SET status = 'empty'
            WHERE id = @table_id AND business_id = @business_id
          `);
      }

      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    audit.logBillVoided(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: bill.bill_number, total: bill.total, status: bill.status },
      [],
    );

    // Real-time: a voided order leaves the kitchen queue and frees its table /
    // drops off the open-orders list.
    broadcast(req.user.business_id, { type: 'kitchen' });
    broadcast(req.user.business_id, { type: bill.table_id ? 'tables' : 'drafts' });

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Void bill error');
    return res.status(500).json({ error: 'Failed to void bill' });
  }
});

// POST /api/bills/send-whatsapp
// Sends a receipt link to the customer's WhatsApp.
// Body: { bill_id } — looks up the bill, builds the receipt URL, sends it.
router.post('/send-whatsapp', requireAuth, async (req, res) => {
  const { bill_id } = req.body;

  if (!bill_id) {
    return res.status(400).json({ error: 'bill_id is required' });
  }

  try {
    await poolConnect;
    const row = await pool.request()
      .input('id',          sql.UniqueIdentifier, bill_id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.receipt_token, b.customer_phone, b.bill_number,
               bs.name AS shop_name
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (row.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }

    const { receipt_token, customer_phone, bill_number, shop_name } = row.recordset[0];

    if (!customer_phone) {
      return res.status(400).json({ error: 'This bill has no customer phone number' });
    }
    if (!normalisePhone(customer_phone)) {
      return res.status(400).json({ error: 'Invalid customer phone number' });
    }

    const receiptUrl = `${RECEIPT_BASE}/receipt/${receipt_token}`;
    const result = await sendBillLink({
      phone:      customer_phone,
      shopName:   shop_name,
      billNumber: bill_number,
      receiptUrl,
    });

    if (result.sent) {
      return res.json({ success: true, campaign_id: result.campaignId });
    }
    if (result.skipped) {
      return res.json({ success: false, skipped: true, message: 'WhatsApp sending is disabled' });
    }
    return res.status(500).json({ error: result.error || 'Failed to send WhatsApp message' });
  } catch (err) {
    logger.error({ err }, 'send-whatsapp error');
    return res.status(500).json({ error: 'Failed to send WhatsApp message' });
  }
});

// GET /api/bills/:id/whatsapp-text
// Returns the normalised phone + a prefilled receipt message for opening the
// user's own WhatsApp (wa.me deep link) — no Business-API template needed.
// The receipt base URL and the message wording stay server-side (one source
// of truth), so the app just launches WhatsApp with what we return.
router.get('/:id/whatsapp-text', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const row = await pool.request()
      .input('id',          sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.receipt_token, b.customer_phone, b.bill_number,
               bs.name AS shop_name
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (row.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }

    const { receipt_token, customer_phone, bill_number, shop_name } = row.recordset[0];

    if (!customer_phone) {
      return res.status(400).json({ error: 'This bill has no customer phone number' });
    }
    const phone = normalisePhone(customer_phone);
    if (!phone) {
      return res.status(400).json({ error: 'Invalid customer phone number' });
    }

    const receiptUrl = `${RECEIPT_BASE}/receipt/${receipt_token}`;
    const message =
      `Your bill from ${shop_name} is ready!\n\n` +
      `Bill No: ${bill_number}\n` +
      `View your receipt here: ${receiptUrl}\n\n` +
      `Thank you for shopping with us!`;

    return res.json({ phone, message, receipt_url: receiptUrl });
  } catch (err) {
    logger.error({ err }, 'whatsapp-text error');
    return res.status(500).json({ error: 'Failed to build WhatsApp message' });
  }
});

// POST /api/bills/:id/whatsapp
// Single decision point for sending a receipt over WhatsApp. Reads the
// business's whatsapp_mode:
//   'api'      (paid) — backend sends the Business-API template itself and
//                       returns { mode:'api', sent:true }. On failure it
//                       reports the error (NO fallback — paid tier is API-only).
//   'deeplink' (free) — returns { mode:'deeplink', phone, message } so the app
//                       opens the cashier's own WhatsApp with a prefilled text.
router.post('/:id/whatsapp', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const row = await pool.request()
      .input('id',          sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.receipt_token, b.customer_phone, b.bill_number,
               bs.name AS shop_name, bs.whatsapp_mode
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (row.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }

    const { receipt_token, customer_phone, bill_number, shop_name, whatsapp_mode } =
      row.recordset[0];

    if (!customer_phone) {
      return res.status(400).json({ error: 'This bill has no customer phone number' });
    }
    const phone = normalisePhone(customer_phone);
    if (!phone) {
      return res.status(400).json({ error: 'Invalid customer phone number' });
    }

    const receiptUrl = `${RECEIPT_BASE}/receipt/${receipt_token}`;
    const message =
      `Your bill from ${shop_name} is ready!\n\n` +
      `Bill No: ${bill_number}\n` +
      `View your receipt here: ${receiptUrl}\n\n` +
      `Thank you for shopping with us!`;

    // Paid: send via the Business API. Report failure; no deeplink fallback.
    if (whatsapp_mode === 'api') {
      const result = await sendBillLink({
        phone: customer_phone,
        shopName: shop_name,
        billNumber: bill_number,
        receiptUrl,
      });
      if (result.sent) {
        return res.json({ mode: 'api', sent: true, campaign_id: result.campaignId });
      }
      if (result.skipped) {
        return res.status(503).json({
          mode: 'api',
          sent: false,
          error: 'WhatsApp API sending is disabled',
        });
      }
      return res.status(502).json({
        mode: 'api',
        sent: false,
        error: result.error || 'Failed to send WhatsApp message',
      });
    }

    // Free: hand the app the phone + message to open WhatsApp itself.
    return res.json({ mode: 'deeplink', phone, message, receipt_url: receiptUrl });
  } catch (err) {
    logger.error({ err }, 'whatsapp send error');
    return res.status(500).json({ error: 'Failed to send WhatsApp message' });
  }
});

// Receipt page — see routes/receipt.js (mounted at /receipt in server.js)

module.exports = router;
