// Stock batches (migrations 079, 080) — purchase cost per lot, so reports can show
// real profit.
//
// items.stock_quantity / item_variants.stock_quantity stay the TOTAL and the
// source of truth. Batches only split that total by purchase:
//
//   opening stock = stock_quantity - SUM(open qty_remaining)
//
// Opening stock existed before batches (or was added by hand). It is the
// oldest stock, so a sale takes it first — after the cashier's pick, if any —
// then batches oldest first (true oldest-first). Opening stock is costed at
// the purchase average or the item's buying price (stockLedger.snapshotBillCosts).
//
// Only shops with "Maintain batches" on (businesses.batch_tracking_enabled)
// CREATE batch data: receive, allocate, trimExcess. Reversals (unreceive,
// returnBill) run whenever the rows carry batch data, so a shop that switched
// it off keeps a consistent history; reconcile tidies up when it comes back.
//
// Functions take an open mssql transaction, or a request factory where they
// also run outside one (the manual stock edit in routes/items.js).

const { sql } = require('./db');

// Quantities are DECIMAL(10,2); work in hundredths so 0.1 + 0.2 stays exact.
const toCents = (n) => Math.round(Number(n) * 100);
const r4 = (n) => Math.round(Number(n) * 10000) / 10000;

/** mssql returns GUIDs upper-case; clients may send either. */
const sameId = (a, b) => !!a && !!b && String(a).toLowerCase() === String(b).toLowerCase();

/** B-0001 — a purchase's automatic batch no. when none is typed. */
const batchCode = (seq) => `B-${String(seq).padStart(4, '0')}`;

/** A line's stock target: its size when it has one, else the item. */
function targetOf(li) {
  if (li.variant_id) return { col: 'variant_id', table: 'item_variants', id: li.variant_id };
  if (li.item_id) return { col: 'item_id', table: 'items', id: li.item_id };
  return null; // raw material or a freight/service line: never batched
}

/**
 * Cost of one received unit. [line] is a computeTotals line (vendorBillMath):
 * `_net` / `_tax` are its pre-bill-discount net and GST. [costFactor] spreads
 * the vendor's bill discount: (subtotal - discount) / subtotal. GST counts as
 * cost only when it can't be claimed back. Free goods lower every unit's cost.
 */
function unitCost(line, costFactor, gstIsCost) {
  const units = Number(line.quantity) + (Number(line.free_quantity) || 0);
  if (!(units > 0)) return 0;
  const paid = line._net * costFactor + (gstIsCost ? line._tax * costFactor : 0);
  return r4(paid / units);
}

/**
 * Which batches to take [qty] from: [preferredId] first, then [openingQty] of
 * opening stock (the oldest, no batch), then the rest in the order given
 * (oldest first), never more than a batch holds. Pure. Anything still left is
 * opening stock too. Returns the batch takes only: [{ id, take }].
 */
function fifoPlan(qty, batches, preferredId, openingQty = 0) {
  const picked = preferredId ? batches.filter((b) => sameId(b.id, preferredId)) : [];
  const rest = preferredId ? batches.filter((b) => !sameId(b.id, preferredId)) : batches;
  let left = toCents(qty);
  const out = [];
  const takeFrom = (list) => {
    for (const b of list) {
      if (left <= 0) break;
      const take = Math.min(left, toCents(b.qty_remaining));
      if (take > 0) {
        out.push({ id: b.id, take: take / 100 });
        left -= take;
      }
    }
  };
  takeFrom(picked);
  left -= Math.min(left, Math.max(toCents(openingQty), 0));
  takeFrom(rest);
  return out;
}

/** A target's open batches, oldest first, locked when [lock]. */
async function openBatches(request, businessId, t, lock) {
  const r = await request
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('target_id', sql.UniqueIdentifier, t.id)
    .query(`SELECT id, qty_remaining FROM stock_batches ${lock ? 'WITH (UPDLOCK)' : ''}
            WHERE business_id = @business_id AND ${t.col} = @target_id
              AND qty_remaining > 0
            ORDER BY received_date, created_at`);
  return r.recordset;
}

/** A typed batch no., trimmed to its column, or null for "automatic". */
const typedNo = (v) => {
  const s = v == null ? '' : String(v).trim().slice(0, 50);
  return s || null;
};

/**
 * Put each purchase line of a tracked item/size into a batch: the one it names
 * (a top-up — same item, same unit cost) or a new one. [lines] are
 * computeTotals lines carrying batch_id / batch_no.
 *
 * A batch no. names the delivery, not the line: every new batch of one
 * purchase shares it (migration 080). A typed batch_no is used as given;
 * otherwise the purchase gets one automatic "B-0007", the number it already
 * has on an edit. A batch this bill opened itself takes the edited cost (so a
 * corrected rate reaches past sales too) and the edited batch no.
 * Returns { ids } (a batch id or null per line) or { error } for a 400.
 */
async function receive(tx, businessId, vendorBillId, receivedDate, lines,
  { costFactor, gstIsCost, prevBatchIds }) {
  const ids = [];
  // Own batches whose cost this edit corrected: their past sales get re-costed.
  const recosted = [];
  let auto = null;
  const autoNo = async () => {
    if (auto) return auto;
    const kept = await tx.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('vendor_bill_id', sql.UniqueIdentifier, vendorBillId)
      .query(`SELECT TOP 1 batch_seq FROM stock_batches
              WHERE business_id = @business_id
                AND created_by_vendor_bill_id = @vendor_bill_id AND batch_seq IS NOT NULL`);
    let seq = kept.recordset[0]?.batch_seq;
    if (seq == null) {
      // HOLDLOCK keeps two saves from taking one number.
      const next = await tx.request()
        .input('business_id', sql.UniqueIdentifier, businessId)
        .query(`SELECT ISNULL(MAX(batch_seq), 0) + 1 AS seq
                FROM stock_batches WITH (UPDLOCK, HOLDLOCK)
                WHERE business_id = @business_id`);
      seq = next.recordset[0].seq;
    }
    auto = { seq, no: batchCode(seq) };
    return auto;
  };
  const codeFor = async (li) => {
    const typed = typedNo(li.batch_no);
    return typed ? { seq: null, no: typed } : autoNo();
  };

  for (let i = 0; i < lines.length; i++) {
    const li = lines[i];
    const t = targetOf(li);
    if (!t) { ids.push(null); continue; }
    // Untracked stock (NULL) gets no batch — receiving must not opt it in.
    const tracked = await tx.request()
      .input('id', sql.UniqueIdentifier, t.id)
      .query(`SELECT stock_quantity FROM ${t.table} WHERE id = @id`);
    if (tracked.recordset[0]?.stock_quantity == null) { ids.push(null); continue; }

    const qty = Number(li.quantity) + (Number(li.free_quantity) || 0);
    const cost = unitCost(li, costFactor, gstIsCost);

    // Set when an edited line must leave its (shared) batch for a new one
    // under the same batch no. — see the rate split below.
    let forced = null;
    if (li.batch_id) {
      const r = await tx.request()
        .input('id', sql.UniqueIdentifier, li.batch_id)
        .input('business_id', sql.UniqueIdentifier, businessId)
        .query(`SELECT id, item_id, variant_id, unit_cost, batch_no, batch_seq,
                       created_by_vendor_bill_id, qty_received, qty_sold, qty_lost
                FROM stock_batches WITH (UPDLOCK)
                WHERE id = @id AND business_id = @business_id`);
      const b = r.recordset[0];
      if (!b || !sameId(b[t.col], t.id)) {
        return { error: `Line ${i + 1}: that batch is not for this item` };
      }
      const own = sameId(b.created_by_vendor_bill_id, vendorBillId);
      const rateDiffers = Math.abs(Number(b.unit_cost) - cost) >= 0.01;
      // A line this purchase already had in another purchase's batch, edited
      // to a new rate: it moves to its own batch under the same batch no.,
      // so the correction saves. Units sold before keep the old batch's cost.
      if (!own && rateDiffers && (prevBatchIds || new Set()).has(String(b.id).toLowerCase())) {
        forced = { seq: b.batch_seq ?? null, no: b.batch_no };
      } else {
        if (!own && rateDiffers) {
          return {
            error: `Line ${i + 1}: rate differs from batch ${b.batch_no} `
              + `(Rs. ${Number(b.unit_cost).toFixed(2)} per unit). Save it as a new batch.`,
          };
        }
        // What was already sold or written off from this batch must still be
        // covered once the edit is saved.
        const out = Number(b.qty_sold) + Number(b.qty_lost);
        if (Number(b.qty_received) + qty < out - 0.001) {
          return {
            error: `Line ${i + 1}: ${out} already sold from batch ${b.batch_no}; `
              + `the quantity can't go below that.`,
          };
        }
        // This purchase's own batches follow its edited cost, and its batch
        // no. when one is typed — a blank one keeps the name it has.
        const code = own && typedNo(li.batch_no) ? await codeFor(li) : null;
        if (own && Math.abs(Number(b.unit_cost) - cost) >= 0.0001) recosted.push(b.id);
        await tx.request()
          .input('id', sql.UniqueIdentifier, b.id)
          .input('qty', sql.Decimal(10, 2), qty)
          .input('unit_cost', sql.Decimal(12, 4), cost)
          .input('batch_no', sql.NVarChar(50), code?.no ?? null)
          .input('batch_seq', sql.Int, code?.seq ?? null)
          .query(`UPDATE stock_batches SET qty_received = qty_received + @qty
                  ${own ? ', unit_cost = @unit_cost' : ''}
                  ${code ? ', batch_no = @batch_no, batch_seq = @batch_seq' : ''}
                  WHERE id = @id`);
        ids.push(b.id);
        continue;
      }
    }

    const code = forced || await codeFor(li);
    // Same item, same batch no., same rate: the stock joins that batch rather
    // than opening a second one under the same name.
    const same = await tx.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('target_id', sql.UniqueIdentifier, t.id)
      .input('batch_no', sql.NVarChar(50), code.no)
      .input('unit_cost', sql.Decimal(12, 4), cost)
      .query(`SELECT TOP 1 id FROM stock_batches WITH (UPDLOCK)
              WHERE business_id = @business_id AND ${t.col} = @target_id
                AND batch_no = @batch_no AND ABS(unit_cost - @unit_cost) < 0.01
              ORDER BY created_at DESC`);
    if (same.recordset.length) {
      await tx.request()
        .input('id', sql.UniqueIdentifier, same.recordset[0].id)
        .input('qty', sql.Decimal(10, 2), qty)
        .query('UPDATE stock_batches SET qty_received = qty_received + @qty WHERE id = @id');
      ids.push(same.recordset[0].id);
      continue;
    }
    const ins = await tx.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('item_id', sql.UniqueIdentifier, li.variant_id ? null : li.item_id)
      .input('variant_id', sql.UniqueIdentifier, li.variant_id || null)
      .input('batch_seq', sql.Int, code.seq)
      .input('batch_no', sql.NVarChar(50), code.no)
      .input('unit_cost', sql.Decimal(12, 4), cost)
      .input('received_date', sql.Date, receivedDate)
      .input('vendor_bill_id', sql.UniqueIdentifier, vendorBillId)
      .input('qty', sql.Decimal(10, 2), qty)
      .query(`INSERT INTO stock_batches (business_id, item_id, variant_id, batch_seq,
                batch_no, unit_cost, received_date, created_by_vendor_bill_id, qty_received)
              OUTPUT INSERTED.id
              VALUES (@business_id, @item_id, @variant_id, @batch_seq,
                @batch_no, @unit_cost, @received_date, @vendor_bill_id, @qty)`);
    ids.push(ins.recordset[0].id);
  }
  return { ids, recosted };
}

/**
 * A batch's cost was corrected: clear and re-take the cost snapshot of every
 * sale line that took from it, so profit follows the corrected rate.
 */
async function recostBatches(tx, businessId, batchIds, snapshotBillCosts) {
  for (const id of batchIds) {
    const bills = await tx.request()
      .input('batch_id', sql.UniqueIdentifier, id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`UPDATE bi SET bi.unit_cost = NULL
              OUTPUT INSERTED.bill_id
              FROM bill_items bi
              WHERE EXISTS (SELECT 1 FROM stock_batch_allocations a
                            WHERE a.batch_id = @batch_id AND a.business_id = @business_id
                              AND a.bill_id = bi.bill_id AND a.item_id = bi.item_id
                              AND ((a.variant_id IS NULL AND bi.variant_id IS NULL)
                                   OR a.variant_id = bi.variant_id))`);
    const billIds = [...new Set(bills.recordset.map((r) => String(r.bill_id).toLowerCase()))];
    for (const billId of billIds) await snapshotBillCosts(tx, businessId, billId);
  }
}

/** Take back what a purchase's lines put into their batches (edit/delete). */
async function unreceive(tx, businessId, lines) {
  for (const li of lines) {
    if (!li.batch_id) continue;
    await tx.request()
      .input('id', sql.UniqueIdentifier, li.batch_id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('qty', sql.Decimal(10, 2), Number(li.quantity) + (Number(li.free_quantity) || 0))
      .query(`UPDATE stock_batches SET qty_received = qty_received - @qty
              WHERE id = @id AND business_id = @business_id`);
  }
}

/**
 * Delete batches left holding nothing that nothing was sold from. Run after
 * the re-receive on an edit, so a line that keeps its batch keeps its id. A
 * batch with sales stays, as the history of what those sales cost.
 */
async function dropEmpty(tx, businessId, batchIds) {
  const ids = [...new Set(batchIds.filter(Boolean).map((id) => String(id).toLowerCase()))];
  for (const id of ids) {
    await tx.request()
      .input('id', sql.UniqueIdentifier, id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`DELETE FROM stock_batches
              WHERE id = @id AND business_id = @business_id
                AND qty_received <= 0 AND qty_sold = 0`);
  }
}

/**
 * Record which batches a sale line took its stock from. Call after the line's
 * stock total was decremented. Never fails a sale: a missing, foreign or short
 * preferred batch just falls back to oldest first, and stock beyond all
 * batches comes from opening (uncosted) stock.
 */
async function allocate(tx, businessId, billId, li) {
  const t = targetOf(li);
  if (!t) return;
  const rows = await openBatches(tx.request(), businessId, t, true);
  if (!rows.length) return; // no batches: nothing to allocate
  // Opening before this sale = stock now + what this line just took − what
  // the batches hold. It sells first (it is the oldest).
  const s = await tx.request()
    .input('id', sql.UniqueIdentifier, t.id)
    .query(`SELECT stock_quantity FROM ${t.table} WHERE id = @id`);
  const held = rows.reduce((sum, b) => sum + toCents(b.qty_remaining), 0);
  const opening = Math.max(toCents(s.recordset[0]?.stock_quantity ?? 0) + toCents(li.quantity) - held, 0) / 100;
  for (const p of fifoPlan(li.quantity, rows, li.batch_id, opening)) {
    await tx.request()
      .input('id', sql.UniqueIdentifier, p.id)
      .input('qty', sql.Decimal(10, 2), p.take)
      .query('UPDATE stock_batches SET qty_sold = qty_sold + @qty WHERE id = @id');
    await tx.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('bill_id', sql.UniqueIdentifier, billId)
      .input('batch_id', sql.UniqueIdentifier, p.id)
      .input('item_id', sql.UniqueIdentifier, li.item_id || null)
      .input('variant_id', sql.UniqueIdentifier, li.variant_id || null)
      .input('qty', sql.Decimal(10, 2), p.take)
      .query(`INSERT INTO stock_batch_allocations
                (business_id, bill_id, batch_id, item_id, variant_id, quantity)
              VALUES (@business_id, @bill_id, @batch_id, @item_id, @variant_id, @qty)`);
  }
}

/**
 * Part of a sale line came back (a sales return): give [qty] back to the
 * batches this bill took it from, newest first. Whatever the bill took from
 * old stock simply stays in the stock total (no batch to give it to).
 */
async function returnPart(tx, businessId, billId, li, qty) {
  const t = targetOf(li);
  if (!t) return;
  const rows = (await tx.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('bill_id', sql.UniqueIdentifier, billId)
    .input('item_id', sql.UniqueIdentifier, li.item_id || null)
    .input('variant_id', sql.UniqueIdentifier, li.variant_id || null)
    .query(`SELECT a.id, a.batch_id, a.quantity
            FROM stock_batch_allocations a
            JOIN stock_batches sb ON sb.id = a.batch_id
            WHERE a.bill_id = @bill_id AND a.business_id = @business_id
              AND a.item_id = @item_id
              AND ((@variant_id IS NULL AND a.variant_id IS NULL) OR a.variant_id = @variant_id)
            ORDER BY sb.received_date DESC, sb.created_at DESC`)).recordset;
  let left = toCents(qty);
  for (const a of rows) {
    if (left <= 0) break;
    const take = Math.min(left, toCents(a.quantity));
    if (take <= 0) continue;
    await tx.request()
      .input('id', sql.UniqueIdentifier, a.batch_id)
      .input('qty', sql.Decimal(10, 2), take / 100)
      .query('UPDATE stock_batches SET qty_sold = qty_sold - @qty WHERE id = @id');
    await tx.request()
      .input('id', sql.UniqueIdentifier, a.id)
      .input('qty', sql.Decimal(10, 2), take / 100)
      .query(take === toCents(a.quantity)
        ? 'DELETE FROM stock_batch_allocations WHERE id = @id'
        : 'UPDATE stock_batch_allocations SET quantity = quantity - @qty WHERE id = @id');
    left -= take;
  }
}

/** Give back everything a bill took from batches (void, or before re-saving its lines). */
async function returnBill(tx, businessId, billId) {
  await tx.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('bill_id', sql.UniqueIdentifier, billId)
    .query(`UPDATE b SET b.qty_sold = b.qty_sold - a.qty
            FROM stock_batches b
            INNER JOIN (SELECT batch_id, SUM(quantity) AS qty
                        FROM stock_batch_allocations
                        WHERE bill_id = @bill_id AND business_id = @business_id
                        GROUP BY batch_id) a ON a.batch_id = b.id
            WHERE b.business_id = @business_id`);
  await tx.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('bill_id', sql.UniqueIdentifier, billId)
    .query(`DELETE FROM stock_batch_allocations
            WHERE bill_id = @bill_id AND business_id = @business_id`);
}

/**
 * Batches may never hold more than the stock total. When the total dropped
 * without a sale naming batches (a manual stock correction, a purchase edited
 * or deleted), write the difference off the oldest batches. Untracked (NULL)
 * stock closes every batch of the target.
 */
async function trimExcess(newRequest, businessId, li, reason = 'lost', asZero = false) {
  const t = targetOf(li);
  if (!t) return;
  const rows = await openBatches(newRequest(), businessId, t, true);
  if (!rows.length) return;
  const s = await newRequest()
    .input('id', sql.UniqueIdentifier, t.id)
    .query(`SELECT stock_quantity FROM ${t.table} WHERE id = @id`);
  const stock = asZero ? 0 : Math.max(Number(s.recordset[0]?.stock_quantity ?? 0), 0);
  const held = rows.reduce((sum, b) => sum + toCents(b.qty_remaining), 0);
  const excess = (held - toCents(stock)) / 100;
  if (excess <= 0) return;
  for (const p of fifoPlan(excess, rows)) {
    await newRequest()
      .input('id', sql.UniqueIdentifier, p.id)
      .input('qty', sql.Decimal(10, 2), p.take)
      // 'lost' is a real write-off (stock corrected down); 'closed' is stock
      // that just stopped being tracked here — never counted as a loss.
      .query(`UPDATE stock_batches SET ${reason === 'closed' ? 'qty_closed = qty_closed' : 'qty_lost = qty_lost'} + @qty WHERE id = @id`);
  }
}

// ponytail: one trimExcess per target with open batches; a set-based UPDATE if
// a shop's batch count ever makes switching on slow.
/** Trim every target's batches to its stock — run when batches are switched on. */
async function reconcile(newRequest, businessId) {
  const r = await newRequest()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT DISTINCT item_id, variant_id FROM stock_batches
            WHERE business_id = @business_id AND qty_remaining > 0`);
  for (const row of r.recordset) {
    // Batches gone stale while switched off were sold, not lost.
    await trimExcess(newRequest, businessId, row, 'closed');
  }
}

/**
 * Open batches per item and per size, oldest first, for the item list the
 * billing screen loads — only while the shop maintains batches (with it off
 * this matches nothing, so the list is exactly as before).
 * Returns Map(lower-case target id -> [batch]).
 */
async function openBatchesByTarget(request, businessId) {
  const r = await request
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT sb.id, sb.item_id, sb.variant_id, sb.batch_no,
                   sb.unit_cost, sb.qty_remaining
            FROM stock_batches sb
            INNER JOIN businesses b ON b.id = sb.business_id
              AND b.batch_tracking_enabled = 1 AND b.inventory_enabled = 1
            WHERE sb.business_id = @business_id AND sb.qty_remaining > 0
            ORDER BY sb.received_date, sb.created_at`);
  const map = new Map();
  for (const b of r.recordset) {
    const key = String(b.variant_id || b.item_id).toLowerCase();
    if (!map.has(key)) map.set(key, []);
    map.get(key).push({
      id: b.id,
      code: b.batch_no,
      unit_cost: parseFloat(b.unit_cost),
      remaining: parseFloat(b.qty_remaining),
    });
  }
  return map;
}

/**
 * What the item list may show about cost. One query for every shop (the
 * business flags); a shop that maintains batches then also gets its open
 * batches and each item's / size's average purchase cost (the cost of its
 * old, pre-batch stock). Returns { on, staffSeeCost, batches, avg }.
 */
async function costView(newRequest, businessId) {
  const f = (await newRequest()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT inventory_enabled, batch_tracking_enabled, staff_see_cost
            FROM businesses WHERE id = @business_id`)).recordset[0] || {};
  const view = {
    on: !!f.inventory_enabled && !!f.batch_tracking_enabled,
    staffSeeCost: f.staff_see_cost !== false && f.staff_see_cost !== 0,
    batches: new Map(),
    avg: new Map(),
  };
  if (!view.on) return view;
  view.batches = await openBatchesByTarget(newRequest(), businessId);
  const a = await newRequest()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT v.item_id, v.variant_id,
                   SUM(v.unit_price * v.quantity)
                     / NULLIF(SUM(v.quantity + ISNULL(v.free_quantity, 0)), 0) AS cost
            FROM vendor_bill_items v
            JOIN vendor_bills vb ON vb.id = v.vendor_bill_id
            WHERE vb.business_id = @business_id
              AND (v.item_id IS NOT NULL OR v.variant_id IS NOT NULL)
            GROUP BY v.item_id, v.variant_id`);
  for (const r of a.recordset) {
    if (r.cost != null) view.avg.set(String(r.variant_id || r.item_id).toLowerCase(), r4(r.cost));
  }
  return view;
}

module.exports = {
  costView,
  batchCode, targetOf, unitCost, fifoPlan,
  receive, unreceive, dropEmpty, allocate, returnBill, returnPart, trimExcess, reconcile, recostBatches,
  openBatchesByTarget,
};
