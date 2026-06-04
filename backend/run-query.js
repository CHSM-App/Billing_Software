const { pool, poolConnect } = require('./src/db');

// ─── PUT YOUR SQL QUERY HERE ───────────────────────────────────────────────
const QUERY = `
 SELECT definition 
FROM sys.check_constraints 
WHERE name = 'CK_whatsapp_otp_log_purpose'

`;
// ──────────────────────────────────────────────────────────────────────────

async function main() {
  await poolConnect;
  try {
    const result = await pool.request().query(QUERY);

    if (result.recordset && result.recordset.length > 0) {
      console.table(result.recordset);
      console.log(`\n${result.recordset.length} row(s) returned.`);
    } else if (result.rowsAffected) {
      console.log(`Query OK — ${result.rowsAffected[0]} row(s) affected.`);
    } else {
      console.log('Query executed successfully. No rows returned.');
    }
  } catch (err) {
    console.error('Query error:', err.message);
  } finally {
    await pool.close();
  }
}

main();
