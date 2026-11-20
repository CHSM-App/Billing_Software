const sql    = require('mssql');
const fs     = require('fs');
const logger = require('./logger');
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const isProd = process.env.NODE_ENV === 'production';

// ---------------------------------------------------------------------------
// Build the mssql options block based on environment
// ---------------------------------------------------------------------------
// Production: enforce TLS, validate the server certificate.
//   - Set DB_SSL_CA to the path of your CA cert file if using a private CA.
//   - If your server has a certificate signed by a public CA (Let's Encrypt,
//     DigiCert, etc.), leave DB_SSL_CA unset — Node's built-in CA store is used.
// Development: allow self-signed certificates for local/dev SQL Server instances.
//   trustServerCertificate is ONLY set to true in non-production.
// ---------------------------------------------------------------------------

function buildOptions() {
  if (isProd) {
    const options = {
      encrypt: true,
      trustServerCertificate: true,
    };
    if (process.env.DB_SSL_CA) {
      options.cryptoCredentialsDetails = {
        ca: fs.readFileSync(process.env.DB_SSL_CA),
      };
    }
    return options;
  }
  // Development / test — self-signed certs are acceptable
  return {
    encrypt: true,
    trustServerCertificate: true,
  };
}

const config = {
  server: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT, 10),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  options: buildOptions(),
  pool: {
    max: isProd ? 20 : 5,
    min: 0,
    idleTimeoutMillis: 30000,
  },
  connectionTimeout: 15000,  // ms to wait for a new connection
  requestTimeout: 30000,     // ms to wait for a query to complete
};

logger.info(
  isProd
    ? { tls: 'enforced', custom_ca: !!process.env.DB_SSL_CA }
    : { tls: 'trust_server_certificate' },
  `db ${isProd ? 'production' : 'development'} mode`,
);

const pool = new sql.ConnectionPool(config);

// Fires once per failed acquire, so an outage would log every request. Log the
// first, then one line per minute with how many were swallowed.
let poolErrorAt = 0;
let poolErrorsSuppressed = 0;
pool.on('error', (err) => {
  const now = Date.now();
  if (now - poolErrorAt < 60000) { poolErrorsSuppressed++; return; }
  logger.error({ err, suppressed: poolErrorsSuppressed }, 'db pool error');
  poolErrorAt = now;
  poolErrorsSuppressed = 0;
});

// Connect on demand. A failed pool.connect() leaves the pool unopened but
// retryable on the same object, so callers that find it disconnected start a
// fresh attempt — the old single startup promise stayed rejected forever and
// only a process restart recovered. Concurrent callers share the in-flight
// attempt, so there is never a second pool and at most one attempt at a time
// (≤ one per connectionTimeout).
let connecting = null;
let connectAttempts = 0;
function ensureConnected() {
  if (pool.connected) return Promise.resolve(pool);
  if (!connecting) {
    const attempt = ++connectAttempts;
    const startedAt = Date.now();
    connecting = pool.connect()
      .then(() => {
        logger.info({ attempt, ms: Date.now() - startedAt }, 'db connected');
        return pool;
      }, (err) => {
        logger.error({
          err,
          attempt,
          ms: Date.now() - startedAt,
          uptime_s: Math.round(process.uptime()),
          rss_mb: Math.round(process.memoryUsage().rss / 1048576),
        }, 'db connection failed');
        throw err;
      })
      .finally(() => { connecting = null; });
  }
  return connecting;
}

ensureConnected().catch(() => {}); // eager first attempt; already logged

// Every caller does `await poolConnect`. As a thenable it re-checks the pool
// on each await instead of replaying the first connect result forever.
const poolConnect = { then: (ok, fail) => ensureConnected().then(ok, fail) };

module.exports = { pool, poolConnect, ensureConnected, sql };
