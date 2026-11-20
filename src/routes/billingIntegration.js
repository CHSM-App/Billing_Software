// =============================================================================
// /internal/billing — read-only integration surface for the central Invoice &
// Subscription Portal (a separate app — see Vengurla Tech's Invoice Project).
// It bills Vittam's own paying customers — the businesses subscribed to
// Vittam — never a business's own shop customers (that's /api/customers).
//
// Deliberately NOT on the site's JWT system (auth.js / JWT_*_SECRET) — a token
// minted from that secret carries a real staff session with its own
// semantics, which is a bigger blast radius than this needs. Instead this is
// its own bearer key, its own env var (BILLING_INTEGRATION_API_KEY), checked
// by its own tiny middleware below. Revoking the invoice portal's access
// means rotating one env var here, with no effect on any real login session.
//
// Response shape is the CustomerAdapter contract the invoice portal expects
// from every product (externalId/name/email/phone/gstNumber/billingAddress),
// so it can use its generic LiveApiCustomerAdapter unmodified — the mapping
// from "business" to that shape lives here, once, next to the data it maps.
// =============================================================================

const express = require('express');
const crypto = require('crypto');
const { pool, poolConnect, sql } = require('../db');
const logger = require('../logger');
const { billingIntegrationLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Constant-time comparison: a naive `token !== expected` returns faster the
// earlier the first mismatched byte is, which leaks how many leading
// characters an attacker already has right. timingSafeEqual needs equal
// lengths, so a length mismatch is handled by comparing the expected key
// against itself — same cost, no early return either way.
function safeEqual(a, b) {
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) {
    crypto.timingSafeEqual(bufB, bufB);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

function requireBillingApiKey(req, res, next) {
  const expected = process.env.BILLING_INTEGRATION_API_KEY;
  if (!expected) {
    // Misconfiguration, not a client error — don't say "unauthorized" for a
    // feature that was never actually turned on.
    logger.error('BILLING_INTEGRATION_API_KEY is not set — /internal/billing is disabled');
    return res.status(503).json({ error: 'Billing integration is not configured on this server.' });
  }
  const header = req.headers.authorization;
  const token = header && header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token || !safeEqual(token, expected)) {
    logger.warn({ ip: req.ip }, 'billing integration: rejected API key');
    return res.status(401).json({ error: 'Not authorized.' });
  }
  return next();
}

// No auth — matches the convention of the site's own /health, so the invoice
// portal's adapter healthCheck() doesn't need the API key just to ask
// "is this reachable at all".
router.get('/health', (req, res) => res.json({ ok: true }));

// Rate limit before the key check so a flood of guesses is throttled even
// before each one is verified; the limiter itself only charges rejected
// (401) requests, so the portal's normal traffic never spends the budget.
router.use(billingIntegrationLimiter, requireBillingApiKey);

function toBillingAddress(b) {
  if (!b.address && !b.city && !b.state) return null;
  return {
    line1: b.address || null,
    city: b.city || null,
    state: b.state || null,
    pincode: b.pincode || null,
    country: 'India',
  };
}

// Vittam's `users` table has no email column — the business's own email (if
// any) is the only email on file, so that is what fills the contract's
// `email` field. Owner name/phone come from the one 'owner' user (migration
// 073 enforces exactly one per business).
function toCustomer(b) {
  return {
    externalId: String(b.id),
    name: b.name,
    ownerName: b.owner_name || null,
    email: b.email || null,
    phone: b.owner_phone || b.phone || null,
    gstNumber: b.gst_number || null,
    billingAddress: toBillingAddress(b),
  };
}

const BUSINESS_COLUMNS = `
  b.id, b.name, b.address, b.phone, b.email, b.city, b.state, b.pincode, b.gst_number,
  owner.name AS owner_name, owner.phone AS owner_phone
`;

const OWNER_JOIN = `
  LEFT JOIN (
    SELECT business_id, name, phone,
           ROW_NUMBER() OVER (PARTITION BY business_id ORDER BY created_at) AS rn
    FROM users WHERE role = 'owner'
  ) owner ON owner.business_id = b.id AND owner.rn = 1
`;

// GET /internal/billing/customers/search?q=&limit=
router.get('/customers/search', async (req, res) => {
  try {
    await poolConnect;
    const q = String(req.query.q || '').trim();
    const limitRaw = parseInt(req.query.limit, 10);
    const limit = Math.min(Number.isFinite(limitRaw) && limitRaw > 0 ? limitRaw : 10, 50);

    const request = pool.request().input('limit', sql.Int, limit);
    let where = '1 = 1';
    if (q) {
      request.input('q', sql.NVarChar(200), `%${q}%`);
      where = '(b.name LIKE @q OR b.phone LIKE @q OR b.email LIKE @q OR owner.name LIKE @q OR owner.phone LIKE @q)';
    }

    const result = await request.query(`
      SELECT TOP (@limit) ${BUSINESS_COLUMNS}
      FROM businesses b
      ${OWNER_JOIN}
      WHERE ${where}
      ORDER BY b.created_at DESC
    `);
    return res.json(result.recordset.map(toCustomer));
  } catch (err) {
    logger.error({ err }, 'billing integration: customer search failed');
    return res.status(500).json({ error: 'Failed to search customers' });
  }
});

// GET /internal/billing/customers/:id
router.get('/customers/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: 'Customer not found' });
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .query(`
        SELECT ${BUSINESS_COLUMNS}
        FROM businesses b
        ${OWNER_JOIN}
        WHERE b.id = @id
      `);
    if (result.recordset.length === 0) return res.status(404).json({ error: 'Customer not found' });
    return res.json(toCustomer(result.recordset[0]));
  } catch (err) {
    logger.error({ err }, 'billing integration: customer lookup failed');
    return res.status(500).json({ error: 'Failed to load customer' });
  }
});

module.exports = router;
