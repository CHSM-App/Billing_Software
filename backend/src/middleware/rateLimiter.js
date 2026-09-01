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

// Every request — 600 per signed-in user per 15 minutes.
//
// Keyed on the access token's user_id, NOT the IP. A shop is one public IP with
// several tills behind it, so an IP-only key hands the whole floor a single
// budget: the busier the shop, the sooner every device is locked out at once —
// exactly when it hurts most. Anonymous requests (login, QR ordering, receipts,
// landing page) still share the shop's IP bucket, but those are low-volume per
// device. Same reasoning as loginLimiter below; this limiter runs ahead of it,
// so leaving it on IP alone undid that fix.
function globalKey(req) {
  const header = req.headers['authorization'];
  if (header && header.startsWith('Bearer ')) {
    try {
      return `u:${verifyAccessToken(header.slice(7)).user_id}`;
    } catch (_) {
      // Expired or forged token — falls through to the shared IP bucket.
    }
  }
  // ipKeyGenerator normalises IPv6 to a /56 subnet, so a client holding a whole
  // IPv6 range can't sidestep the limit by rotating addresses.
  return `ip:${ipKeyGenerator(req.ip)}`;
}

const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 600,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: globalKey,
  message: 'Too many requests. Please slow down.',
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

module.exports = { globalLimiter, globalKey, loginLimiter, registerLimiter, refreshLimiter, deletionLimiter };
