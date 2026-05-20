require('dotenv').config();
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

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT} (accessible on local network)`);
});
