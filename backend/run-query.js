const { pool, poolConnect } = require('./src/db');

// ─── PUT YOUR SQL QUERY HERE ───────────────────────────────────────────────
const QUERY = `
 INSERT INTO items (business_id, name, category, price, stock_quantity, low_stock_threshold)
VALUES
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Tata Salt',         'Grocery',   20.00,  200, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Amul Butter 100g',  'Dairy',     55.00,  150, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Aashirvaad Atta 5kg','Grocery', 280.00,   80, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Fortune Sunflower Oil 1L','Oil', 160.00,  100, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Maggi Noodles 70g', 'Snacks',    14.00,  300, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Bisleri Water 1L',  'Beverages', 20.00,  250, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Lifebuoy Soap 100g','Personal',  35.00,  180, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Colgate 200g',      'Personal',  99.00,  120, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Toor Dal 1kg',      'Grocery',  145.00,   90, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Moong Dal 1kg',     'Grocery',  130.00,   85, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Basmati Rice 5kg',  'Grocery',  450.00,   60, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Parle-G Biscuit',   'Snacks',     5.00,  500, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Coca Cola 600ml',   'Beverages', 40.00,  200, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Lays Chips 26g',    'Snacks',    20.00,  250, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Dettol Handwash 200ml','Personal',85.00, 100, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Nescafe Classic 50g','Beverages',250.00,  70, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Surf Excel 1kg',    'Household',110.00,  130, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Harpic 500ml',      'Household', 99.00,   90, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Good Day Biscuit',  'Snacks',    30.00,  200, 50),
('77120484-6E3B-4B1D-A4F9-B006519ED04B', 'Kurkure 80g',       'Snacks',    20.00,  180, 50)


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
