// =============================================================================
// customers.js — keeps the `customers` table (migration 046) in step with bills.
//
// bills.customer_name / customer_phone remain the source of truth for invoices
// and are never modified here. This module only copies them one way into
// `customers`:
//
//   upsertCustomer — called by the bill routes AFTER their transaction has
//     committed, and never awaited. It swallows its own errors, so a sale can
//     never fail or slow down because of the customers table.
//
//   syncCustomers — a catch-up pass over a business's bills, for any write
//     path that does not call upsertCustomer. Throttled per business.
// =============================================================================

const { pool, poolConnect, sql } = require('./db');
const logger = require('./logger');

const clean = (v) => (v == null ? '' : String(v).trim());

/**
 * One customer = one number, however it was typed. The billing app saves
 * 9876543210; the online store and QR orders save 919876543210 (WhatsApp's
 * format). customers.phone always holds the 10-digit form so those are the
 * same person.
 *
 * MUST stay identical to SQL dbo.canonical_phone (migration 047), which the
 * sync uses on bills.
 */
function canonicalPhone(raw) {
  const d = clean(raw).replace(/[\s+\-().]/g, '');
  if (d.length === 12 && d.startsWith('91')) return d.slice(2);
  if (d.length === 11 && d.startsWith('0')) return d.slice(1);
  return d.slice(0, 20);
}

/**
 * SQL condition matching bills of the customer whose canonical phone is in
 * [phoneExpr], in every format a bill may hold it. An IN list (not a function
 * on bills.customer_phone) so the (business_id, customer_phone) index is used.
 */
function billPhoneMatch(phoneExpr, billAlias = 'b') {
  const p = phoneExpr;
  return `${billAlias}.customer_phone IN (${p}, '91' + ${p}, '+91' + ${p}, '0' + ${p}, '+91 ' + ${p})`;
}

/**
 * Insert the customer, or refresh their name from the bill just saved. Fire
 * and forget: always resolves, never rejects.
 */
function upsertCustomer(businessId, phone, name) {
  const p = canonicalPhone(phone);
  if (!businessId || !p) return Promise.resolve();
  const n = clean(name) || null;
  return (async () => {
    await poolConnect;
    await pool.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('phone', sql.NVarChar(20), p.slice(0, 20))
      .input('name', sql.NVarChar(200), n ? n.slice(0, 200) : null)
      .query(`
        MERGE customers WITH (HOLDLOCK) AS c
        USING (SELECT @phone AS phone, @name AS name) AS s
          ON c.business_id = @business_id AND c.phone = s.phone
        WHEN NOT MATCHED THEN
          INSERT (business_id, phone, name) VALUES (@business_id, s.phone, s.name)
        WHEN MATCHED AND s.name IS NOT NULL AND (c.name IS NULL OR c.name <> s.name) THEN
          UPDATE SET name = s.name, updated_at = GETUTCDATE();
      `);
  })().catch((err) => {
    logger.warn({ err, businessId }, 'customer upsert failed (bill unaffected)');
  });
}

// When each business was last synced in this process. The first sync per
// business scans all its bills; later ones only bills created since then.
// ponytail: per-process throttle — a multi-instance deploy just syncs a bit
// more often, which is harmless (the MERGE is idempotent).
const SYNC_EVERY_MS = 5 * 60 * 1000;
const lastSync = new Map();

/**
 * Add any phone on this business's bills that is missing from `customers`,
 * and refresh names to the latest bill's. At most once per SYNC_EVERY_MS per
 * business. Throws on DB error — callers decide whether that matters.
 */
async function syncCustomers(businessId, { force = false } = {}) {
  const now = Date.now();
  const prev = lastSync.get(businessId);
  if (!force && prev && now - prev < SYNC_EVERY_MS) return;
  lastSync.set(businessId, now);

  await poolConnect;
  try {
    await pool.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      // A minute of overlap so a bill committed during the last pass is not missed.
      .input('since', sql.DateTime2, prev ? new Date(prev - 60 * 1000) : new Date(0))
      .query(`
        WITH latest AS (
          SELECT dbo.canonical_phone(customer_phone) AS phone,
                 NULLIF(LTRIM(RTRIM(customer_name)), '') AS name,
                 ROW_NUMBER() OVER (
                   PARTITION BY dbo.canonical_phone(customer_phone)
                   ORDER BY CASE WHEN NULLIF(LTRIM(RTRIM(customer_name)), '') IS NULL
                                 THEN 1 ELSE 0 END,
                            created_at DESC) AS rn
          FROM bills
          WHERE business_id = @business_id
            AND created_at >= @since
            AND customer_phone IS NOT NULL
            AND LTRIM(RTRIM(customer_phone)) <> ''
        )
        MERGE customers WITH (HOLDLOCK) AS c
        USING (SELECT LEFT(phone, 20) AS phone, LEFT(name, 200) AS name
               FROM latest WHERE rn = 1) AS s
          ON c.business_id = @business_id AND c.phone = s.phone
        WHEN NOT MATCHED THEN
          INSERT (business_id, phone, name) VALUES (@business_id, s.phone, s.name)
        WHEN MATCHED AND s.name IS NOT NULL AND (c.name IS NULL OR c.name <> s.name) THEN
          UPDATE SET name = s.name, updated_at = GETUTCDATE();
      `);
  } catch (err) {
    // Let the next call retry instead of waiting out the throttle.
    if (prev) lastSync.set(businessId, prev); else lastSync.delete(businessId);
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Admin entitlement (subscriptions.allow_customers, migration 048).
// Cached per business for a minute so it does not add a database round trip
// to every Customers request; the admin save clears the entry, so a change
// made there applies at once on this server (within a minute on any other).
// ---------------------------------------------------------------------------
const ACCESS_TTL_MS = 60 * 1000;
const accessCache = new Map();

/** Whether the business may use Customers & campaigns. Default: allowed. */
async function customersAllowed(businessId) {
  // GUIDs reach here in either case (JWT vs admin URL) — key them one way.
  const key = String(businessId).toLowerCase();
  const hit = accessCache.get(key);
  if (hit && Date.now() - hit.at < ACCESS_TTL_MS) return hit.allowed;
  await poolConnect;
  const r = await pool.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query('SELECT allow_customers FROM subscriptions WHERE business_id = @business_id');
  const v = r.recordset[0] ? r.recordset[0].allow_customers : null;
  const allowed = v == null ? true : !!v;
  accessCache.set(key, { allowed, at: Date.now() });
  return allowed;
}

/** Drop the cached entitlement — called when an admin changes it. */
function forgetCustomersAccess(businessId) {
  accessCache.delete(String(businessId).toLowerCase());
}

module.exports = {
  upsertCustomer, syncCustomers, canonicalPhone, billPhoneMatch,
  customersAllowed, forgetCustomersAccess,
};
