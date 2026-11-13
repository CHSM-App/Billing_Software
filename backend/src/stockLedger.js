'use strict';

/**
 * stockLedger.js — append-only per-item stock history (stock_movements).
 *
 * items/item_variants.stock_quantity stays the live number; every change to it
 * also writes one signed row here so opening/closing stock can be rebuilt for
 * any past day:  closing(D) = SUM(qty) of rows dated <= D,  opening(D) = < D.
 *
 * `runner` is a mssql pool or transaction (anything with .request()); inside a
 * stock transaction pass the transaction so the ledger commits/rolls back with
 * the stock itself.
 *
 * Dates are the shop's BUSINESS day: IST minus businesses.day_end_hour, so a
 * beer shop open till 1am (day_end_hour = 4) books a 12:30am sale to the day
 * it opened. Purchases pass their invoice date instead.
 */

const { sql } = require('./db');

const TYPES = ['opening', 'purchase', 'sale', 'void', 'adjust'];

// SQL expression for the business date of instant @at (UTC; null = now).
const BUSINESS_DATE_SQL = `
  CAST(DATEADD(MINUTE,
        330 - 60 * ISNULL((SELECT day_end_hour FROM businesses WHERE id = @business_id), 0),
        COALESCE(@at, SYSUTCDATETIME())) AS DATE)`;

/**
 * Record a stock change. `qty` is signed (+ in, − out). Exactly one of
 * itemId / variantId is the stock target (a size's stock lives on the size).
 *
 * @param {object} o
 * @param {string} o.businessId
 * @param {string} [o.itemId]
 * @param {string} [o.variantId]
 * @param {number} o.qty        signed quantity
 * @param {string} o.type       one of TYPES
 * @param {string} [o.refId]    bill / vendor bill the change came from
 * @param {string} [o.date]     YYYY-MM-DD; overrides `at`
 * @param {Date}   [o.at]       UTC instant of the event; default now
 */
async function logMovement(runner, o) {
  if (!TYPES.includes(o.type)) throw new Error(`bad movement type ${o.type}`);
  const qty = Number(o.qty);
  if (!qty) return; // nothing moved
  await runner.request()
    .input('business_id', sql.UniqueIdentifier, o.businessId)
    .input('item_id', sql.UniqueIdentifier, o.variantId ? null : (o.itemId || null))
    .input('variant_id', sql.UniqueIdentifier, o.variantId || null)
    .input('qty', sql.Decimal(12, 3), qty)
    .input('type', sql.NVarChar(20), o.type)
    .input('ref_id', sql.UniqueIdentifier, o.refId || null)
    .input('date', sql.Date, o.date || null)
    .input('at', sql.DateTime2, o.at || null)
    .query(`
      INSERT INTO stock_movements
        (business_id, item_id, variant_id, movement_date, movement_type, qty, ref_id)
      VALUES (@business_id, @item_id, @variant_id,
              COALESCE(@date, ${BUSINESS_DATE_SQL}), @type, @qty, @ref_id)`);
}

/**
 * A manual stock figure was typed in (item/size created with stock, or the
 * owner overwrote the count): log the difference. Untracked (null) new stock
 * logs nothing — the report only lists tracked items.
 * ponytail: delta uses the pre-read old value; a sale landing between that read
 * and the write is covered by the report's drift correction, not here.
 */
async function logAdjustment(runner, businessId, target, oldStock, newStock) {
  if (newStock == null) return;
  await logMovement(runner, {
    businessId, itemId: target.itemId, variantId: target.variantId,
    qty: Number(newStock) - Number(oldStock ?? 0), type: 'adjust',
  });
}

/**
 * SQL to append to the statement that finalizes a bill (needs @business_id and
 * @id inputs). A held (draft) bill's stock left the shelf when it was created,
 * but the sale is dated when it is finalized: move its sale rows to the
 * finalize day so the stock report and the profit report agree. Appended to the
 * same batch, not a separate round trip.
 */
const REDATE_SALE_SQL = `
  DECLARE @at DATETIME2 = NULL;
  UPDATE stock_movements SET movement_date = ${BUSINESS_DATE_SQL}
  WHERE business_id = @business_id AND ref_id = @id AND movement_type = 'sale';`;

/**
 * Snapshot each line's buying price onto bill_items.unit_cost (ex-tax, per
 * unit): weighted average of the item's purchase-bill lines, free (scheme)
 * goods counted in the divisor so they lower the cost. NULL when the item was
 * never purchased — profit then reports "cost missing" instead of guessing.
 * Only fills lines that have no snapshot yet, so re-running is harmless.
 */
async function snapshotBillCosts(runner, businessId, billId) {
  await runner.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .input('bill_id', sql.UniqueIdentifier, billId)
    .query(`
      UPDATE bi SET unit_cost = c.cost
      FROM bill_items bi
      OUTER APPLY (
        SELECT SUM(v.unit_price * v.quantity)
                 / NULLIF(SUM(v.quantity + ISNULL(v.free_quantity, 0)), 0) AS cost
        FROM vendor_bill_items v
        JOIN vendor_bills vb ON vb.id = v.vendor_bill_id
        WHERE vb.business_id = @business_id
          AND ((bi.variant_id IS NOT NULL AND v.variant_id = bi.variant_id)
            OR (bi.variant_id IS NULL AND v.item_id = bi.item_id))
      ) c
      WHERE bi.bill_id = @bill_id AND bi.unit_cost IS NULL
        AND (bi.item_id IS NOT NULL OR bi.variant_id IS NOT NULL)`);
}

module.exports = { logMovement, logAdjustment, REDATE_SALE_SQL, snapshotBillCosts, BUSINESS_DATE_SQL };
