const { pool, poolConnect } = require('./src/db');

// ─── PUT YOUR SQL QUERY HERE ───────────────────────────────────────────────
const QUERY = `
 DECLARE @bid UNIQUEIDENTIFIER = '6F1E69DB-FE80-4EB2-9AA3-D8AEC4D4947E'
  INSERT INTO items (id, business_id, name, category, price, is_active) VALUES
  (NEWID(), @bid, 'Tata Salt 1kg',           'Grocery',    20.00,  1),
  (NEWID(), @bid, 'Aashirvaad Atta 5kg',     'Grocery',   250.00,  1),
  (NEWID(), @bid, 'Fortune Rice 5kg',         'Grocery',   280.00,  1),
  (NEWID(), @bid, 'Toor Dal 1kg',             'Grocery',   140.00,  1),
  (NEWID(), @bid, 'Chana Dal 1kg',            'Grocery',   100.00,  1),
  (NEWID(), @bid, 'Moong Dal 1kg',            'Grocery',   120.00,  1),
  (NEWID(), @bid, 'Saffola Oil 1L',           'Grocery',   180.00,  1),
  (NEWID(), @bid, 'Amul Butter 100g',         'Dairy',      55.00,  1),
  (NEWID(), @bid, 'Amul Milk 500ml',          'Dairy',      28.00,  1),
  (NEWID(), @bid, 'Amul Cheese Slice 200g',   'Dairy',      95.00,  1),
  (NEWID(), @bid, 'Nandini Curd 400g',        'Dairy',      40.00,  1),
  (NEWID(), @bid, 'Britannia Bread',          'Bakery',     45.00,  1),
  (NEWID(), @bid, 'Parle-G Biscuits 800g',    'Snacks',     85.00,  1),
  (NEWID(), @bid, 'Monaco Biscuits',          'Snacks',     30.00,  1),
  (NEWID(), @bid, 'Lays Chips 26g',           'Snacks',     20.00,  1),
  (NEWID(), @bid, 'Kurkure 90g',              'Snacks',     20.00,  1),
  (NEWID(), @bid, 'Maggi Noodles 70g',        'Instant',    14.00,  1),
  (NEWID(), @bid, 'Yippee Noodles 70g',       'Instant',    14.00,  1),
  (NEWID(), @bid, 'Bru Coffee 50g',           'Beverages',  95.00,  1),
  (NEWID(), @bid, 'Taj Mahal Tea 250g',       'Beverages', 145.00,  1),
  (NEWID(), @bid, 'Horlicks 500g',            'Beverages', 280.00,  1),
  (NEWID(), @bid, 'Coca-Cola 600ml',          'Beverages',  40.00,  1),
  (NEWID(), @bid, 'Sprite 600ml',             'Beverages',  40.00,  1),
  (NEWID(), @bid, 'Frooti 200ml',             'Beverages',  20.00,  1),
  (NEWID(), @bid, 'Surf Excel 1kg',           'Household',  95.00,  1),
  (NEWID(), @bid, 'Vim Dishwash Bar 200g',    'Household',  30.00,  1),
  (NEWID(), @bid, 'Dettol Soap 75g',          'Personal',   45.00,  1),
  (NEWID(), @bid, 'Lux Soap 100g',            'Personal',   35.00,  1),
  (NEWID(), @bid, 'Colgate 200g',             'Personal',   95.00,  1),
  (NEWID(), @bid, 'Dove Shampoo 180ml',       'Personal',  165.00,  1),
  (NEWID(), @bid, 'Parachute Oil 200ml',      'Personal',   90.00,  1),
  (NEWID(), @bid, 'Clinic Plus 80ml',         'Personal',   60.00,  1),
  (NEWID(), @bid, 'Hajmola Candy 20pc',       'Snacks',     10.00,  1),
  (NEWID(), @bid, 'Eclairs Toffee 10pc',      'Snacks',     10.00,  1),
  (NEWID(), @bid, 'Cadbury Dairy Milk 13g',   'Snacks',     20.00,  1),
  (NEWID(), @bid, 'KitKat 13.2g',             'Snacks',     20.00,  1),
  (NEWID(), @bid, 'Matchbox',                 'Household',   2.00,  1),
  (NEWID(), @bid, 'Agarbatti Pack',           'Household',  30.00,  1),
  (NEWID(), @bid, 'Notebook 100 Pages',       'Stationery', 40.00,  1),
  (NEWID(), @bid, 'Pen Blue Ink',             'Stationery',  10.00, 1)

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
