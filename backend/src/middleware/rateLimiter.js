const rateLimit = require('express-rate-limit');

// Shared handler — adds Retry-After and a consistent JSON body
function onLimitReached(req, res, options) {
  const retryAfterSec = Math.ceil(options.windowMs / 1000);
  res.set('Retry-After', retryAfterSec);
  res.status(429).json({
    error: options.message,
    retry_after_seconds: retryAfterSec,
  });
}

// POST /api/login — 5 attempts per IP per 15 minutes
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,  // RateLimit-* headers (RFC 6585)
  legacyHeaders: false,
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

module.exports = { loginLimiter, registerLimiter, refreshLimiter };
