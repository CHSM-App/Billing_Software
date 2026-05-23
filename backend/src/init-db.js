require('dotenv').config();
const fs = require('fs');
const path = require('path');
const sql = require('mssql');

const config = {
  server: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT, 10),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  options: {
    trustServerCertificate: true,
  },
};

async function run() {
  let pool;
  try {
    console.log('Connecting to SQL Server...');
    pool = await sql.connect(config);
    console.log('Connected.');

    const schemaSQL = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');

    // Split on GO or semicolons so we can run each statement separately.
    // The schema uses semicolons — split on them and skip blank chunks.
    const statements = schemaSQL
      .split(';')
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && !s.startsWith('--'));

    for (const statement of statements) {
      // Skip pure comment lines
      if (statement.replace(/--.*$/gm, '').trim().length === 0) continue;
      try {
        await pool.request().query(statement);
      } catch (err) {
        if (err.message && err.message.includes('There is already an object named')) {
          // Table already exists — skip
        } else {
          throw err;
        }
      }
    }

    console.log('Schema applied successfully.');
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(1);
  } finally {
    if (pool) await pool.close();
  }
}

run();
