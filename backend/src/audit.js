'use strict';

/**
 * audit.js — append-only audit trail writer
 *
 * All public functions accept a `requestOrPool` first argument that can be
 * either an mssql pool/request (for out-of-transaction writes) or a
 * transaction-request returned by `transaction.request()` (for in-transaction
 * writes that roll back together with the main operation on failure).
 *
 * Design principles:
 *   • Never throws — a failed audit write is logged but NEVER blocks the
 *     main operation.  Business logic must not depend on audit success.
 *   • Immutable — rows are INSERT-only.  No UPDATE or DELETE.
 *   • Snapshot important human-readable labels so the log stays readable
 *     even after the referenced rows are deleted/renamed.
 */

const logger = require('./logger');
const { pool, poolConnect, sql } = require('./db');

// ---------------------------------------------------------------------------
// Core writer
// ---------------------------------------------------------------------------

/**
 * Write a single audit event.
 *
 * @param {object} opts
 * @param {string}  opts.business_id
 * @param {string|null}  opts.user_id        - JWT user_id (null for system events)
 * @param {string|null}  opts.user_name      - snapshot of actor name
 * @param {string}  opts.event_type          - one of the CHECK constraint values
 * @param {string|null}  opts.entity_id      - PK of the primary affected row
 * @param {string|null}  opts.entity_label   - human-readable identifier (bill number, item name…)
 * @param {object|null}  opts.old_value      - state before the change
 * @param {object|null}  opts.new_value      - state after the change
 * @param {string|null}  opts.description    - optional free-text note
 * @param {object|null}  [requestObj]        - mssql request to reuse (for in-transaction writes)
 *                                             If omitted, a fresh pool.request() is used.
 */
async function writeAudit(opts, requestObj) {
  const {
    business_id,
    user_id = null,
    user_name = null,
    event_type,
    entity_id = null,
    entity_label = null,
    old_value = null,
    new_value = null,
    description = null,
  } = opts;

  try {
    await poolConnect;

    const req = requestObj || pool.request();

    await req
      .input('business_id',   sql.UniqueIdentifier, business_id)
      .input('user_id',       sql.UniqueIdentifier, user_id)
      .input('user_name',     sql.NVarChar(200),    user_name)
      .input('event_type',    sql.NVarChar(50),     event_type)
      .input('entity_id',     sql.UniqueIdentifier, entity_id)
      .input('entity_label',  sql.NVarChar(200),    entity_label)
      .input('old_value',     sql.NVarChar(4000),   old_value  ? JSON.stringify(old_value)  : null)
      .input('new_value',     sql.NVarChar(4000),   new_value  ? JSON.stringify(new_value)  : null)
      .input('description',   sql.NVarChar(1000),   description)
      .query(`
        INSERT INTO audit_logs
          (business_id, user_id, user_name, event_type,
           entity_id, entity_label, old_value, new_value, description)
        VALUES
          (@business_id, @user_id, @user_name, @event_type,
           @entity_id, @entity_label, @old_value, @new_value, @description)
      `);
  } catch (err) {
    // Non-fatal: log and continue
    logger.error({ err, event_type, entity_id }, 'audit write failed');
  }
}

// ---------------------------------------------------------------------------
// Domain helpers — one function per event type
// These are the only callsites in the codebase; keep signatures stable.
// ---------------------------------------------------------------------------

// ── Bills ──────────────────────────────────────────────────────────────────

/**
 * Log bill creation (after the transaction commits successfully).
 * @param {object} actor   - { user_id, user_name }
 * @param {object} bill    - { id, business_id, bill_number, total, payment_mode, status }
 * @param {Array}  items   - array of { item_name, quantity, unit_price, line_total }
 */
async function logBillCreated(actor, bill, items) {
  await writeAudit({
    business_id:  bill.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'bill_created',
    entity_id:    bill.id,
    entity_label: bill.bill_number,
    new_value: {
      bill_number:  bill.bill_number,
      status:       bill.status,
      total:        bill.total,
      payment_mode: bill.payment_mode,
      item_count:   items.length,
      items:        items.map((i) => ({ name: i.item_name, qty: i.quantity, unit_price: i.unit_price })),
    },
    description: `Bill ${bill.bill_number} created — total ₹${bill.total}`,
  });
}

/**
 * Log bill finalization.
 */
async function logBillFinalized(actor, bill) {
  await writeAudit({
    business_id:  bill.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'bill_finalized',
    entity_id:    bill.id,
    entity_label: bill.bill_number,
    old_value:    { status: 'draft' },
    new_value:    { status: 'finalized' },
    description:  `Bill ${bill.bill_number} finalized`,
  });
}

/**
 * Log bill void with full snapshot of what was reversed.
 * @param {object} bill   - { id, business_id, bill_number, total, status }
 * @param {Array}  items  - bill_items at the time of void (for stock-reversal audit)
 */
async function logBillVoided(actor, bill, items) {
  await writeAudit({
    business_id:  bill.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'bill_voided',
    entity_id:    bill.id,
    entity_label: bill.bill_number,
    old_value:    { status: bill.status, total: bill.total },
    new_value:    { status: 'voided' },
    description:  `Bill ${bill.bill_number} voided — ₹${bill.total} reversed`,
  });
}

/**
 * Log items being added to a draft bill.
 */
async function logBillItemsAdded(actor, bill, addedItems) {
  await writeAudit({
    business_id:  bill.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'bill_items_added',
    entity_id:    bill.id,
    entity_label: bill.bill_number,
    new_value: {
      items: addedItems.map((i) => ({ name: i.item_name, qty: i.quantity, unit_price: i.unit_price })),
    },
    description:  `${addedItems.length} item(s) added to draft bill ${bill.bill_number}`,
  });
}

/**
 * Log items being replaced on a draft bill.
 */
async function logBillItemsUpdated(actor, bill, oldItems, newItems) {
  await writeAudit({
    business_id:  bill.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'bill_items_updated',
    entity_id:    bill.id,
    entity_label: bill.bill_number,
    old_value: { items: oldItems.map((i) => ({ name: i.item_name, qty: i.quantity, unit_price: i.unit_price })) },
    new_value: { items: newItems.map((i) => ({ name: i.item_name, qty: i.quantity, unit_price: i.unit_price })) },
    description:  `Items replaced on draft bill ${bill.bill_number}`,
  });
}

// ── Items ──────────────────────────────────────────────────────────────────

/**
 * Log item creation.
 */
async function logItemCreated(actor, item) {
  await writeAudit({
    business_id:  item.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'item_created',
    entity_id:    item.id,
    entity_label: item.name,
    new_value: {
      name:           item.name,
      price:          item.price,
      tax_rate:       item.tax_rate,
      // Records whether `price` above is GST-inclusive — without it the logged
      // figure is ambiguous, since the same number bills differently either way.
      price_inclusive_tax: item.price_inclusive_tax,
      category:       item.category,
      stock_quantity: item.stock_quantity,
      barcode:        item.barcode,
    },
    description: `Item "${item.name}" created at ₹${item.price}`
      + (item.price_inclusive_tax ? ' (GST incl.)' : ''),
  });
}

/**
 * Log a price change on an existing item.
 * Only emitted when price actually changed.
 */
async function logItemPriceChanged(actor, item, oldPrice, newPrice) {
  await writeAudit({
    business_id:  item.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'item_price_changed',
    entity_id:    item.id,
    entity_label: item.name,
    old_value:    { price: oldPrice },
    new_value:    { price: newPrice },
    description:  `"${item.name}" price changed ₹${oldPrice} → ₹${newPrice}`,
  });
}

/**
 * Log a manual stock adjustment (owner setting stock_quantity directly).
 * Only emitted when stock_quantity actually changed.
 */
async function logItemStockAdjusted(actor, item, oldQty, newQty) {
  const delta = (newQty ?? 0) - (oldQty ?? 0);
  const sign  = delta >= 0 ? '+' : '';
  await writeAudit({
    business_id:  item.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'item_stock_adjusted',
    entity_id:    item.id,
    entity_label: item.name,
    old_value:    { stock_quantity: oldQty },
    new_value:    { stock_quantity: newQty },
    description:  `"${item.name}" stock manually adjusted ${sign}${delta} (${oldQty} → ${newQty})`,
  });
}

/**
 * Log soft-deletion of an item.
 */
async function logItemDeleted(actor, item) {
  await writeAudit({
    business_id:  item.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'item_deleted',
    entity_id:    item.id,
    entity_label: item.name,
    old_value:    { name: item.name, price: item.price },
    description:  `Item "${item.name}" soft-deleted`,
  });
}

// ── Staff ──────────────────────────────────────────────────────────────────

/**
 * Log adding a new cashier.
 */
async function logStaffAdded(actor, staffUser) {
  await writeAudit({
    business_id:  actor.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'staff_added',
    entity_id:    staffUser.id,
    entity_label: staffUser.name,
    new_value:    { name: staffUser.name, phone: staffUser.phone, role: staffUser.role },
    description:  `Cashier "${staffUser.name}" (${staffUser.phone}) added`,
  });
}

/**
 * Log updating a cashier (name, phone, or PIN).
 * @param {object} changes - fields that were actually changed
 */
async function logStaffUpdated(actor, staffUser, changes) {
  await writeAudit({
    business_id:  actor.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'staff_updated',
    entity_id:    staffUser.id,
    entity_label: staffUser.name,
    new_value:    changes,
    description:  `Cashier "${staffUser.name}" updated: ${Object.keys(changes).join(', ')}`,
  });
}

/**
 * Log deleting a cashier.
 */
async function logStaffDeleted(actor, staffUser) {
  await writeAudit({
    business_id:  actor.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'staff_deleted',
    entity_id:    staffUser.id,
    entity_label: staffUser.name,
    old_value:    { name: staffUser.name, phone: staffUser.phone },
    description:  `Cashier "${staffUser.name}" deleted`,
  });
}

// ── Business profile ──────────────────────────────────────────────────────

/**
 * Log a business profile update.
 * @param {object} actor       - { user_id, user_name, business_id }
 * @param {object} oldProfile  - snapshot of changed fields before update
 * @param {object} newProfile  - snapshot of changed fields after update
 */
async function logBusinessProfileUpdated(actor, oldProfile, newProfile) {
  await writeAudit({
    business_id:  actor.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'business_profile_updated',
    entity_id:    actor.business_id,
    entity_label: newProfile.name || oldProfile.name,
    old_value:    oldProfile,
    new_value:    newProfile,
    description:  `Business profile updated: ${Object.keys(newProfile).join(', ')}`,
  });
}

// ── Auth ───────────────────────────────────────────────────────────────────

/**
 * Log successful login (call with the pool-level request, not a transaction).
 */
async function logUserLogin(businessId, userId, userName) {
  await writeAudit({
    business_id:  businessId,
    user_id:      userId,
    user_name:    userName,
    event_type:   'user_login',
    entity_id:    userId,
    entity_label: userName,
    description:  `User "${userName}" logged in`,
  });
}

/**
 * Record a successful login in the dedicated login_logs table, capturing the
 * client IP address and user-agent (device / app identifier).
 *
 * This is separate from logUserLogin (which writes to the general audit_logs
 * trail). Like the rest of this module it NEVER throws — a failed login-log
 * write is logged and swallowed so it can't block the login itself.
 *
 * @param {object} opts
 * @param {string}       opts.business_id
 * @param {string}       opts.user_id
 * @param {string|null}  opts.user_name
 * @param {string|null}  opts.phone
 * @param {string|null}  opts.ip_address
 * @param {string|null}  opts.user_agent
 */
async function logLoginToTable(opts) {
  const {
    business_id,
    user_id,
    user_name = null,
    phone = null,
    ip_address = null,
    user_agent = null,
  } = opts;

  try {
    await poolConnect;
    await pool.request()
      .input('business_id', sql.UniqueIdentifier, business_id)
      .input('user_id',     sql.UniqueIdentifier, user_id)
      .input('user_name',   sql.NVarChar(200),    user_name)
      .input('phone',       sql.NVarChar(20),     phone)
      .input('ip_address',  sql.NVarChar(64),     ip_address ? String(ip_address).slice(0, 64) : null)
      .input('user_agent',  sql.NVarChar(500),    user_agent ? String(user_agent).slice(0, 500) : null)
      .query(`
        INSERT INTO login_logs
          (business_id, user_id, user_name, phone, ip_address, user_agent)
        VALUES
          (@business_id, @user_id, @user_name, @phone, @ip_address, @user_agent)
      `);
  } catch (err) {
    logger.error({ err, user_id }, 'login_logs write failed');
  }
}

/**
 * Log a failed login attempt.  entity_id is null (we may not know the user).
 */
async function logLoginFailed(businessId, phone) {
  await writeAudit({
    business_id:  businessId,
    user_id:      null,
    user_name:    null,
    event_type:   'user_login_failed',
    entity_id:    null,
    entity_label: phone,
    description:  `Failed login attempt for phone ${phone}`,
  });
}

/**
 * Log an account being locked after too many failed attempts.
 */
async function logUserLocked(businessId, userId, userName) {
  await writeAudit({
    business_id:  businessId,
    user_id:      userId,
    user_name:    userName,
    event_type:   'user_locked',
    entity_id:    userId,
    entity_label: userName,
    description:  `Account "${userName}" locked after repeated failed attempts`,
  });
}

// ── Account deletion ───────────────────────────────────────────────────────

/**
 * Log that an owner submitted and OTP-verified an account deletion request.
 * @param {string} businessId
 * @param {string} userId
 * @param {string} userName
 * @param {Date}   scheduledFor
 */
async function logAccountDeletionRequested(businessId, userId, userName, scheduledFor) {
  await writeAudit({
    business_id:  businessId,
    user_id:      userId,
    user_name:    userName,
    event_type:   'account_deletion_requested',
    entity_id:    businessId,
    entity_label: userName,
    new_value:    { scheduled_for: scheduledFor },
    description:  `Account deletion requested by "${userName}" — scheduled for ${scheduledFor.toDateString()}`,
  });
}

/**
 * Log that the owner cancelled their pending deletion request.
 */
async function logAccountDeletionCancelled(businessId, userId, userName) {
  await writeAudit({
    business_id:  businessId,
    user_id:      userId,
    user_name:    userName,
    event_type:   'account_deletion_cancelled',
    entity_id:    businessId,
    entity_label: userName,
    description:  `Account deletion cancelled by "${userName}"`,
  });
}

/**
 * Log that the account was permanently deleted by the cleanup job.
 * Called after the transaction commits — business row no longer exists,
 * but the audit_logs FK is NO ACTION so the row is still written.
 */
async function logAccountDeleted(businessId, userId, userName) {
  await writeAudit({
    business_id:  businessId,
    user_id:      userId,
    user_name:    userName,
    event_type:   'account_deleted',
    entity_id:    businessId,
    entity_label: userName,
    description:  `Account for "${userName}" permanently deleted by scheduled cleanup`,
  });
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Vendor bills (purchase invoices)
// ---------------------------------------------------------------------------

/** A vendor bill was recorded. `bill` is the inserted row. */
async function logVendorBillCreated(actor, bill, lineCount) {
  await writeAudit({
    business_id:  bill.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'vendor_bill_created',
    entity_id:    bill.id,
    entity_label: `${bill.vendor_name} ${bill.invoice_number}`,
    new_value:    {
      vendor_name: bill.vendor_name,
      vendor_gstin: bill.vendor_gstin,
      invoice_number: bill.invoice_number,
      total: bill.total,
      tax_amount: bill.tax_amount,
      line_count: lineCount,
    },
    description:
      `Purchase "${bill.invoice_number}" from ${bill.vendor_name} recorded — Rs.${bill.total}`,
  });
}

/** A vendor bill was edited. Totals only — the line diff would be unreadable. */
async function logVendorBillUpdated(actor, before, after) {
  await writeAudit({
    business_id:  after.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'vendor_bill_updated',
    entity_id:    after.id,
    entity_label: `${after.vendor_name} ${after.invoice_number}`,
    old_value:    { total: before.total, tax_amount: before.tax_amount },
    new_value:    { total: after.total, tax_amount: after.tax_amount },
    description:
      `Purchase "${after.invoice_number}" from ${after.vendor_name} updated — Rs.${before.total} → Rs.${after.total}`,
  });
}

/** A vendor bill was deleted (and any stock it added was reversed). */
async function logVendorBillDeleted(actor, bill) {
  await writeAudit({
    business_id:  bill.business_id,
    user_id:      actor.user_id,
    user_name:    actor.user_name,
    event_type:   'vendor_bill_deleted',
    entity_id:    bill.id,
    entity_label: `${bill.vendor_name} ${bill.invoice_number}`,
    old_value:    {
      vendor_name: bill.vendor_name,
      invoice_number: bill.invoice_number,
      total: bill.total,
    },
    description:
      `Purchase "${bill.invoice_number}" from ${bill.vendor_name} deleted — Rs.${bill.total}`,
  });
}

module.exports = {
  writeAudit,
  // Bills
  logBillCreated,
  logBillFinalized,
  logBillVoided,
  logBillItemsAdded,
  logBillItemsUpdated,
  // Items
  logItemCreated,
  logItemPriceChanged,
  logItemStockAdjusted,
  logItemDeleted,
  // Staff
  logStaffAdded,
  logStaffUpdated,
  logStaffDeleted,
  // Auth
  logUserLogin,
  logLoginToTable,
  logLoginFailed,
  logUserLocked,
  // Business
  logBusinessProfileUpdated,
  // Account deletion
  logAccountDeletionRequested,
  logAccountDeletionCancelled,
  logAccountDeleted,
  // Vendor bills
  logVendorBillCreated,
  logVendorBillUpdated,
  logVendorBillDeleted,
};
