const sql    = require('mssql');
const fs     = require('fs');
const logger = require('./logger');
require('dotenv').config();

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
      trustServerCertificate: false,
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
const poolConnect = pool.connect();

pool.on('error', (err) => {
  logger.error({ err }, 'db pool error');
});

poolConnect.catch((err) => {
  logger.error({ err }, 'db connection failed');
});

module.exports = { pool, poolConnect, sql };
