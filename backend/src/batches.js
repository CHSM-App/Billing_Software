// Stock batches (migration 044).
//
// items.stock_quantity / item_variants.stock_quantity stay the TOTAL and the
// source of truth. Batches split that total by purchase:
//
//   opening stock = stock_quantity - SUM(stock_batches.qty_remaining)
//
// Opening stock is whatever existed before batches, or was added by hand; it
// has no known cost. Every function here keeps opening >= 0 — trimExcess is the
// one place that restores it after the total drops without naming a batch.
//
// All functions take an open mssql transaction (trimExcess also accepts the
// pool, for the non-transactional manual stock edit in routes/items.js).

const { sql } = require('./db');

// Quantities are DECIMAL(10,2); work in hundredths so 0.1 + 0.2 stays exact.
const toCents = (n) => Math.round(Number(n) * 100);

/**
 * Which batches to shrink, oldest first, to remove [excess] units. Pure.
 * [batches] must already be ordered oldest first.
 * Returns [{ id, take }] — never takes more than a batch holds.
 */
function trimPlan(excess, batches) {
  let left = toCents(excess);
  const out = [];
  for (const b of batches) {
    if (left <= 0) break;
    const take = Math.min(left, toCents(b.qty_remaining));
    if (take > 0) {
      out.push({ id: b.id, take: take / 100 });
      left -= take;
    }
  }
  return out;
}

// A line targets its size when it has one, otherwise the item itself — the
// same rule decrementLineStock follows for the stock total.
function targetOf(li) {
  return li.variant_id
    ? { col: 'variant_id', table: 'item_variants', id: li.variant_id }
    : { col: 'item_id', table: 'items', id: li.item_id };
}

/**
 * Create one batch per purchase line that receives a tracked item or size.
 * [costFactor] spreads the vendor's bill-level discount over the lines:
 * (subtotal - discount) / subtotal.
 */
async function receiveBatches(tx, businessId, vendorBillId, receivedDate, lines, costFactor) {
  for (const li of lines) {
    if (!li.item_id && !li.variant_id) continue; // raw material / freight line
    const t = targetOf(li);
    await tx.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('item_id', sql.UniqueIdentifier, li.variant_id ? null : li.item_id)
      .input('variant_id', sql.UniqueIdentifier, li.variant_id || null)
      .input('target_id', sql.UniqueIdentifier, t.id)
      .input('vendor_bill_id', sql.UniqueIdentifier, vendorBillId)
      .input('batch_no', sql.NVarChar(50), li.batch_no || null)
      .input('unit_cost', sql.Decimal(12, 4), Number(li.unit_price) * costFactor)
      .input('qty', sql.Decimal(10, 2), li.quantity)
      .input('received_date', sql.Date, receivedDate)
      // Untracked stock (NULL) gets no batch — receiving must not opt it in.
      .query(`
        INSERT INTO stock_batches (business_id, item_id, variant_id, vendor_bill_id,
          batch_no, unit_cost, qty_received, qty_remaining, received_date)
        SELECT @business_id, @item_id, @variant_id, @vendor_bill_id,
          @batch_no, @unit_cost, @qty, @qty, @received_date
        WHERE EXISTS (SELECT 1 FROM ${t.table}
                      WHERE id = @target_id AND stock_quantity IS NOT NULL)`);
  }
}

/** Drop every batch a purchase created. Sold lines keep their cost snapshot. */
async function removeBillBatches(tx, vendorBillId) {
  await tx.request()
    .input('vendor_bill_id', sql.UniqueIdentifier, vendorBillId)
    .query('DELETE FROM stock_batches WHERE vendor_bill_id = @vendor_bill_id');
}

/** Take a sale line's quantity out of its chosen batch. False when it's short. */
async function takeFromBatch(tx, li) {
  const r = await tx.request()
    .input('id', sql.UniqueIdentifier, li.batch_id)
    .input('qty', sql.Decimal(10, 2), li.quantity)
    .query(`UPDATE stock_batches SET qty_remaining = qty_remaining - @qty
            WHERE id = @id AND qty_remaining >= @qty`);
  return r.rowsAffected[0] > 0;
}

/**
 * Put a voided/replaced line's quantity back into its batch. A batch deleted
 * since (its purchase was removed) matches nothing, so the quantity simply
 * stays in the total as opening stock.
 */
async function returnToBatch(tx, li) {
  if (!li.batch_id) return;
  await tx.request()
    .input('id', sql.UniqueIdentifier, li.batch_id)
    .input('qty', sql.Decimal(10, 2), li.quantity)
    .query('UPDATE stock_batches SET qty_remaining = qty_remaining + @qty WHERE id = @id');
}

/**
 * Shrink batches, oldest first, until they no longer exceed the stock total.
 * Called whenever the total drops without naming a batch: a manual stock
 * edit, a purchase edited/deleted, or a sale line with no batch.
 *
 * ponytail: a line with no batch (older app, QR/online order) that sells past
 * the opening stock drains the oldest batch here and is recorded without a
 * cost. Send batch_id from every client if that gap starts to matter.
 */
async function trimExcess(tx, businessId, li) {
  if (!li.item_id && !li.variant_id) return;
  const t = targetOf(li);
  const r = await tx.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('target_id', sql.UniqueIdentifier, t.id)
    .query(`
      SELECT b.id, b.qty_remaining,
             (SELECT stock_quantity FROM ${t.table} WHERE id = @target_id) AS stock
      FROM stock_batches b WITH (UPDLOCK)
      WHERE b.business_id = @business_id AND b.${t.col} = @target_id
        AND b.qty_remaining > 0
      ORDER BY b.received_date, b.created_at`);
  const rows = r.recordset;
  if (rows.length === 0 || rows[0].stock == null) return;
  const held = rows.reduce((s, b) => s + toCents(b.qty_remaining), 0);
  const excess = (held - Math.max(toCents(rows[0].stock), 0)) / 100;
  if (excess <= 0) return;
  for (const p of trimPlan(excess, rows)) {
    await tx.request()
      .input('id', sql.UniqueIdentifier, p.id)
      .input('qty', sql.Decimal(10, 2), p.take)
      .query('UPDATE stock_batches SET qty_remaining = qty_remaining - @qty WHERE id = @id');
  }
}

/**
 * Load the batches named by incoming bill lines and check each belongs to the
 * line's own item/size in this business. Returns { map, error }.
 */
async function loadBatchMap(tx, businessId, items) {
  const ids = [...new Set(items.map((i) => i.batch_id).filter(Boolean))];
  if (ids.length === 0) return { map: {}, error: null };
  const req = tx.request().input('business_id', sql.UniqueIdentifier, businessId);
  ids.forEach((id, i) => req.input(`b${i}`, sql.UniqueIdentifier, id));
  const r = await req.query(`
    SELECT id, item_id, variant_id, batch_no, unit_cost, qty_remaining
    FROM stock_batches
    WHERE business_id = @business_id AND id IN (${ids.map((_, i) => `@b${i}`).join(',')})`);
  // Keyed lowercase: mssql returns GUIDs uppercase, clients may send either.
  const map = {};
  for (const row of r.recordset) map[String(row.id).toLowerCase()] = row;
  const bad = items.find((i) => {
    if (!i.batch_id) return false;
    const b = map[String(i.batch_id).toLowerCase()];
    if (!b) return true;
    return i.variant_id
      ? String(b.variant_id).toLowerCase() !== String(i.variant_id).toLowerCase()
      : String(b.item_id).toLowerCase() !== String(i.item_id).toLowerCase();
  });
  return { map, error: bad ? `Batch not found: ${bad.batch_id}` : null };
}

/** The batch columns for one incoming bill line — nulls when no batch applies. */
function batchFields(i, batchMap) {
  const b = batchMap && i.batch_id ? batchMap[String(i.batch_id).toLowerCase()] : null;
  return {
    batch_id: b ? b.id : null,
    batch_no: b ? b.batch_no : null,
    unit_cost: b ? b.unit_cost : null,
  };
}

module.exports = {
  trimPlan,
  receiveBatches,
  removeBillBatches,
  takeFromBatch,
  returnToBatch,
  trimExcess,
  loadBatchMap,
  batchFields,
};
