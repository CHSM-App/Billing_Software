const rateLimit = require('express-rate-limit');

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
  keyGenerator: (req) => `${req.ip}:${req.body && req.body.phone ? req.body.phone : ''}`,
  message: 'Too many login attempts. Please try again in 15 minutes.',
  handler: onLimitReached,
  skipSuccessfulRequests: true, // only count failures toward the limit
});

// POST /api/register — 3 registrations per IP per hour
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 3,
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
// 5 attempts per IP per hour — tight because each attempt triggers a WhatsApp OTP
const deletionLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many account deletion attempts. Please try again in 1 hour.',
  handler: onLimitReached,
  skipSuccessfulRequests: false,
});

module.exports = { loginLimiter, registerLimiter, refreshLimiter, deletionLimiter };
