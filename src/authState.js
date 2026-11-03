'use strict';

// =============================================================================
// authState.js — what an 8-hour access token cannot carry.
//
// A JWT is frozen at login: it keeps saying "active cashier of a paid shop"
// after the owner disables that cashier, the admin suspends the shop, or the
// owner resets a stolen PIN. requireAuth asks this module instead, on every
// request, for the account's state as it is NOW:
//
//   active       users.is_active (false also when the row is gone)
//   role         users.role — a demotion applies without a re-login
//   validAfterS  users.sessions_valid_after, in unix seconds: tokens issued
//                before it are dead (PIN reset, log out everywhere)
//   paidUntil    ms timestamp after which the business may not write
//                (subscription status / expires_at + grace)
//
// Billing calls requireAuth constantly, so this is a cache: one primary-key
// query per user per TTL, a Map lookup otherwise. cached() is synchronous so a
// hit adds no latency and no await to the hot path.
//
// ponytail: in-process cache. iisnode runs ONE node process (web.config
// nodeProcessCountPerApplication="1"), so forgetUser/forgetBusiness take effect
// immediately. Raise that count and staleness becomes bounded by TTL_MS only —
// move this to a shared store then.
// =============================================================================

const { pool, poolConnect, sql } = require('./db');
const logger = require('./logger');

const TTL_MS = 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

const cache = new Map(); // user_id -> { at, businessId, state }

/**
 * When this business's paid time ends (ms), or 0 for "not allowed to write".
 *
 * 'suspended' and 'pending' are hard stops. 'active' and 'expired' run to
 * expires_at + grace_period_days: GET /api/license flips an overdue 'active'
 * row to 'expired' the moment expires_at passes, so 'expired' alone cannot
 * mean "stop now" without wiping out the grace period. To cut a shop off
 * immediately, suspend it.
 *
 * No subscription row at all is also a stop — the app already refuses to run
 * without one (GET /api/license answers 403 no_subscription).
 */
function paidUntil(row) {
  if (!row.status || row.status === 'suspended' || row.status === 'pending') return 0;
  const expires = new Date(row.expires_at).getTime();
  if (!Number.isFinite(expires)) return 0;
  return expires + (Number(row.grace_period_days) || 0) * DAY_MS;
}

function toState(row) {
  if (!row) return { active: false };
  const validAfter = row.sessions_valid_after ? new Date(row.sessions_valid_after).getTime() : 0;
  return {
    active: row.is_active === true || row.is_active === 1,
    role: row.role,
    validAfterS: Math.floor(validAfter / 1000),
    paidUntil: paidUntil(row),
  };
}

/** Fresh cached state for this user, or undefined on a miss / expiry. */
function cached(userId) {
  const e = cache.get(userId);
  return e && Date.now() - e.at < TTL_MS ? e.state : undefined;
}

/**
 * Read the state from the database and cache it. Never rejects: on a DB error
 * it falls back to the last known state, or null ("unknown — let it through").
 * Failing closed here would turn a database blip into every till being logged
 * out, and the request would hit the same dead database straight after anyway.
 */
async function load(userId, businessId) {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('user_id', sql.UniqueIdentifier, userId)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`
        SELECT u.is_active, u.role, u.sessions_valid_after,
               s.status, s.expires_at, s.grace_period_days
        FROM users u
        LEFT JOIN subscriptions s ON s.business_id = u.business_id
        WHERE u.id = @user_id AND u.business_id = @business_id
      `);
    const state = toState(result.recordset[0]);
    cache.set(userId, { at: Date.now(), businessId, state });
    return state;
  } catch (err) {
    const stale = cache.get(userId);
    logger.warn({ err, user_id: userId }, 'auth state lookup failed — using last known state');
    return stale ? stale.state : null;
  }
}

/** Drop one user's entry — call after changing their role, status or PIN. */
function forgetUser(userId) {
  cache.delete(userId);
}

/** Drop every user of a business — call after changing its subscription. */
function forgetBusiness(businessId) {
  for (const [userId, e] of cache) {
    if (e.businessId === businessId) cache.delete(userId);
  }
}

module.exports = { cached, load, forgetUser, forgetBusiness, paidUntil, TTL_MS };
