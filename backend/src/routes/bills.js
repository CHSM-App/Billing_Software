const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can perform this action' });
  }
  next();
}

// Generate bill number: INV-0001, INV-0002, ...
async function generateBillNumber(transaction, businessId) {
  const result = await transaction.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query('SELECT COUNT(*) AS cnt FROM bills WHERE business_id = @business_id');
  const next = result.recordset[0].cnt + 1;
  return 'INV-' + String(next).padStart(4, '0');
}

// Fetch full bill with line items
async function fetchBill(billId, businessId) {
  const billResult = await pool.request()
    .input('id', sql.UniqueIdentifier, billId)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`
      SELECT id, business_id, bill_number, table_id, customer_name, customer_phone,
             subtotal, tax_amount, total, payment_mode, status, created_by_user_id, created_at
      FROM bills
      WHERE id = @id AND business_id = @business_id
    `);

  if (billResult.recordset.length === 0) return null;
  const bill = billResult.recordset[0];

  const itemsResult = await pool.request()
    .input('bill_id', sql.UniqueIdentifier, billId)
    .query(`
      SELECT id, bill_id, item_id, item_name, quantity, unit_price, tax_rate, line_total
      FROM bill_items
      WHERE bill_id = @bill_id
    `);

  bill.items = itemsResult.recordset;
  return bill;
}

// POST /api/bills
router.post('/', requireAuth, async (req, res) => {
  const { items, table_id, customer_name, customer_phone, payment_mode, status } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required and must not be empty' });
  }
  if (!payment_mode) {
    return res.status(400).json({ error: 'payment_mode is required' });
  }
  const validPaymentModes = ['cash', 'upi', 'card', 'credit', 'other'];
  if (!validPaymentModes.includes(payment_mode)) {
    return res.status(400).json({ error: `payment_mode must be one of: ${validPaymentModes.join(', ')}` });
  }
  const billStatus = status || 'finalized';
  if (!['draft', 'finalized'].includes(billStatus)) {
    return res.status(400).json({ error: 'status must be draft or finalized' });
  }

  try {
    await poolConnect;

    // Check inventory_enabled for this business
    const bizResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT inventory_enabled FROM businesses WHERE id = @business_id');
    const inventoryEnabled = bizResult.recordset[0]?.inventory_enabled;

    // Look up all items in one query
    const itemIds = items.map((i) => `'${i.item_id}'`).join(',');
    const itemsData = await pool.request().query(`
      SELECT id, name, price, tax_rate, stock_quantity
      FROM items
      WHERE id IN (${itemIds}) AND business_id = '${req.user.business_id}' AND is_active = 1
    `);
    const itemMap = {};
    for (const row of itemsData.recordset) {
      itemMap[row.id] = row;
    }

    // Validate all items exist
    for (const item of items) {
      if (!itemMap[item.item_id]) {
        return res.status(400).json({ error: `Item not found: ${item.item_id}` });
      }
    }

    // Calculate totals
    let subtotal = 0;
    let taxAmount = 0;
    const lineItems = items.map((i) => {
      const dbItem = itemMap[i.item_id];
      const qty = parseFloat(i.quantity);
      const unitPrice = parseFloat(dbItem.price);
      const taxRate = dbItem.tax_rate != null ? parseFloat(dbItem.tax_rate) : null;
      const lineTax = taxRate ? qty * unitPrice * (taxRate / 100) : 0;
      const lineTotal = qty * unitPrice + lineTax;
      subtotal += qty * unitPrice;
      taxAmount += lineTax;
      return {
        item_id: dbItem.id,
        item_name: dbItem.name,
        quantity: qty,
        unit_price: unitPrice,
        tax_rate: taxRate,
        line_total: parseFloat(lineTotal.toFixed(2)),
      };
    });
    const total = parseFloat((subtotal + taxAmount).toFixed(2));
    subtotal = parseFloat(subtotal.toFixed(2));
    taxAmount = parseFloat(taxAmount.toFixed(2));

    const transaction = pool.transaction();
    await transaction.begin();

    try {
      const billNumber = await generateBillNumber(transaction, req.user.business_id);

      // Insert bill
      const billResult = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('bill_number', sql.NVarChar(50), billNumber)
        .input('table_id', sql.UniqueIdentifier, table_id || null)
        .input('customer_name', sql.NVarChar(200), customer_name || null)
        .input('customer_phone', sql.NVarChar(20), customer_phone || null)
        .input('subtotal', sql.Decimal(10, 2), subtotal)
        .input('tax_amount', sql.Decimal(10, 2), taxAmount)
        .input('total', sql.Decimal(10, 2), total)
        .input('payment_mode', sql.NVarChar(20), payment_mode)
        .input('status', sql.NVarChar(20), billStatus)
        .input('created_by_user_id', sql.UniqueIdentifier, req.user.user_id)
        .query(`
          INSERT INTO bills (business_id, bill_number, table_id, customer_name, customer_phone,
                             subtotal, tax_amount, total, payment_mode, status, created_by_user_id)
          OUTPUT INSERTED.id
          VALUES (@business_id, @bill_number, @table_id, @customer_name, @customer_phone,
                  @subtotal, @tax_amount, @total, @payment_mode, @status, @created_by_user_id)
        `);

      const billId = billResult.recordset[0].id;

      // Insert bill_items
      for (const li of lineItems) {
        await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, billId)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit_price', sql.Decimal(10, 2), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('line_total', sql.Decimal(10, 2), li.line_total)
          .query(`
            INSERT INTO bill_items (bill_id, item_id, item_name, quantity, unit_price, tax_rate, line_total)
            VALUES (@bill_id, @item_id, @item_name, @quantity, @unit_price, @tax_rate, @line_total)
          `);
      }

      // Update table status if table_id provided
      if (table_id) {
        const tableStatus = billStatus === 'draft' ? 'occupied' : 'billed';
        await transaction.request()
          .input('table_id', sql.UniqueIdentifier, table_id)
          .input('business_id', sql.UniqueIdentifier, req.user.business_id)
          .input('table_status', sql.NVarChar(20), tableStatus)
          .query(`
            UPDATE tables SET status = @table_status
            WHERE id = @table_id AND business_id = @business_id
          `);
      }

      // Decrement stock if inventory enabled
      if (inventoryEnabled) {
        for (const li of lineItems) {
          await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query(`
              UPDATE items SET stock_quantity = stock_quantity - @qty
              WHERE id = @item_id AND business_id = @business_id
            `);
        }
      }

      await transaction.commit();

      const created = await fetchBill(billId, req.user.business_id);
      return res.status(201).json(created);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    console.error('Create bill error:', err.message);
    return res.status(500).json({ error: 'Failed to create bill' });
  }
});

// GET /api/bills
router.get('/', requireAuth, async (req, res) => {
  const { from, to, search } = req.query;

  try {
    await poolConnect;
    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    let where = 'b.business_id = @business_id';

    if (from) {
      request.input('from', sql.DateTime2, new Date(from));
      where += ' AND b.created_at >= @from';
    } else {
      request.input('today', sql.NVarChar(20), new Date().toISOString().slice(0, 10));
      where += " AND CAST(b.created_at AS DATE) = @today";
    }
    if (to) {
      request.input('to', sql.DateTime2, new Date(to + 'T23:59:59'));
      where += ' AND b.created_at <= @to';
    }
    if (search) {
      request.input('search', sql.NVarChar(100), `%${search}%`);
      where += ' AND (b.bill_number LIKE @search OR b.customer_phone LIKE @search)';
    }

    const billsResult = await request.query(`
      SELECT b.id, b.business_id, b.bill_number, b.table_id, b.customer_name, b.customer_phone,
             b.subtotal, b.tax_amount, b.total, b.payment_mode, b.status, b.created_by_user_id, b.created_at
      FROM bills b
      WHERE ${where}
      ORDER BY b.created_at DESC
    `);

    if (billsResult.recordset.length === 0) return res.json([]);

    const billIds = billsResult.recordset.map((b) => `'${b.id}'`).join(',');
    const itemsResult = await pool.request().query(`
      SELECT id, bill_id, item_id, item_name, quantity, unit_price, tax_rate, line_total
      FROM bill_items
      WHERE bill_id IN (${billIds})
    `);

    const itemsByBill = {};
    for (const item of itemsResult.recordset) {
      if (!itemsByBill[item.bill_id]) itemsByBill[item.bill_id] = [];
      itemsByBill[item.bill_id].push(item);
    }

    const bills = billsResult.recordset.map((b) => ({
      ...b,
      items: itemsByBill[b.id] || [],
    }));

    return res.json(bills);
  } catch (err) {
    console.error('Get bills error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch bills' });
  }
});

// GET /api/bills/:id
router.get('/:id', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const bill = await fetchBill(req.params.id, req.user.business_id);
    if (!bill) return res.status(404).json({ error: 'Bill not found' });
    return res.json(bill);
  } catch (err) {
    console.error('Get bill error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch bill' });
  }
});

// PUT /api/bills/:id/finalize
router.put('/:id/finalize', requireAuth, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        UPDATE bills SET status = 'finalized'
        OUTPUT INSERTED.id, INSERTED.table_id
        WHERE id = @id AND business_id = @business_id AND status = 'draft'
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Draft bill not found' });
    }

    const tableId = result.recordset[0].table_id;
    if (tableId) {
      await pool.request()
        .input('table_id', sql.UniqueIdentifier, tableId)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          UPDATE tables SET status = 'billed'
          WHERE id = @table_id AND business_id = @business_id
        `);
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);
    return res.json(bill);
  } catch (err) {
    console.error('Finalize bill error:', err.message);
    return res.status(500).json({ error: 'Failed to finalize bill' });
  }
});

// PUT /api/bills/:id/add-items
router.put('/:id/add-items', requireAuth, async (req, res) => {
  const { items } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }

  try {
    await poolConnect;

    // Check bill is draft
    const billCheck = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, status FROM bills
        WHERE id = @id AND business_id = @business_id
      `);

    if (billCheck.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }
    if (billCheck.recordset[0].status !== 'draft') {
      return res.status(409).json({ error: 'Can only add items to a draft bill' });
    }

    const bizResult = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query('SELECT inventory_enabled FROM businesses WHERE id = @business_id');
    const inventoryEnabled = bizResult.recordset[0]?.inventory_enabled;

    const itemIds = items.map((i) => `'${i.item_id}'`).join(',');
    const itemsData = await pool.request().query(`
      SELECT id, name, price, tax_rate
      FROM items
      WHERE id IN (${itemIds}) AND business_id = '${req.user.business_id}' AND is_active = 1
    `);
    const itemMap = {};
    for (const row of itemsData.recordset) itemMap[row.id] = row;

    for (const item of items) {
      if (!itemMap[item.item_id]) {
        return res.status(400).json({ error: `Item not found: ${item.item_id}` });
      }
    }

    const lineItems = items.map((i) => {
      const dbItem = itemMap[i.item_id];
      const qty = parseFloat(i.quantity);
      const unitPrice = parseFloat(dbItem.price);
      const taxRate = dbItem.tax_rate != null ? parseFloat(dbItem.tax_rate) : null;
      const lineTax = taxRate ? qty * unitPrice * (taxRate / 100) : 0;
      return {
        item_id: dbItem.id,
        item_name: dbItem.name,
        quantity: qty,
        unit_price: unitPrice,
        tax_rate: taxRate,
        line_total: parseFloat((qty * unitPrice + lineTax).toFixed(2)),
        line_subtotal: qty * unitPrice,
        line_tax: lineTax,
      };
    });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      for (const li of lineItems) {
        await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit_price', sql.Decimal(10, 2), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('line_total', sql.Decimal(10, 2), li.line_total)
          .query(`
            INSERT INTO bill_items (bill_id, item_id, item_name, quantity, unit_price, tax_rate, line_total)
            VALUES (@bill_id, @item_id, @item_name, @quantity, @unit_price, @tax_rate, @line_total)
          `);
      }

      // Recalculate totals from all bill_items
      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`
          UPDATE bills SET
            subtotal   = (SELECT SUM(quantity * unit_price) FROM bill_items WHERE bill_id = @id),
            tax_amount = (SELECT SUM(line_total - quantity * unit_price) FROM bill_items WHERE bill_id = @id),
            total      = (SELECT SUM(line_total) FROM bill_items WHERE bill_id = @id)
          WHERE id = @id
        `);

      if (inventoryEnabled) {
        for (const li of lineItems) {
          await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query(`
              UPDATE items SET stock_quantity = stock_quantity - @qty
              WHERE id = @item_id AND business_id = @business_id
            `);
        }
      }

      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);
    return res.json(bill);
  } catch (err) {
    console.error('Add items error:', err.message);
    return res.status(500).json({ error: 'Failed to add items' });
  }
});

// PUT /api/bills/:id/update-items — replace all items on a draft bill
router.put('/:id/update-items', requireAuth, async (req, res) => {
  const { items } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }

  try {
    await poolConnect;

    const billCheck = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.id, b.status, bs.inventory_enabled
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (billCheck.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }
    if (billCheck.recordset[0].status !== 'draft') {
      return res.status(409).json({ error: 'Can only update items on a draft bill' });
    }
    const inventoryEnabled = billCheck.recordset[0].inventory_enabled;

    const itemIds = items.map((i) => `'${i.item_id}'`).join(',');
    const itemsData = await pool.request().query(`
      SELECT id, name, price, tax_rate
      FROM items
      WHERE id IN (${itemIds}) AND business_id = '${req.user.business_id}' AND is_active = 1
    `);
    const itemMap = {};
    for (const row of itemsData.recordset) itemMap[row.id] = row;

    for (const item of items) {
      if (!itemMap[item.item_id]) {
        return res.status(400).json({ error: `Item not found: ${item.item_id}` });
      }
    }

    const lineItems = items.map((i) => {
      const dbItem = itemMap[i.item_id];
      const qty = parseFloat(i.quantity);
      const unitPrice = parseFloat(dbItem.price);
      const taxRate = dbItem.tax_rate != null ? parseFloat(dbItem.tax_rate) : null;
      const lineTax = taxRate ? qty * unitPrice * (taxRate / 100) : 0;
      return {
        item_id: dbItem.id,
        item_name: dbItem.name,
        quantity: qty,
        unit_price: unitPrice,
        tax_rate: taxRate,
        line_total: parseFloat((qty * unitPrice + lineTax).toFixed(2)),
        line_subtotal: qty * unitPrice,
        line_tax: lineTax,
      };
    });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      // Restore inventory for old items if enabled
      if (inventoryEnabled) {
        const oldItems = await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .query('SELECT item_id, quantity FROM bill_items WHERE bill_id = @bill_id AND item_id IS NOT NULL');
        for (const li of oldItems.recordset) {
          await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query('UPDATE items SET stock_quantity = stock_quantity + @qty WHERE id = @item_id AND business_id = @business_id');
        }
      }

      // Delete existing line items
      await transaction.request()
        .input('bill_id', sql.UniqueIdentifier, req.params.id)
        .query('DELETE FROM bill_items WHERE bill_id = @bill_id');

      // Insert new line items
      for (const li of lineItems) {
        await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit_price', sql.Decimal(10, 2), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('line_total', sql.Decimal(10, 2), li.line_total)
          .query(`
            INSERT INTO bill_items (bill_id, item_id, item_name, quantity, unit_price, tax_rate, line_total)
            VALUES (@bill_id, @item_id, @item_name, @quantity, @unit_price, @tax_rate, @line_total)
          `);
      }

      // Recalculate totals
      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`
          UPDATE bills SET
            subtotal   = (SELECT SUM(quantity * unit_price) FROM bill_items WHERE bill_id = @id),
            tax_amount = (SELECT SUM(line_total - quantity * unit_price) FROM bill_items WHERE bill_id = @id),
            total      = (SELECT SUM(line_total) FROM bill_items WHERE bill_id = @id)
          WHERE id = @id
        `);

      // Decrement inventory for new items
      if (inventoryEnabled) {
        for (const li of lineItems) {
          await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query('UPDATE items SET stock_quantity = stock_quantity - @qty WHERE id = @item_id AND business_id = @business_id');
        }
      }

      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);
    return res.json(bill);
  } catch (err) {
    console.error('Update items error:', err.message);
    return res.status(500).json({ error: 'Failed to update items' });
  }
});

// DELETE /api/bills/:id — void (owner only)
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const billResult = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.id, b.status, b.table_id,
               bs.inventory_enabled
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (billResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }
    const bill = billResult.recordset[0];
    if (bill.status === 'voided') {
      return res.status(409).json({ error: 'Bill is already voided' });
    }

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query("UPDATE bills SET status = 'voided' WHERE id = @id");

      // Restore stock if inventory enabled
      if (bill.inventory_enabled) {
        const lineItems = await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .query('SELECT item_id, quantity FROM bill_items WHERE bill_id = @bill_id AND item_id IS NOT NULL');

        for (const li of lineItems.recordset) {
          await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query(`
              UPDATE items SET stock_quantity = stock_quantity + @qty
              WHERE id = @item_id AND business_id = @business_id
            `);
        }
      }

      // Free the table
      if (bill.table_id) {
        await transaction.request()
          .input('table_id', sql.UniqueIdentifier, bill.table_id)
          .input('business_id', sql.UniqueIdentifier, req.user.business_id)
          .query(`
            UPDATE tables SET status = 'empty'
            WHERE id = @table_id AND business_id = @business_id
          `);
      }

      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    return res.json({ success: true });
  } catch (err) {
    console.error('Void bill error:', err.message);
    return res.status(500).json({ error: 'Failed to void bill' });
  }
});

module.exports = router;
