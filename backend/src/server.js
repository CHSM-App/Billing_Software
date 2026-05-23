require('dotenv').config();

// Validate required environment variables at startup
const REQUIRED_ENV = ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME', 'JWT_SECRET'];
const missing = REQUIRED_ENV.filter((key) => !process.env[key]);
if (missing.length > 0) {
  console.error(`[startup] Missing required environment variables: ${missing.join(', ')}`);
  console.error('[startup] Copy backend/.env.example to backend/.env and fill in the values.');
  process.exit(1);
}
if (process.env.JWT_SECRET === 'changeme') {
  console.error('[startup] JWT_SECRET is set to the default "changeme" — replace it with a strong secret.');
  process.exit(1);
}

const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const { pool, poolConnect, sql } = require('./db');

const app = express();

app.use(cors());
app.use(bodyParser.json());

// Health check — confirms DB connectivity (both paths work)
async function healthHandler(req, res) {
  try {
    await poolConnect;
    await pool.request().query('SELECT 1');
    res.json({ ok: true, db: 'connected', ts: new Date().toISOString() });
  } catch (err) {
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
app.use('/api/tables', require('./routes/tables'));
app.use('/api/reports', require('./routes/reports'));
app.use('/api/expenses/recurring', require('./routes/recurring_expenses'));
app.use('/api/expenses', require('./routes/expenses'));

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT} (accessible on local network)`);
});
