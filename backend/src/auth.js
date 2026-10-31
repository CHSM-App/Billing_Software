const jwt = require('jsonwebtoken');
const crypto = require('crypto');
require('dotenv').config();
const authState = require('./authState');

const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET;
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET;

/**
 * Signing key for a PUBLIC, customer-facing token (the storefront's OTP
 * session, the table-QR order session) — one distinct key per `kind`.
 *
 * These used to be signed with ACCESS_SECRET itself, which meant a token handed
 * to any member of the public who could receive an OTP verified cleanly as a
 * staff access token: requireAuth checks only the signature, so a customer's
 * 4-hour storefront session authenticated ~35 staff endpoints scoped to that
 * shop (read every bill and the credit ledger, create and edit bills, send
 * WhatsApp on the shop's account).
 *
 * Derived rather than configured so there is no new secret to distribute and no
 * deployment that can forget to set one — and derived with HMAC, so knowing a
 * public key never reveals ACCESS_SECRET. requireAuth's `typ` check below is
 * the independent second layer; either alone closes the hole.
 */
function publicTokenSecret(kind) {
  return crypto.createHmac('sha256', ACCESS_SECRET)
    .update(`vittam:public-token:${kind}`)
    .digest('hex');
}

// Access token: 8 hours — long enough that a refresh failure during a normal
// working day never logs the user out mid-session.
function signAccessToken(payload) {
  return jwt.sign(payload, ACCESS_SECRET, { expiresIn: '8h' });
}

// Refresh token: long-lived (30 days)
function signRefreshToken(payload) {
  return jwt.sign(payload, REFRESH_SECRET, { expiresIn: '30d' });
}

function verifyAccessToken(token) {
  return jwt.verify(token, ACCESS_SECRET);
}

function verifyRefreshToken(token) {
  return jwt.verify(token, REFRESH_SECRET);
}

// Writes a lapsed business may still make: ending a session, and the device's
// push-token housekeeping. Everything else that changes data is "new work".
const ALWAYS_ALLOWED_WRITES = ['/api/logout-all', '/api/fcm/'];

function isWrite(req) {
  return !!req.method && !['GET', 'HEAD', 'OPTIONS'].includes(req.method);
}

/**
 * True when this request must be refused because the business is not paid up.
 * Reads are never blocked (the owner can still see and export their data), and
 * an offline-queued sale is accepted when it was made while the subscription
 * was still paid — so lapsing never costs a shop a sale it already rang up.
 * Refused with 402, which the app's sync queue retries rather than discards.
 */
function blockedBySubscription(req, state) {
  if (!isWrite(req) || Date.now() <= state.paidUntil) return false;
  const url = String(req.originalUrl || '').split('?')[0];
  if (ALWAYS_ALLOWED_WRITES.some((p) => url === p || url.startsWith(p))) return false;
  if (req.method === 'POST' && url === '/api/bills' && req.body && req.body.finalized_at) {
    const soldAt = Date.parse(req.body.finalized_at);
    if (Number.isFinite(soldAt) && soldAt <= state.paidUntil) return false;
  }
  return true;
}

function requireAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing token' });
  }
  const token = header.slice(7);
  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  // A staff access token carries no `typ`. Every customer-facing token does
  // ('store', 'order', 'otp'), so anything typed is a public session being
  // presented where a staff session is required — refuse it regardless of
  // signature. Redundant now that public tokens are signed with a derived key,
  // and kept deliberately: it is the layer that still holds if a future token
  // type is ever minted with ACCESS_SECRET by mistake.
  if (payload.typ) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }

  // The token says who the caller was at login; authState says who they are
  // now (see authState.js). null = state unknown (DB error, no history), so
  // the token alone decides, exactly as before this check existed.
  const finish = (state) => {
    if (state) {
      if (!state.active || (payload.iat && payload.iat < state.validAfterS)) {
        return res.status(401).json({ error: 'Invalid or expired token' });
      }
      if (state.role) payload.role = state.role;
      if (blockedBySubscription(req, state)) {
        // `error` is the readable text: the app shows body.error before
        // body.message (api.dart _extractServerMessage). `code` is for logic.
        return res.status(402).json({
          error: 'Your subscription has ended. Please renew to continue billing.',
          code: 'subscription_inactive',
        });
      }
    }
    req.user = payload;
    return next();
  };

  // Hit: synchronous, no await on the billing hot path. Miss: one PK query.
  const state = authState.cached(payload.user_id);
  if (state !== undefined) return finish(state);
  return authState.load(payload.user_id, payload.business_id).then(finish);
}

module.exports = {
  signAccessToken, signRefreshToken, verifyAccessToken, verifyRefreshToken,
  requireAuth, publicTokenSecret,
};
