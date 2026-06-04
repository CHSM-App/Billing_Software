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
const rateLimit  = require('express-rate-limit');
const { pool, poolConnect, sql } = require('./db');

const app = express();

// Behind IIS — without this every request looks like 127.0.0.1 and the
// rate limiter buckets all users together.
app.set('trust proxy', 1);

// ---------------------------------------------------------------------------
// Static files — must be before CORS/rate-limit so assets are served without
// any origin checks or request quotas.
// ---------------------------------------------------------------------------
const path = require('path');
const PUBLIC_DIR = path.join(__dirname, '..', 'public');
app.use(express.static(PUBLIC_DIR));

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

// Global rate limit
app.use(rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res, next, options) => {
    res.set('Retry-After', Math.ceil(options.windowMs / 1000));
    res.status(429).json({
      error: 'Too many requests. Please slow down.',
      retry_after_seconds: Math.ceil(options.windowMs / 1000),
    });
  },
}));

// Health check
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
app.get('/health', healthHandler);
app.get('/api/health', healthHandler);

// Routes
app.use('/api', require('./routes/auth'));
app.use('/api/staff', require('./routes/staff'));
app.use('/api/businesses', require('./routes/businesses'));
app.use('/api/items', require('./routes/items'));
app.use('/api/bills', require('./routes/bills'));
app.use('/receipt',  require('./routes/receipt'));
app.use('/api/tables', require('./routes/tables'));
app.use('/api/reports', require('./routes/reports'));
app.use('/api/expenses/recurring', require('./routes/recurring_expenses'));
app.use('/api/expenses', require('./routes/expenses'));
app.use('/api/audit', require('./routes/audit'));
app.use('/api/license', require('./routes/license'));
app.use('/api/account', require('./routes/account'));

// ---------------------------------------------------------------------------
// SPA catch-all — return index.html for any unmatched route so React Router works.
// ---------------------------------------------------------------------------
// Express 5 requires a named wildcard; `/{*path}` also matches `/`.
app.get('/{*path}', (req, res) => {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
  res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
});

const PORT = process.env.PORT || 3000;

// iisnode runs src/server.js directly — bind immediately so iisnode gets a
// live process. The DB pool connects eagerly in db.js and routes will queue
// until it is ready. Tests require() this file and set NODE_ENV=test.
if (process.env.NODE_ENV !== 'test') {
  app.listen(PORT, '0.0.0.0', () => {
    logger.info({ port: PORT }, 'server listening');
  });
}

module.exports = app;
