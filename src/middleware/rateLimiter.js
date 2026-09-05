const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { verifyAccessToken } = require('../auth');

// Shared handler — adds Retry-After and a consistent JSON body.
//
// NOTE: express-rate-limit v7+ passes the handler as (req, res, next, options).
// The previous 3-arg signature bound `options` to `next`, so options.windowMs
// and options.message were undefined — producing a 429 body of
// {"retry_after_seconds": null} with NO `error` field. Clients then showed a
// generic "Something went wrong" because there was no message to display.
function onLimitReached(req, res, next, options) {
  // Prefer the actual reset time set on the request; fall back to windowMs.
  const resetMs = req.rateLimit && req.rateLimit.resetTime
    ? req.rateLimit.resetTime.getTime() - Date.now()
    : options.windowMs;
  const retryAfterSec = Math.max(1, Math.ceil(resetMs / 1000));
  res.set('Retry-After', String(retryAfterSec));
  res.status(options.statusCode || 429).json({
    error: options.message,
    retry_after_seconds: retryAfterSec,
  });
}

// Returns the user_id from a valid access token, or null when the request is
// anonymous / the token is expired or forged.
//
// Memoised on the request: express-rate-limit calls keyGenerator AND max for
// every request, and requireAuth verifies again downstream — three HMAC checks
// of the same token otherwise.
function tokenUserId(req) {
  if (req._rlUserId !== undefined) return req._rlUserId;
  const header = req.headers['authorization'];
  let userId = null;
  if (header && header.startsWith('Bearer ')) {
    try {
      userId = verifyAccessToken(header.slice(7)).user_id;
    } catch (_) {
      userId = null;
    }
  }
  req._rlUserId = userId;
  return userId;
}

// Global limiter. Deliberately NOT a throttle on normal app use.
//
// Rate limiting belongs on the endpoints that cost something or are attack
// surfaces — login, registration, WhatsApp sends. Billing is not one of them:
// a till mid-service that gets a 429 cannot settle the customer in front of it,
// which is a far worse outcome than whatever the limit was guarding against.
// Two earlier versions of this got that wrong: an IP-only key meant every till
// in a shop shared one budget, so the busier the shop the sooner the whole
// floor locked up at once.
//
// So: signed-in requests are keyed per user with a ceiling set far above any
// human workflow (~55/sec sustained). It exists only to stop a runaway retry
// loop or a stolen token hammering the database — a real cashier will never
// come near it. Anonymous traffic (login page, QR ordering, receipts, landing
// page) keeps a normal per-IP budget, since that is the part strangers can
// reach.
const AUTHED_MAX = 50000;   // per user per 15 min — a backstop, not a throttle
const ANON_MAX   = 1000;    // per IP per 15 min — shared by a shop's guests

function globalKey(req) {
  const userId = tokenUserId(req);
  if (userId) return `u:${userId}`;
  // ipKeyGenerator normalises IPv6 to a /56 subnet, so a client holding a whole
  // IPv6 range can't sidestep the limit by rotating addresses.
  return `ip:${ipKeyGenerator(req.ip)}`;
}

function globalMax(req) {
  return tokenUserId(req) ? AUTHED_MAX : ANON_MAX;
}

const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: globalMax,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: globalKey,
  message: 'Too many requests. Please slow down.',
  handler: onLimitReached,
});

// GET /health + /api/health — 600 per IP per minute.
//
// Health sits AHEAD of globalLimiter (see server.js) so a shop that exhausts
// its app budget can still find out it is online — sharing one bucket let the
// app rate-limit itself into a permanent offline state. Ahead of it, though, is
// not the same as unlimited: this endpoint is unauthenticated and runs a
// `SELECT 1`, so without a ceiling anyone could hammer the database through it.
// Its own generous per-IP bucket gives it both properties. 600/min is ~10/sec,
// far above real clients (each device probes at most once per 3s, and only
// while offline), so it never fires in normal use.
const healthLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 600,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many requests. Please slow down.',
  handler: onLimitReached,
});

// POST /api/bills/send-whatsapp + /bills/:id/whatsapp — 300 per user per hour.
//
// These actually send a WhatsApp message, so they cost money and burn provider
// quota; unlike billing, they DO deserve a limit. 300/hour is ~5 a minute
// sustained, well above a busy shop messaging a receipt to every customer, so
// it only catches a runaway loop or a stolen token.
const whatsappLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: globalKey,
  message: 'Too many WhatsApp messages. Please try again later.',
  handler: onLimitReached,
});

// POST /api/login — 20 failed attempts per (IP + phone) per 15 minutes.
//
// Keyed on IP *and* the phone being logged in, not IP alone. On shared/NAT'd
// networks (one shop's staff behind a single public IP, or CGNAT) an IP-only
// key means coworkers share one budget and lock each other out. Combining the
// phone isolates each account's attempts so one user's typos never block
// others on the same network. Per-account lockout (users.locked_until) still
// provides the tighter, credential-stuffing-resistant guard.
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,  // RateLimit-* headers (RFC 6585)
  legacyHeaders: false,
  // ipKeyGenerator, not raw req.ip: an IPv6 client owns a whole subnet and
  // could otherwise rotate addresses to reset its login budget at will.
  keyGenerator: (req) =>
    `${ipKeyGenerator(req.ip)}:${req.body && req.body.phone ? req.body.phone : ''}`,
  message: 'Too many login attempts. Please try again in 15 minutes.',
  handler: onLimitReached,
  skipSuccessfulRequests: true, // only count failures toward the limit
});

// POST /api/register — 10 registrations per IP per hour
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many registration attempts. Please try again in 1 hour.',
  handler: onLimitReached,
  skipSuccessfulRequests: true,
});

// POST /api/refresh — 60 requests per IP per 15 minutes.
// skipSuccessfulRequests: true means only failed/rejected refreshes count,
// so normal token rotation by a legitimate client never hits this limit.
const refreshLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many token refresh requests. Please try again in 15 minutes.',
  handler: onLimitReached,
  skipSuccessfulRequests: true,
});

// POST /api/account/deletion/request + /confirm + /cancel
// 15 attempts per IP per hour — bounded because each attempt triggers a WhatsApp OTP
const deletionLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many account deletion attempts. Please try again in 1 hour.',
  handler: onLimitReached,
  skipSuccessfulRequests: false,
});

module.exports = { globalLimiter, globalKey, globalMax, healthLimiter, whatsappLimiter, loginLimiter, registerLimiter, refreshLimiter, deletionLimiter };
