const { pool, poolConnect } = require('./src/db');

// ─── PUT YOUR SQL QUERY HERE ───────────────────────────────────────────────
const QUERY = `
  SELECT t.table_number, t.qr_token, t.business_id,
         bs.name AS shop_name, bs.self_order_enabled
  FROM tables t
  JOIN businesses bs ON bs.id = t.business_id
  WHERE t.qr_token = '118D6D35D27241749058141BC7305C5D'
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
