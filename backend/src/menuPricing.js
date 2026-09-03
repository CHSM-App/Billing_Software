'use strict';
// =============================================================================
// Server-side pricing for customer-placed orders (table QR menu + online store).
//
// The one rule both public ordering flows share: the client's price is NEVER
// trusted. A browser can post any number it likes, so every line is re-priced
// here from the live `items` / `item_variants` rows before it is written
// anywhere. This lives in its own module because BOTH public routes need
// byte-identical behaviour — a mispriced line becomes a wrong bill, and two
// copies of this logic would drift the first time one of them was touched.
// =============================================================================

const { pool, sql } = require('./db');
const { netUnitPrice } = require('./money');

const MAX_LINE_QTY = 50;        // per-line sanity cap
const MAX_LINES_PER_ORDER = 40; // per-order sanity cap

/**
 * Validate + normalise the raw `items` array from a request body.
 *
 * Cheap and synchronous, so callers run it BEFORE opening a transaction.
 *
 * @param {unknown} items  raw `req.body.items`
 * @returns {{ lines: Array<{item_id, variant_id, quantity}> } | { error: string }}
 */
function cleanLines(items) {
  if (!Array.isArray(items) || items.length === 0) {
    return { error: 'items array is required' };
  }
  if (items.length > MAX_LINES_PER_ORDER) {
    return { error: 'Too many items in one order' };
  }
  const lines = [];
  for (const li of items) {
    const qty = Number(li && li.quantity);
    if (!li || !li.item_id || !Number.isFinite(qty) || qty <= 0 || qty > MAX_LINE_QTY) {
      return { error: 'Invalid item or quantity' };
    }
    lines.push({ item_id: li.item_id, variant_id: li.variant_id || null, quantity: qty });
  }
  return { lines };
}

/**
 * Price cleaned lines from the current catalog.
 *
 * @param {() => object} makeRequest  yields a fresh mssql Request — pass
 *        `() => transaction.request()` inside a transaction, or omit to use the
 *        pool. Each query needs its own request (parameter names collide).
 * @param {string} businessId
 * @param {Array<{item_id, variant_id, quantity}>} lines  from [cleanLines]
 * @returns {Promise<Array<{item_id, variant_id, item_name, quantity, unit_price,
 *          tax_rate, line_total}>>}
 * @throws {{httpStatus: 400, message: string}} when an item or variant has since
 *         been deactivated — thrown, not returned, so a caller inside a
 *         transaction unwinds through its existing rollback path.
 */
async function priceLines(makeRequest, businessId, lines) {
  const request = makeRequest || (() => pool.request());

  // Active items only, scoped to this business.
  const itemIds = [...new Set(lines.map((l) => l.item_id))];
  const inNames = itemIds.map((_, i) => `@it${i}`);
  const priceReq = request().input('business_id', sql.UniqueIdentifier, businessId);
  itemIds.forEach((id, i) => priceReq.input(`it${i}`, sql.UniqueIdentifier, id));
  const priceResult = await priceReq.query(`
    SELECT id, name, price, tax_rate, price_inclusive_tax
    FROM items
    WHERE business_id = @business_id AND is_active = 1 AND id IN (${inNames.join(',')})
  `);
  const itemMap = {};
  for (const r of priceResult.recordset) itemMap[r.id] = r;

  // Which of these items are sold ONLY through a size? An item with active
  // variants has no sellable base price — items.price is nullable exactly for
  // that case — so a line that names one without a variant_id cannot be priced.
  // The staff biller already refuses this (findMissingVariantError in
  // routes/bills.js); without the same check here a customer could post a
  // sized item with no size and be charged the NULL base price as zero.
  const sizedItemIds = new Set();
  const sizedFor = lines.filter((l) => !l.variant_id).map((l) => l.item_id);
  if (sizedFor.length > 0) {
    const ids = [...new Set(sizedFor)];
    const sNames = ids.map((_, i) => `@sz${i}`);
    const sReq = request();
    ids.forEach((id, i) => sReq.input(`sz${i}`, sql.UniqueIdentifier, id));
    const sResult = await sReq.query(`
      SELECT DISTINCT item_id FROM item_variants
      WHERE is_active = 1 AND item_id IN (${sNames.join(',')})
    `);
    for (const r of sResult.recordset) sizedItemIds.add(r.item_id);
  }

  // Variants are joined back to items so a variant id from ANOTHER business
  // cannot be attached to one of this business's items.
  const variantIds = [...new Set(lines.map((l) => l.variant_id).filter(Boolean))];
  const variantMap = {};
  if (variantIds.length > 0) {
    const vNames = variantIds.map((_, i) => `@vr${i}`);
    const vReq = request().input('business_id', sql.UniqueIdentifier, businessId);
    variantIds.forEach((id, i) => vReq.input(`vr${i}`, sql.UniqueIdentifier, id));
    const vResult = await vReq.query(`
      SELECT v.id, v.item_id, v.label, v.price
      FROM item_variants v
      JOIN items i ON i.id = v.item_id
      WHERE i.business_id = @business_id AND v.is_active = 1 AND v.id IN (${vNames.join(',')})
    `);
    for (const r of vResult.recordset) variantMap[r.id] = r;
  }

  const priced = [];
  for (const l of lines) {
    const item = itemMap[l.item_id];
    if (!item) throw { httpStatus: 400, message: 'An item is no longer available' };

    // A sized item MUST arrive with a size. The page hides the Add button until
    // one is picked, but the page is a browser: a stale tab, a double-tap during
    // a menu reload, or anyone typing into devtools can still post the bare
    // item — and its base price is NULL, which would silently bill as zero.
    if (!l.variant_id && sizedItemIds.has(l.item_id)) {
      throw { httpStatus: 400, code: 'size_required',
              message: `Please choose a size for ${item.name}.` };
    }
    // Belt and braces for a catalog left half-edited: an item with no price and
    // no sizes cannot be sold at all, and must never fall through as zero.
    if (item.price == null && !l.variant_id) {
      throw { httpStatus: 400, message: `${item.name} is not available right now.` };
    }

    let unitPrice = Number(item.price);
    let itemName = item.name;
    if (l.variant_id) {
      const v = variantMap[l.variant_id];
      if (!v || v.item_id !== item.id) {
        throw { httpStatus: 400, message: 'A selected option is no longer available' };
      }
      if (v.price != null) unitPrice = Number(v.price);
      itemName = `${item.name} (${v.label})`;
    }
    // An MRP-priced item quotes its price GST-inclusive, so strip the tax to get
    // the net rate the line must store. bill_items.unit_price is net everywhere
    // (see resolveNetPriceAndRate in routes/bills.js) and subtotals are summed
    // straight from these lines — storing the gross rate here would show the
    // customer a subtotal that grew again once staff finalized the bill.
    unitPrice = netUnitPrice(
      unitPrice,
      item.tax_rate,
      item.price_inclusive_tax === true || item.price_inclusive_tax === 1,
    );
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
  return priced;
}

module.exports = { cleanLines, priceLines, MAX_LINE_QTY, MAX_LINES_PER_ORDER };
