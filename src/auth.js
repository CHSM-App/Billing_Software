const jwt = require('jsonwebtoken');
const crypto = require('crypto');
require('dotenv').config();

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

function requireAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing token' });
  }
  const token = header.slice(7);
  try {
    const payload = verifyAccessToken(token);
    // A staff access token carries no `typ`. Every customer-facing token does
    // ('store', 'order'), so anything typed is a public session being presented
    // where a staff session is required — refuse it regardless of signature.
    // Redundant now that public tokens are signed with a derived key, and kept
    // deliberately: it is the layer that still holds if a future token type is
    // ever minted with ACCESS_SECRET by mistake.
    if (payload.typ) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
    req.user = payload;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = {
  signAccessToken, signRefreshToken, verifyAccessToken, verifyRefreshToken,
  requireAuth, publicTokenSecret,
};
