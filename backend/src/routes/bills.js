const express = require('express');
const crypto  = require('crypto');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const audit = require('../audit');
const { isValidDateString, todayUtc, dayRange, dateRange } = require('../dateUtils');
const { sendBillLink, normalisePhone } = require('../whatsapp');

// Base URL used in receipt links — no trailing slash
const RECEIPT_BASE = process.env.RECEIPT_BASE_URL || 'https://Vittam.vengurlatech.com';

function generateReceiptToken() {
  // 16 URL-safe chars (base62) — ~95 bits of entropy, unguessable
  return crypto.randomBytes(12).toString('base64url').slice(0, 16);
}

const router = express.Router();

// Build a parameterized IN clause for an array of UUIDs.
// Returns { clause: '@p0,@p1,...', bind: (request) => request }
// Usage: const { clause, bind } = inParams(ids); bind(request); ... WHERE id IN (${clause})
function inParams(ids, type) {
  const sqlType = type || sql.UniqueIdentifier;
  const names = ids.map((_, i) => `@p${i}`);
  const bind = (request) => {
    ids.forEach((id, i) => request.input(`p${i}`, sqlType, id));
    return request;
  };
  return { clause: names.join(','), bind };
}

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
             subtotal, tax_amount, discount_amount, total, payment_mode, status, created_by_user_id, created_at,
             receipt_token
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
  const { items, table_id, customer_name, customer_phone, payment_mode, status, client_bill_id, discount_amount } = req.body;

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
  // client_bill_id must be a UUID v4 when supplied
  if (client_bill_id !== undefined && (typeof client_bill_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(client_bill_id))) {
    return res.status(400).json({ error: 'client_bill_id must be a valid UUID' });
  }

  try {
    await poolConnect;

    // ── Idempotency gate ──────────────────────────────────────────────────────
    // If the client supplied a client_bill_id and we already have a bill with
    // that id for this business, the request is a duplicate (e.g. network
    // timeout followed by a retry).  Return the existing bill instead of
    // creating a second one.  HTTP 200 (not 201) signals "already existed".
    if (client_bill_id) {
      const existing = await pool.request()
        .input('business_id',    sql.UniqueIdentifier, req.user.business_id)
        .input('client_bill_id', sql.NVarChar(36),     client_bill_id)
        .query(`
          SELECT id FROM bills
          WHERE business_id = @business_id AND client_bill_id = @client_bill_id
        `);
      if (existing.recordset.length > 0) {
        const bill = await fetchBill(existing.recordset[0].id, req.user.business_id);
        logger.info({ client_bill_id, bill_id: bill.id }, 'duplicate bill submission — returning existing');
        return res.status(200).json(bill);
      }
    }
    // ─────────────────────────────────────────────────────────────────────────

    const transaction = pool.transaction();
    await transaction.begin();

    try {
      // Read inventory flag and item data inside the transaction so they are
      // consistent with the stock update that follows (no TOCTOU gap).
      const bizResult = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query('SELECT inventory_enabled FROM businesses WHERE id = @business_id');
      const inventoryEnabled = bizResult.recordset[0]?.inventory_enabled;

      const { clause: itemClause, bind: bindItems } = inParams(items.map((i) => i.item_id));
      const itemsData = await bindItems(transaction.request())
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT id, name, price, tax_rate, stock_quantity
          FROM items
          WHERE id IN (${itemClause}) AND business_id = @business_id AND is_active = 1
        `);
      const itemMap = {};
      for (const row of itemsData.recordset) itemMap[row.id] = row;

      // Validate all items exist
      const missingItems = items.filter((i) => !itemMap[i.item_id]);
      if (missingItems.length > 0) {
        await transaction.rollback();
        return res.status(400).json({ error: `Item not found: ${missingItems[0].item_id}` });
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
      subtotal = parseFloat(subtotal.toFixed(2));
      taxAmount = parseFloat(taxAmount.toFixed(2));
      const total = parseFloat((subtotal + taxAmount).toFixed(2));
      const discountAmount = parseFloat(Math.min(
        Math.max(parseFloat(discount_amount) || 0, 0),
        total,
      ).toFixed(2));

      // Centralized stock pre-check: validate ALL items before any writes.
      // itemMap rows were fetched inside this transaction (locked), so
      // stock_quantity here reflects the committed state at transaction start.
      // The atomic UPDATE below is still the final concurrency guard, but this
      // pre-check catches obvious shortfalls early and reports all failing items
      // at once rather than discovering them one-by-one mid-write.
      if (inventoryEnabled) {
        // Aggregate requested quantities per item (a single bill may list the
        // same item on multiple lines).
        const requested = {};
        for (const li of lineItems) {
          requested[li.item_id] = (requested[li.item_id] || 0) + li.quantity;
        }
        const insufficient = lineItems
          .filter((li) => itemMap[li.item_id].stock_quantity != null && requested[li.item_id] > itemMap[li.item_id].stock_quantity)
          .map((li) => ({
            item_id: li.item_id,
            item_name: li.item_name,
            requested: requested[li.item_id],
            available: itemMap[li.item_id].stock_quantity,
          }))
          // De-duplicate (same item_id can appear on multiple lines)
          .filter((v, i, arr) => arr.findIndex((x) => x.item_id === v.item_id) === i);

        if (insufficient.length > 0) {
          await transaction.rollback();
          return res.status(409).json({
            error: 'Insufficient stock',
            items: insufficient,
          });
        }
      }

      const billNumber = await generateBillNumber(transaction, req.user.business_id);
      const receiptToken = generateReceiptToken();

      // Insert bill
      const billResult = await transaction.request()
        .input('business_id',     sql.UniqueIdentifier, req.user.business_id)
        .input('bill_number',     sql.NVarChar(50),     billNumber)
        .input('table_id',        sql.UniqueIdentifier, table_id || null)
        .input('customer_name',   sql.NVarChar(200),    customer_name || null)
        .input('customer_phone',  sql.NVarChar(20),     customer_phone || null)
        .input('subtotal',        sql.Decimal(10, 2),   subtotal)
        .input('tax_amount',      sql.Decimal(10, 2),   taxAmount)
        .input('discount_amount', sql.Decimal(10, 2),   discountAmount)
        .input('total',           sql.Decimal(10, 2),   total)
        .input('payment_mode',    sql.NVarChar(20),     payment_mode)
        .input('status',          sql.NVarChar(20),     billStatus)
        .input('created_by_user_id', sql.UniqueIdentifier, req.user.user_id)
        .input('client_bill_id',  sql.NVarChar(36),     client_bill_id || null)
        .input('receipt_token',   sql.NVarChar(16),     receiptToken)
        .query(`
          INSERT INTO bills (business_id, bill_number, table_id, customer_name, customer_phone,
                             subtotal, tax_amount, discount_amount, total, payment_mode, status,
                             created_by_user_id, client_bill_id, receipt_token)
          OUTPUT INSERTED.id
          VALUES (@business_id, @bill_number, @table_id, @customer_name, @customer_phone,
                  @subtotal, @tax_amount, @discount_amount, @total, @payment_mode, @status,
                  @created_by_user_id, @client_bill_id, @receipt_token)
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

      // Atomically decrement stock — final concurrency guard.
      // AND stock_quantity >= @qty prevents negative stock if another request
      // consumed inventory between our read above and this write.
      if (inventoryEnabled) {
        for (const li of lineItems) {
          // Skip items with NULL stock — treated as unlimited/untracked
          if (itemMap[li.item_id].stock_quantity == null) continue;
          const stockResult = await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query(`
              UPDATE items
              SET stock_quantity = stock_quantity - @qty
              WHERE id = @item_id AND business_id = @business_id
                AND stock_quantity >= @qty
            `);
          if (stockResult.rowsAffected[0] === 0) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id }],
            });
          }
        }
      }

      await transaction.commit();

      const created = await fetchBill(billId, req.user.business_id);

      // Audit — fire-and-forget after the transaction commits
      audit.logBillCreated(
        { user_id: req.user.user_id, user_name: req.user.name || null },
        { id: billId, business_id: req.user.business_id, bill_number: billNumber, total, payment_mode, status: billStatus },
        lineItems,
      );

      return res.status(201).json(created);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    logger.error({ err }, 'Create bill error');
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

    // Validate supplied date strings before touching the DB
    if (from && !isValidDateString(from)) {
      return res.status(400).json({ error: 'from must be a valid date in YYYY-MM-DD format' });
    }
    if (to && !isValidDateString(to)) {
      return res.status(400).json({ error: 'to must be a valid date in YYYY-MM-DD format' });
    }

    let where = 'b.business_id = @business_id';

    if (from && to) {
      // Explicit range: sargable DATETIME2 bounds (>= start of from-day, < start of day after to)
      const { start: fromDt, end: toDt } = dateRange(from, to);
      request.input('from_dt', sql.DateTime2, fromDt);
      request.input('to_dt',   sql.DateTime2, toDt);
      where += ' AND b.created_at >= @from_dt AND b.created_at < @to_dt';
    } else if (from) {
      // Only lower bound supplied — from that day onward
      const { start: fromDt } = dayRange(from);
      request.input('from_dt', sql.DateTime2, fromDt);
      where += ' AND b.created_at >= @from_dt';
    } else {
      // No range supplied — default to today (UTC calendar day)
      const dateStr = todayUtc();
      const { start: fromDt, end: toDt } = dayRange(dateStr);
      request.input('from_dt', sql.DateTime2, fromDt);
      request.input('to_dt',   sql.DateTime2, toDt);
      where += ' AND b.created_at >= @from_dt AND b.created_at < @to_dt';
    }
    if (search) {
      request.input('search', sql.NVarChar(100), `%${search}%`);
      where += ' AND (b.bill_number LIKE @search OR b.customer_phone LIKE @search)';
    }

    const billsResult = await request.query(`
      SELECT b.id, b.business_id, b.bill_number, b.table_id, b.customer_name, b.customer_phone,
             b.subtotal, b.tax_amount, b.discount_amount, b.total, b.payment_mode, b.status,
             b.created_by_user_id, b.created_at, b.receipt_token
      FROM bills b
      WHERE ${where}
      ORDER BY b.created_at DESC
    `);

    if (billsResult.recordset.length === 0) return res.json([]);

    const { clause: billClause, bind: bindBills } = inParams(billsResult.recordset.map((b) => b.id));
    const itemsResult = await bindBills(pool.request()).query(`
      SELECT id, bill_id, item_id, item_name, quantity, unit_price, tax_rate, line_total
      FROM bill_items
      WHERE bill_id IN (${billClause})
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
    logger.error({ err }, 'Get bills error');
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
    logger.error({ err }, 'Get bill error');
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
        OUTPUT INSERTED.id, INSERTED.table_id, INSERTED.bill_number
        WHERE id = @id AND business_id = @business_id AND status = 'draft'
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Draft bill not found' });
    }

    const { table_id: tableId, bill_number: billNumber } = result.recordset[0];
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

    audit.logBillFinalized(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: billNumber },
    );

    return res.json(bill);
  } catch (err) {
    logger.error({ err }, 'Finalize bill error');
    return res.status(500).json({ error: 'Failed to finalize bill' });
  }
});

// PUT /api/bills/:id/add-items
router.put('/:id/add-items', requireAuth, async (req, res) => {
  const { items } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }

  let addedLineItems = [];

  try {
    await poolConnect;

    const transaction = pool.transaction();
    await transaction.begin();

    try {
      // Read bill status, inventory flag, and item data inside the transaction
      // so they are consistent with the stock update that follows (no TOCTOU gap).
      const billCheck = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT b.id, b.status, bs.inventory_enabled
          FROM bills b
          JOIN businesses bs ON bs.id = b.business_id
          WHERE b.id = @id AND b.business_id = @business_id
        `);

      if (billCheck.recordset.length === 0) {
        await transaction.rollback();
        return res.status(404).json({ error: 'Bill not found' });
      }
      if (billCheck.recordset[0].status !== 'draft') {
        await transaction.rollback();
        return res.status(409).json({ error: 'Can only add items to a draft bill' });
      }
      const inventoryEnabled = billCheck.recordset[0].inventory_enabled;

      const { clause: itemClause2, bind: bindItems2 } = inParams(items.map((i) => i.item_id));
      const itemsData = await bindItems2(transaction.request())
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT id, name, price, tax_rate, stock_quantity
          FROM items
          WHERE id IN (${itemClause2}) AND business_id = @business_id AND is_active = 1
        `);
      const itemMap = {};
      for (const row of itemsData.recordset) itemMap[row.id] = row;

      const missingItems2 = items.filter((i) => !itemMap[i.item_id]);
      if (missingItems2.length > 0) {
        await transaction.rollback();
        return res.status(400).json({ error: `Item not found: ${missingItems2[0].item_id}` });
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
        };
      });

      // Centralized stock pre-check — report all insufficient items before any writes.
      if (inventoryEnabled) {
        const requested2 = {};
        for (const li of lineItems) {
          requested2[li.item_id] = (requested2[li.item_id] || 0) + li.quantity;
        }
        const insufficient2 = lineItems
          .filter((li) => requested2[li.item_id] > itemMap[li.item_id].stock_quantity)
          .map((li) => ({
            item_id: li.item_id,
            item_name: li.item_name,
            requested: requested2[li.item_id],
            available: itemMap[li.item_id].stock_quantity,
          }))
          .filter((v, i, arr) => arr.findIndex((x) => x.item_id === v.item_id) === i);

        if (insufficient2.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ error: 'Insufficient stock', items: insufficient2 });
        }
      }

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

      // Atomic decrement — final concurrency guard.
      if (inventoryEnabled) {
        for (const li of lineItems) {
          // Skip items with NULL stock — treated as unlimited/untracked
          if (itemMap[li.item_id].stock_quantity == null) continue;
          const stockResult = await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query(`
              UPDATE items
              SET stock_quantity = stock_quantity - @qty
              WHERE id = @item_id AND business_id = @business_id
                AND stock_quantity >= @qty
            `);
          if (stockResult.rowsAffected[0] === 0) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id }],
            });
          }
        }
      }

      addedLineItems = lineItems;
      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);

    audit.logBillItemsAdded(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: bill.bill_number },
      addedLineItems,
    );

    return res.json(bill);
  } catch (err) {
    logger.error({ err }, 'Add items error');
    return res.status(500).json({ error: 'Failed to add items' });
  }
});

// PUT /api/bills/:id/update-items — replace all items on a draft bill
router.put('/:id/update-items', requireAuth, async (req, res) => {
  const { items } = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }

  let previousLineItems = [];
  let replacementLineItems = [];

  try {
    await poolConnect;

    const transaction = pool.transaction();
    await transaction.begin();

    try {
      // Read bill status, inventory flag, and item data inside the transaction
      // so they are consistent with the stock updates that follow (no TOCTOU gap).
      const billCheck = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT b.id, b.status, bs.inventory_enabled
          FROM bills b
          JOIN businesses bs ON bs.id = b.business_id
          WHERE b.id = @id AND b.business_id = @business_id
        `);

      if (billCheck.recordset.length === 0) {
        await transaction.rollback();
        return res.status(404).json({ error: 'Bill not found' });
      }
      if (billCheck.recordset[0].status !== 'draft') {
        await transaction.rollback();
        return res.status(409).json({ error: 'Can only update items on a draft bill' });
      }
      const inventoryEnabled = billCheck.recordset[0].inventory_enabled;

      const { clause: itemClause3, bind: bindItems3 } = inParams(items.map((i) => i.item_id));
      const itemsData = await bindItems3(transaction.request())
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`
          SELECT id, name, price, tax_rate, stock_quantity
          FROM items
          WHERE id IN (${itemClause3}) AND business_id = @business_id AND is_active = 1
        `);
      const itemMap = {};
      for (const row of itemsData.recordset) itemMap[row.id] = row;

      const missingItems3 = items.filter((i) => !itemMap[i.item_id]);
      if (missingItems3.length > 0) {
        await transaction.rollback();
        return res.status(400).json({ error: `Item not found: ${missingItems3[0].item_id}` });
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
        };
      });

      // Centralized stock pre-check for new items.
      // Note: old-item stock will be restored below before the new decrements,
      // so we check against current stock_quantity as a conservative lower bound.
      // The atomic UPDATE is still the final concurrency guard.
      if (inventoryEnabled) {
        const requested3 = {};
        for (const li of lineItems) {
          requested3[li.item_id] = (requested3[li.item_id] || 0) + li.quantity;
        }
        const insufficient3 = lineItems
          .filter((li) => requested3[li.item_id] > itemMap[li.item_id].stock_quantity)
          .map((li) => ({
            item_id: li.item_id,
            item_name: li.item_name,
            requested: requested3[li.item_id],
            available: itemMap[li.item_id].stock_quantity,
          }))
          .filter((v, i, arr) => arr.findIndex((x) => x.item_id === v.item_id) === i);

        if (insufficient3.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ error: 'Insufficient stock', items: insufficient3 });
        }
      }

      // Snapshot old items for audit + stock restore
      const oldItemsResult = await transaction.request()
        .input('bill_id', sql.UniqueIdentifier, req.params.id)
        .query('SELECT item_id, item_name, quantity, unit_price FROM bill_items WHERE bill_id = @bill_id');
      previousLineItems = oldItemsResult.recordset;

      // Restore inventory for old items — increment is always safe, no guard needed.
      if (inventoryEnabled) {
        for (const li of previousLineItems.filter((x) => x.item_id)) {
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

      // Atomic decrement for new items — final concurrency guard.
      if (inventoryEnabled) {
        for (const li of lineItems) {
          // Skip items with NULL stock — treated as unlimited/untracked
          if (itemMap[li.item_id].stock_quantity == null) continue;
          const stockResult = await transaction.request()
            .input('item_id', sql.UniqueIdentifier, li.item_id)
            .input('business_id', sql.UniqueIdentifier, req.user.business_id)
            .input('qty', sql.Decimal(10, 2), li.quantity)
            .query(`
              UPDATE items
              SET stock_quantity = stock_quantity - @qty
              WHERE id = @item_id AND business_id = @business_id
                AND stock_quantity >= @qty
            `);
          if (stockResult.rowsAffected[0] === 0) {
            await transaction.rollback();
            return res.status(409).json({
              error: 'Insufficient stock',
              items: [{ item_name: li.item_name, item_id: li.item_id }],
            });
          }
        }
      }

      replacementLineItems = lineItems;
      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }

    const bill = await fetchBill(req.params.id, req.user.business_id);

    audit.logBillItemsUpdated(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: bill.bill_number },
      previousLineItems,
      replacementLineItems,
    );

    return res.json(bill);
  } catch (err) {
    logger.error({ err }, 'Update items error');
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
        SELECT b.id, b.status, b.table_id, b.bill_number, b.total,
               bs.inventory_enabled
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (billResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }
    const bill = billResult.recordset[0];

    // Quick pre-flight check before acquiring the transaction (saves round-trips
    // for the common case where a bill was already voided).
    if (bill.status === 'voided') {
      return res.status(409).json({ error: 'Bill is already voided' });
    }

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      // Atomic status flip — the WHERE clause is the true concurrency gate.
      // If two void requests race, only one will see rowsAffected = 1;
      // the other gets 0 and is rejected inside the transaction, preventing
      // any stock from being restored twice.
      const voidResult = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`
          UPDATE bills SET status = 'voided'
          WHERE id = @id AND status != 'voided'
        `);

      if (voidResult.rowsAffected[0] === 0) {
        await transaction.rollback();
        return res.status(409).json({ error: 'Bill is already voided' });
      }

      // Restore stock — only runs when the status flip above succeeded,
      // so it is impossible for stock to be restored more than once per bill.
      if (bill.inventory_enabled) {
        const lineItems = await transaction.request()
          .input('bill_id', sql.UniqueIdentifier, req.params.id)
          .query('SELECT item_id, item_name, quantity FROM bill_items WHERE bill_id = @bill_id AND item_id IS NOT NULL');

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

    audit.logBillVoided(
      { user_id: req.user.user_id, user_name: req.user.name || null },
      { id: req.params.id, business_id: req.user.business_id, bill_number: bill.bill_number, total: bill.total, status: bill.status },
      [],
    );

    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Void bill error');
    return res.status(500).json({ error: 'Failed to void bill' });
  }
});

// POST /api/bills/send-whatsapp
// Sends a receipt link to the customer's WhatsApp.
// Body: { bill_id } — looks up the bill, builds the receipt URL, sends it.
router.post('/send-whatsapp', requireAuth, async (req, res) => {
  const { bill_id } = req.body;

  if (!bill_id) {
    return res.status(400).json({ error: 'bill_id is required' });
  }

  try {
    await poolConnect;
    const row = await pool.request()
      .input('id',          sql.UniqueIdentifier, bill_id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT b.receipt_token, b.customer_phone, b.bill_number,
               bs.name AS shop_name
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.id = @id AND b.business_id = @business_id
      `);

    if (row.recordset.length === 0) {
      return res.status(404).json({ error: 'Bill not found' });
    }

    const { receipt_token, customer_phone, bill_number, shop_name } = row.recordset[0];

    if (!customer_phone) {
      return res.status(400).json({ error: 'This bill has no customer phone number' });
    }
    if (!normalisePhone(customer_phone)) {
      return res.status(400).json({ error: 'Invalid customer phone number' });
    }

    const receiptUrl = `${RECEIPT_BASE}/receipt/${receipt_token}`;
    const result = await sendBillLink({
      phone:      customer_phone,
      shopName:   shop_name,
      billNumber: bill_number,
      receiptUrl,
    });

    if (result.sent) {
      return res.json({ success: true, campaign_id: result.campaignId });
    }
    if (result.skipped) {
      return res.json({ success: false, skipped: true, message: 'WhatsApp sending is disabled' });
    }
    return res.status(500).json({ error: result.error || 'Failed to send WhatsApp message' });
  } catch (err) {
    logger.error({ err }, 'send-whatsapp error');
    return res.status(500).json({ error: 'Failed to send WhatsApp message' });
  }
});

// Receipt page — see routes/receipt.js (mounted at /receipt in server.js)

module.exports = router;
