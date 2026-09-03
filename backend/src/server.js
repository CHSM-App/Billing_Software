require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

// Validate required environment variables at startup
const REQUIRED_ENV = ['NODE_ENV', 'DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME', 'JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'CORS_ORIGINS'];
const missing = REQUIRED_ENV.filter((key) => !process.env[key]);
if (missing.length > 0) {
  // Logger not yet initialised — use console for fatal startup errors only
  console.error(`[startup] Missing required environment variables: ${missing.join(', ')}`);
  console.error('[startup] Copy backend/.env.example to backend/.env and fill in the values.');
}
if (process.env.NODE_ENV && !['development', 'production', 'test'].includes(process.env.NODE_ENV)) {
  console.error(`[startup] NODE_ENV must be "development", "production", or "test" (got: "${process.env.NODE_ENV}")`);
}

const WEAK_DEFAULTS = ['changeme', 'secret', 'jwt_secret', 'your_secret'];
for (const key of ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET']) {
  if (process.env[key]) {
    if (WEAK_DEFAULTS.includes(process.env[key].toLowerCase())) {
      console.error(`[startup] ${key} is set to a weak default — replace it with a cryptographically strong secret.`);
    }
    if (process.env[key].length < 32) {
      console.error(`[startup] ${key} is too short (${process.env[key].length} chars) — must be at least 32 characters.`);
    }
  }
}

// Logger is safe to initialise now that NODE_ENV is validated
const logger   = require('./logger');
const pinoHttp = require('pino-http');

logger.info({ node_env: process.env.NODE_ENV }, 'startup');

const express    = require('express');
const cors       = require('cors');
const bodyParser = require('body-parser');
const { pool, poolConnect, sql } = require('./db');
const { globalLimiter, healthLimiter } = require('./middleware/rateLimiter');

const app = express();

// Behind IIS — without this every request looks like 127.0.0.1 and the
// rate limiter buckets all users together.
app.set('trust proxy', 1);

// ---------------------------------------------------------------------------
// Canonical host — send page requests arriving on any other hostname (notably
// the bare server IP) to the real domain, so search engines stop seeing two
// copies of every page. Only page traffic is redirected; API, QR-order, receipt,
// upload and health paths are left alone. See src/canonicalHost.js.
// ---------------------------------------------------------------------------
const { resolveCanonicalHost, canonicalRedirectTarget } = require('./canonicalHost');
const CANONICAL_HOST = resolveCanonicalHost();

if (CANONICAL_HOST) {
  app.use((req, res, next) => {
    const target = canonicalRedirectTarget(req, CANONICAL_HOST);
    return target ? res.redirect(301, target) : next();
  });
}

// Trailing slashes create a duplicate URL for every page ("/help" and "/help/").
// Collapse them onto the canonical form before static lookup.
app.use((req, res, next) => {
  if ((req.method === 'GET' || req.method === 'HEAD') && req.path.length > 1 && req.path.endsWith('/')) {
    const query = req.originalUrl.slice(req.path.length);
    return res.redirect(301, req.path.replace(/\/+$/, '') + query);
  }
  next();
});

// ---------------------------------------------------------------------------
// Static files — must be before CORS/rate-limit so assets are served without
// any origin checks or request quotas.
//
// `extensions: ['html']` is what makes the prerendered pages work: /help resolves
// to public/help.html, so crawlers get fully rendered HTML instead of an empty
// SPA shell. See landingPage/prerender.js.
// ---------------------------------------------------------------------------
const path = require('path');
const PUBLIC_DIR = path.join(__dirname, '..', 'public');
app.use(express.static(PUBLIC_DIR, { extensions: ['html'] }));

// Customer-uploaded item photos live in backend/uploads (OUTSIDE public/, which
// CI rebuilds and force-pushes on deploy). Served read-only at /uploads so the
// URL stored in items.image_url ("/uploads/items/<id>.jpg") resolves. Long cache
// since filenames are stable and the app appends a ?v= cache-buster on change.
const UPLOADS_DIR = path.join(__dirname, '..', 'uploads');
app.use('/uploads', express.static(UPLOADS_DIR, {
  maxAge: '7d',
  fallthrough: true,
}));

// ---------------------------------------------------------------------------
// CORS
// ---------------------------------------------------------------------------
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

if (allowedOrigins.includes('*')) {
  logger.error('CORS_ORIGINS must not contain "*". Specify exact origins.');
}

for (const origin of allowedOrigins) {
  try {
    const u = new URL(origin);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new Error();
  } catch {
    logger.error({ origin }, 'Invalid CORS origin — must be a full http/https URL');
  }
}

logger.info({ origins: allowedOrigins }, 'CORS configured');

app.use(cors({
  origin(requestOrigin, callback) {
    if (!requestOrigin) return callback(null, true);
    if (allowedOrigins.includes(requestOrigin)) return callback(null, true);
    callback(new Error(`CORS: origin "${requestOrigin}" is not allowed`));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
  maxAge: 86400,
}));

// ---------------------------------------------------------------------------
// HTTP request logging (pino-http)
// Logs every request with method, url, status, response time, and user context.
// Health-check endpoints are excluded to keep logs clean.
// ---------------------------------------------------------------------------
app.use(pinoHttp({
  logger,
  // Auto-assign a unique request ID to each request for tracing
  genReqId(req) {
    return req.headers['x-request-id'] || require('crypto').randomUUID();
  },
  // Attach the request ID to the response so clients can correlate
  customSuccessMessage(req, res) {
    return `${req.method} ${req.url} ${res.statusCode}`;
  },
  customErrorMessage(req, res, err) {
    return `${req.method} ${req.url} ${res.statusCode} — ${err.message}`;
  },
  // Suppress noisy health-check pings
  autoLogging: {
    ignore(req) {
      return req.url === '/health' || req.url === '/api/health';
    },
  },
  // Log user_id from JWT payload if already decoded (set by requireAuth middleware)
  customProps(req) {
    return req.user
      ? { user_id: req.user.user_id, business_id: req.user.business_id }
      : {};
  },
  // Redact sensitive fields from logged request/response bodies
  redact: {
    paths: ['req.headers.authorization', 'req.body.pin', 'req.body.refresh_token'],
    censor: '[REDACTED]',
  },
}));

app.use(bodyParser.json());

// Health check — registered BEFORE the global rate limiter, deliberately, and
// with its own budget instead (healthLimiter).
//
// Every client hits this to decide whether it is online. Sharing the app's
// budget let the app deadlock itself: once a shop tripped the limit /health
// answered 429, checkReachable() read that as "offline", and every device then
// probed /health — re-spending the budget as fast as the window refilled it.
// The shop stayed both rate-limited and offline with nobody doing any work.
// Its own bucket breaks that loop while still capping an unauthenticated
// endpoint that runs a `SELECT 1` on every call.
app.get('/health', healthLimiter, healthHandler);
app.get('/api/health', healthLimiter, healthHandler);

// Global rate limit — see middleware/rateLimiter.js for why it is keyed
// per signed-in user rather than per IP.
app.use(globalLimiter);

// Hoisted — the routes above are registered before this declaration.
async function healthHandler(req, res) {
  try {
    await poolConnect;
    await pool.request().query('SELECT 1');
    res.json({ ok: true, db: 'connected', ts: new Date().toISOString() });
  } catch (err) {
    logger.error({ err }, 'health check failed');
    res.status(500).json({ ok: false, db: 'error', error: err.message });
  }
}

// Routes
app.use('/api', require('./routes/auth'));
app.use('/api/staff', require('./routes/staff'));
app.use('/api/businesses', require('./routes/businesses'));
app.use('/api/items', require('./routes/items'));
app.use('/api/raw-materials', require('./routes/raw_materials'));
app.use('/api/bills', require('./routes/bills'));
app.use('/api/credit', require('./routes/credit'));
app.use('/receipt',  require('./routes/receipt'));
app.use('/order',    require('./routes/public_order'));
app.use('/store',    require('./routes/public_store'));
app.use('/api/online-orders', require('./routes/online_orders'));
app.use('/api/tables', require('./routes/tables'));
app.use('/api/kitchen', require('./routes/kitchen'));
app.use('/api/reports', require('./routes/reports'));
app.use('/api/expenses/recurring', require('./routes/recurring_expenses'));
app.use('/api/expenses', require('./routes/expenses'));
app.use('/api/vendor-bills', require('./routes/vendor_bills'));
app.use('/api/audit', require('./routes/audit'));
app.use('/api/license', require('./routes/license'));
app.use('/api/account', require('./routes/account'));
app.use('/api/fcm', require('./routes/fcm'));
// Internal admin dashboard — MUST be above the SPA catch-all so /admin/* isn't
// swallowed by index.html. Gated by ADMIN_URL_SLUG (page) + admin JWT (API).
app.use('/admin', require('./routes/admin'));

// Unexpected middleware/route failures should stay JSON for API callers.
app.use((err, req, res, next) => {
  logger.error({ err, method: req.method, url: req.originalUrl }, 'unhandled request error');

  if (res.headersSent) return next(err);

  if (req.originalUrl && req.originalUrl.startsWith('/api/')) {
    const status = err.status || err.statusCode || (err instanceof SyntaxError ? 400 : 500);
    const message = status === 400
      ? 'Invalid request body.'
      : 'Something went wrong. Please try again.';
    return res.status(status).json({ error: message });
  }

  return next(err);
});

// ---------------------------------------------------------------------------
// Not found — every landing-page route is prerendered to its own HTML file and
// already served by express.static above, so anything reaching here really is
// missing. Previously this returned index.html with a 200, which is why the SEO
// audit reported no custom 404 page: search engines saw an infinite supply of
// duplicate "valid" URLs (soft 404s) instead of a single clear signal.
// ---------------------------------------------------------------------------
// Express 5 requires a named wildcard; `/{*path}` also matches `/`.
const NOT_FOUND_PAGE = path.join(PUBLIC_DIR, '404.html');

app.use('/{*path}', (req, res) => {
  res.status(404);
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate');

  if (req.originalUrl.startsWith('/api/')) {
    return res.json({ error: 'Not found.' });
  }
  if (req.method === 'HEAD') return res.end();
  if (req.method !== 'GET') return res.type('txt').send('Not Found');

  return res.sendFile(NOT_FOUND_PAGE, (err) => {
    if (err && !res.headersSent) res.type('txt').send('Not Found');
  });
});

const PORT = process.env.PORT || 3000;

// iisnode runs src/server.js directly — bind immediately so iisnode gets a
// live process. The DB pool connects eagerly in db.js and routes will queue
// until it is ready. Tests require() this file and set NODE_ENV=test.
if (process.env.NODE_ENV !== 'test') {
  const server = app.listen(PORT, '0.0.0.0', () => {
    logger.info({ port: PORT }, 'server listening');
  });
  // Attach the WebSocket server for real-time updates (kitchen/tables/drafts).
  try {
    require('./realtime').attach(server);
  } catch (err) {
    logger.error({ err }, 'failed to attach websocket server');
  }
}

module.exports = app;
