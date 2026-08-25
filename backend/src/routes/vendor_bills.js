const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const { netUnitPrice } = require('../money');
const audit = require('../audit');
const logger = require('../logger');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can access vendor bills' });
  }
  next();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/;

/** Round to 2dp the way every money figure in this codebase is rounded. */
const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;

/**
 * Split a tax figure into the CGST/SGST halves, giving the odd paisa to CGST so
 * the two always add back to exactly the original. This is the SAME expression
 * used by the GSTR-1 endpoint and routes/receipt.js — a different rounding here
 * would make the outward and inward returns disagree by paise.
 */
function gstHalves(tax) {
  const paise = Math.round((Number(tax) || 0) * 100);
  return [((paise + 1) >> 1) / 100, (paise >> 1) / 100];
}

/**
 * Validate the line array. Returns an error string, or null when valid.
 *
 * A line may target an item, a variant, a raw material, or NOTHING — a freight
 * or service charge carries real ITC but has no stock to receive, and refusing
 * it would force the recorded invoice total to differ from the vendor's.
 */
function validateLines(lines) {
  if (!Array.isArray(lines) || lines.length === 0) {
    return 'At least one line item is required';
  }
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    const at = `Line ${i + 1}`;
    const targets = [l.item_id, l.variant_id, l.raw_material_id].filter(Boolean);
    if (targets.length > 1) {
      return `${at}: choose only one of item, variant or raw material`;
    }
    if (!targets.length && !String(l.name || '').trim()) {
      return `${at}: a description is required when no item is selected`;
    }
    const qty = parseFloat(l.quantity);
    if (!Number.isFinite(qty) || qty <= 0) {
      return `${at}: quantity must be greater than 0`;
    }
    const price = parseFloat(l.unit_price);
    if (!Number.isFinite(price) || price < 0) {
      return `${at}: rate must be 0 or more`;
    }
    if (l.tax_rate != null && l.tax_rate !== '') {
      const rate = parseFloat(l.tax_rate);
      if (!Number.isFinite(rate) || rate < 0 || rate > 100) {
        return `${at}: GST rate must be between 0 and 100`;
      }
    }
  }
  return null;
}

/**
 * Price every line and total the bill.
 *
 * `unit_price` may be quoted tax-INCLUSIVE by the vendor, so it is normalised to
 * a net rate with money.js netUnitPrice — the same back-calculation sales use,
 * which keeps a purchase and a sale of the same goods internally consistent.
 *
 * The bill-level discount reduces the taxable base, so tax is scaled by
 * discountedNet/subtotal exactly as routes/bills.js does. Keeping this rule
 * identical on both sides means the P&L never disagrees with itself.
 */
function computeTotals(lines, opts) {
  const { gstEnabled, isInterstate, discountAmount, roundOff } = opts;

  const priced = lines.map((l, idx) => {
    // GST off -> tax is ignored ENTIRELY, even if the item still carries a
    // stale rate. Without this a disabled-GST bill would create phantom ITC.
    const rate = gstEnabled && l.tax_rate != null && l.tax_rate !== ''
      ? parseFloat(l.tax_rate)
      : null;
    const qty = parseFloat(l.quantity);
    const net = netUnitPrice(parseFloat(l.unit_price), rate, !!l.price_inclusive_tax);
    const lineNet = net * qty;
    const lineTax = rate ? lineNet * (rate / 100) : 0;
    return {
      item_id: l.item_id || null,
      variant_id: l.variant_id || null,
      raw_material_id: l.raw_material_id || null,
      item_name: String(l.name || '').trim().slice(0, 200),
      quantity: qty,
      unit: l.unit ? String(l.unit).slice(0, 20) : null,
      unit_price: net,
      tax_rate: rate,
      hsn_code: l.hsn_code ? String(l.hsn_code).trim().slice(0, 10) : null,
      line_total: r2(lineNet + lineTax),
      sort_order: idx,
      _net: lineNet,
      _tax: lineTax,
    };
  });

  const subtotal = priced.reduce((s, l) => s + l._net, 0);
  const rawTax = priced.reduce((s, l) => s + l._tax, 0);
  const discount = Math.min(Math.max(parseFloat(discountAmount) || 0, 0), subtotal);
  const taxAmount = subtotal > 0 ? rawTax * ((subtotal - discount) / subtotal) : 0;

  let cgst = 0, sgst = 0, igst = 0;
  if (isInterstate) {
    igst = r2(taxAmount);
  } else {
    [cgst, sgst] = gstHalves(taxAmount);
  }

  const round = parseFloat(roundOff) || 0;
  const total = r2(subtotal - discount + r2(taxAmount) + round);

  return {
    lines: priced,
    subtotal: r2(subtotal),
    taxAmount: r2(taxAmount),
    cgst, sgst, igst,
    discount: r2(discount),
    roundOff: round,
    total,
  };
}

/** Batch-resolve the item / variant / raw-material ids a bill's lines refer to. */
async function resolveTargets(transaction, businessId, lines) {
  const itemIds = [...new Set(lines.map((l) => l.item_id).filter(Boolean))];
  const varIds = [...new Set(lines.map((l) => l.variant_id).filter(Boolean))];
  const rawIds = [...new Set(lines.map((l) => l.raw_material_id).filter(Boolean))];

  const fetch = async (ids, query) => {
    const found = new Set();
    for (const id of ids) {
      const r = await transaction.request()
        .input('id', sql.UniqueIdentifier, id)
        .input('business_id', sql.UniqueIdentifier, businessId)
        .query(query);
      if (r.recordset.length) found.add(id);
    }
    return found;
  };

  const items = await fetch(itemIds,
    `SELECT id FROM items WHERE id = @id AND business_id = @business_id`);
  // Variants are scoped through their parent item's business.
  const variants = await fetch(varIds,
    `SELECT v.id FROM item_variants v
     INNER JOIN items i ON i.id = v.item_id
     WHERE v.id = @id AND i.business_id = @business_id`);
  const raws = await fetch(rawIds,
    `SELECT id FROM raw_materials WHERE id = @id AND business_id = @business_id`);

  for (const id of itemIds) if (!items.has(id)) return `Unknown item: ${id}`;
  for (const id of varIds) if (!variants.has(id)) return `Unknown size/variant: ${id}`;
  for (const id of rawIds) if (!raws.has(id)) return `Unknown raw material: ${id}`;
  return null;
}

/**
 * Move a line's stock. [sign] is +1 when receiving goods, -1 when reversing an
 * edit or delete.
 *
 * The `stock_quantity IS NOT NULL` guard is load-bearing: NULL means the owner
 * opted OUT of tracking that target, and receiving a purchase must not silently
 * opt them back in. Mirrors restoreLineStock in routes/bills.js.
 *
 * Unlike the sale-side decrement there is no `>= @qty` guard, so rowsAffected 0
 * means "untracked", NOT a failure — never treat it as one.
 */
async function applyLineStock(transaction, businessId, li, sign) {
  const qty = sign * Number(li.quantity);
  if (li.variant_id) {
    await transaction.request()
      .input('id', sql.UniqueIdentifier, li.variant_id)
      .input('qty', sql.Decimal(10, 2), qty)
      .query(`UPDATE item_variants SET stock_quantity = stock_quantity + @qty
              WHERE id = @id AND stock_quantity IS NOT NULL`);
  } else if (li.item_id) {
    await transaction.request()
      .input('id', sql.UniqueIdentifier, li.item_id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('qty', sql.Decimal(10, 2), qty)
      .query(`UPDATE items SET stock_quantity = stock_quantity + @qty
              WHERE id = @id AND business_id = @business_id
                AND stock_quantity IS NOT NULL`);
  } else if (li.raw_material_id) {
    await transaction.request()
      .input('id', sql.UniqueIdentifier, li.raw_material_id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('qty', sql.Decimal(10, 2), qty)
      .query(`UPDATE raw_materials SET stock_quantity = stock_quantity + @qty
              WHERE id = @id AND business_id = @business_id
                AND stock_quantity IS NOT NULL`);
  }
  // No target -> a service/freight line; nothing to move.
}

const HEADER_COLS = `
  vb.id, vb.vendor_name, vb.vendor_gstin, vb.vendor_state,
  vb.invoice_number, vb.invoice_date,
  vb.subtotal, vb.tax_amount, vb.cgst_amount, vb.sgst_amount,
  vb.igst_amount, vb.cess_amount, vb.discount_amount, vb.round_off, vb.total,
  vb.is_interstate, vb.itc_eligible, vb.reverse_charge,
  vb.payment_mode, vb.payment_status, vb.amount_paid, vb.notes,
  vb.stock_applied, vb.created_at, vb.updated_at`;

function shapeHeader(row) {
  return {
    id: row.id,
    vendor_name: row.vendor_name,
    vendor_gstin: row.vendor_gstin,
    vendor_state: row.vendor_state,
    invoice_number: row.invoice_number,
    invoice_date: row.invoice_date.toISOString().slice(0, 10),
    subtotal: parseFloat(row.subtotal),
    tax_amount: parseFloat(row.tax_amount),
    cgst_amount: parseFloat(row.cgst_amount),
    sgst_amount: parseFloat(row.sgst_amount),
    igst_amount: parseFloat(row.igst_amount),
    cess_amount: parseFloat(row.cess_amount),
    discount_amount: parseFloat(row.discount_amount),
    round_off: parseFloat(row.round_off),
    total: parseFloat(row.total),
    is_interstate: !!row.is_interstate,
    itc_eligible: !!row.itc_eligible,
    reverse_charge: !!row.reverse_charge,
    payment_mode: row.payment_mode,
    payment_status: row.payment_status,
    amount_paid: parseFloat(row.amount_paid),
    notes: row.notes,
    stock_applied: !!row.stock_applied,
    created_at: row.created_at,
    created_by_name: row.created_by_name,
    line_count: row.line_count != null ? Number(row.line_count) : undefined,
  };
}

async function fetchVendorBill(id, businessId) {
  const head = await pool.request()
    .input('id', sql.UniqueIdentifier, id)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT ${HEADER_COLS}, u.name AS created_by_name
            FROM vendor_bills vb
            LEFT JOIN users u ON u.id = vb.created_by_user_id
            WHERE vb.id = @id AND vb.business_id = @business_id`);
  if (!head.recordset.length) return null;

  const lines = await pool.request()
    .input('id', sql.UniqueIdentifier, id)
    .query(`SELECT id, item_id, variant_id, raw_material_id, item_name,
                   quantity, unit, unit_price, tax_rate, hsn_code,
                   line_total, sort_order
            FROM vendor_bill_items
            WHERE vendor_bill_id = @id ORDER BY sort_order`);

  return {
    ...shapeHeader(head.recordset[0]),
    lines: lines.recordset.map((l) => ({
      id: l.id,
      item_id: l.item_id,
      variant_id: l.variant_id,
      raw_material_id: l.raw_material_id,
      item_name: l.item_name,
      quantity: parseFloat(l.quantity),
      unit: l.unit,
      unit_price: parseFloat(l.unit_price),
      tax_rate: l.tax_rate != null ? parseFloat(l.tax_rate) : null,
      hsn_code: l.hsn_code,
      line_total: parseFloat(l.line_total),
      sort_order: l.sort_order,
    })),
  };
}

/** Read the business flags a purchase depends on. Called INSIDE the transaction
 *  so inventory/GST cannot be toggled between the read and the write. */
async function readBusinessFlags(transaction, businessId) {
  const r = await transaction.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT inventory_enabled, gst_enabled, gst_number, state
            FROM businesses WHERE id = @business_id`);
  const b = r.recordset[0] || {};
  return {
    inventoryEnabled: !!b.inventory_enabled,
    gstEnabled: !!b.gst_enabled,
    gstin: b.gst_number || '',
    state: b.state || '',
  };
}

/** Normalise + validate the header fields shared by POST and PUT. */
function readHeader(body) {
  const vendorName = String(body.vendor_name || '').trim();
  if (!vendorName) return { error: 'Vendor name is required' };

  const invoiceNumber = String(body.invoice_number || '').trim();
  if (!invoiceNumber) return { error: 'Invoice number is required' };

  const invoiceDate = String(body.invoice_date || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(invoiceDate)) {
    return { error: 'Invoice date must be YYYY-MM-DD' };
  }

  let gstin = body.vendor_gstin ? String(body.vendor_gstin).trim().toUpperCase() : null;
  if (gstin) {
    // Reject a malformed GSTIN outright: it silently breaks GSTR-2B matching
    // later, which is far more expensive to debug than a form error now.
    if (!GSTIN_RE.test(gstin)) return { error: 'Vendor GSTIN is not valid' };
  } else {
    gstin = null;
  }

  const status = String(body.payment_status || 'paid');
  if (!['paid', 'unpaid', 'partial'].includes(status)) {
    return { error: 'Payment status must be paid, unpaid or partial' };
  }

  return {
    vendorName: vendorName.slice(0, 200),
    gstin,
    vendorState: body.vendor_state ? String(body.vendor_state).trim().slice(0, 100) : null,
    invoiceNumber: invoiceNumber.slice(0, 50),
    invoiceDate,
    paymentMode: String(body.payment_mode || 'cash').slice(0, 20),
    paymentStatus: status,
    amountPaid: parseFloat(body.amount_paid) || 0,
    notes: body.notes ? String(body.notes).trim().slice(0, 500) : null,
    itcEligible: body.itc_eligible === undefined ? true : !!body.itc_eligible,
    reverseCharge: !!body.reverse_charge,
  };
}

/** True when a duplicate-key violation tripped the unique invoice index. */
const isDuplicateKey = (err) => err && (err.number === 2601 || err.number === 2627);

// ---------------------------------------------------------------------------
// GET /api/vendor-bills/vendors
//
// Declared BEFORE '/:id' — otherwise "vendors" is parsed as a bill id and the
// UniqueIdentifier bind throws.
// ---------------------------------------------------------------------------
router.get('/vendors', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT vendor_name AS name,
               MAX(vendor_gstin) AS gstin,
               MAX(vendor_state) AS state,
               COUNT(*) AS bill_count
        FROM vendor_bills
        WHERE business_id = @business_id
        GROUP BY vendor_name
        ORDER BY COUNT(*) DESC, vendor_name ASC`);
    return res.json(result.recordset.map((r) => ({
      name: r.name,
      gstin: r.gstin,
      state: r.state,
      bill_count: Number(r.bill_count),
    })));
  } catch (err) {
    logger.error({ err }, 'List vendors error');
    return res.status(500).json({ error: 'Failed to load vendors' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/vendor-bills?from&to&vendor&payment_status
// ---------------------------------------------------------------------------
router.get('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { from, to, vendor, payment_status } = req.query;

    let query = `
      SELECT ${HEADER_COLS}, u.name AS created_by_name,
             (SELECT COUNT(*) FROM vendor_bill_items vbi
              WHERE vbi.vendor_bill_id = vb.id) AS line_count
      FROM vendor_bills vb
      LEFT JOIN users u ON u.id = vb.created_by_user_id
      WHERE vb.business_id = @business_id`;

    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (from) { query += ` AND vb.invoice_date >= @from`; request.input('from', sql.Date, from); }
    if (to) { query += ` AND vb.invoice_date <= @to`; request.input('to', sql.Date, to); }
    if (vendor) {
      query += ` AND vb.vendor_name LIKE @vendor`;
      request.input('vendor', sql.NVarChar(200), `%${vendor}%`);
    }
    if (payment_status) {
      query += ` AND vb.payment_status = @payment_status`;
      request.input('payment_status', sql.NVarChar(20), payment_status);
    }
    query += ` ORDER BY vb.invoice_date DESC, vb.created_at DESC`;

    const result = await request.query(query);
    return res.json(result.recordset.map(shapeHeader));
  } catch (err) {
    logger.error({ err }, 'List vendor bills error');
    return res.status(500).json({ error: 'Failed to load vendor bills' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/vendor-bills/:id
// ---------------------------------------------------------------------------
router.get('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const bill = await fetchVendorBill(req.params.id, req.user.business_id);
    if (!bill) return res.status(404).json({ error: 'Vendor bill not found' });
    return res.json(bill);
  } catch (err) {
    logger.error({ err }, 'Get vendor bill error');
    return res.status(500).json({ error: 'Failed to load vendor bill' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/vendor-bills
// ---------------------------------------------------------------------------
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const head = readHeader(req.body);
    if (head.error) return res.status(400).json({ error: head.error });

    const lineError = validateLines(req.body.lines);
    if (lineError) return res.status(400).json({ error: lineError });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      const flags = await readBusinessFlags(transaction, req.user.business_id);

      const targetError = await resolveTargets(
        transaction, req.user.business_id, req.body.lines);
      if (targetError) {
        await transaction.rollback();
        return res.status(400).json({ error: targetError });
      }

      // Interstate is derived from the state codes that lead each GSTIN, with
      // an explicit client value winning (bill-to / ship-to cases differ).
      const derivedInterstate = !!(head.gstin && flags.gstin
        && head.gstin.slice(0, 2) !== flags.gstin.slice(0, 2));
      const isInterstate = req.body.is_interstate === undefined
        ? derivedInterstate
        : !!req.body.is_interstate;

      const totals = computeTotals(req.body.lines, {
        gstEnabled: flags.gstEnabled,
        isInterstate,
        discountAmount: req.body.discount_amount,
        roundOff: req.body.round_off,
      });

      const inserted = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('vendor_name', sql.NVarChar(200), head.vendorName)
        .input('vendor_gstin', sql.NVarChar(15), head.gstin)
        .input('vendor_state', sql.NVarChar(100), head.vendorState)
        .input('invoice_number', sql.NVarChar(50), head.invoiceNumber)
        .input('invoice_date', sql.Date, head.invoiceDate)
        .input('subtotal', sql.Decimal(12, 2), totals.subtotal)
        .input('tax_amount', sql.Decimal(12, 2), totals.taxAmount)
        .input('cgst_amount', sql.Decimal(12, 2), totals.cgst)
        .input('sgst_amount', sql.Decimal(12, 2), totals.sgst)
        .input('igst_amount', sql.Decimal(12, 2), totals.igst)
        .input('discount_amount', sql.Decimal(12, 2), totals.discount)
        .input('round_off', sql.Decimal(10, 2), totals.roundOff)
        .input('total', sql.Decimal(12, 2), totals.total)
        .input('is_interstate', sql.Bit, isInterstate ? 1 : 0)
        .input('itc_eligible', sql.Bit, head.itcEligible ? 1 : 0)
        .input('reverse_charge', sql.Bit, head.reverseCharge ? 1 : 0)
        .input('payment_mode', sql.NVarChar(20), head.paymentMode)
        .input('payment_status', sql.NVarChar(20), head.paymentStatus)
        .input('amount_paid', sql.Decimal(12, 2), head.amountPaid)
        .input('notes', sql.NVarChar(500), head.notes)
        .input('stock_applied', sql.Bit, flags.inventoryEnabled ? 1 : 0)
        .input('created_by_user_id', sql.UniqueIdentifier, req.user.user_id)
        .query(`
          INSERT INTO vendor_bills (
            business_id, vendor_name, vendor_gstin, vendor_state,
            invoice_number, invoice_date, subtotal, tax_amount,
            cgst_amount, sgst_amount, igst_amount,
            discount_amount, round_off, total,
            is_interstate, itc_eligible, reverse_charge,
            payment_mode, payment_status, amount_paid, notes,
            stock_applied, created_by_user_id)
          OUTPUT INSERTED.id
          VALUES (
            @business_id, @vendor_name, @vendor_gstin, @vendor_state,
            @invoice_number, @invoice_date, @subtotal, @tax_amount,
            @cgst_amount, @sgst_amount, @igst_amount,
            @discount_amount, @round_off, @total,
            @is_interstate, @itc_eligible, @reverse_charge,
            @payment_mode, @payment_status, @amount_paid, @notes,
            @stock_applied, @created_by_user_id)`);

      const billId = inserted.recordset[0].id;

      // mssql requests are single-use: a fresh one per statement.
      for (const li of totals.lines) {
        await transaction.request()
          .input('vendor_bill_id', sql.UniqueIdentifier, billId)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('variant_id', sql.UniqueIdentifier, li.variant_id)
          .input('raw_material_id', sql.UniqueIdentifier, li.raw_material_id)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit', sql.NVarChar(20), li.unit)
          .input('unit_price', sql.Decimal(12, 4), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('hsn_code', sql.NVarChar(10), li.hsn_code)
          .input('line_total', sql.Decimal(12, 2), li.line_total)
          .input('sort_order', sql.Int, li.sort_order)
          .query(`
            INSERT INTO vendor_bill_items (
              vendor_bill_id, item_id, variant_id, raw_material_id, item_name,
              quantity, unit, unit_price, tax_rate, hsn_code, line_total, sort_order)
            VALUES (
              @vendor_bill_id, @item_id, @variant_id, @raw_material_id, @item_name,
              @quantity, @unit, @unit_price, @tax_rate, @hsn_code, @line_total, @sort_order)`);
      }

      if (flags.inventoryEnabled) {
        for (const li of totals.lines) {
          await applyLineStock(transaction, req.user.business_id, li, +1);
        }
      }

      await transaction.commit();

      const bill = await fetchVendorBill(billId, req.user.business_id);
      audit.logVendorBillCreated(
        req.user,
        { ...bill, business_id: req.user.business_id },
        totals.lines.length,
      ).catch((err) => logger.error({ err }, 'audit vendor_bill_created failed'));

      return res.status(201).json(bill);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    if (isDuplicateKey(err)) {
      return res.status(409).json({
        error: 'This invoice number is already recorded for this vendor',
      });
    }
    logger.error({ err }, 'Create vendor bill error');
    return res.status(500).json({ error: 'Failed to save vendor bill' });
  }
});

// ---------------------------------------------------------------------------
// PUT /api/vendor-bills/:id — full replace (header + lines)
// ---------------------------------------------------------------------------
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const head = readHeader(req.body);
    if (head.error) return res.status(400).json({ error: head.error });

    const lineError = validateLines(req.body.lines);
    if (lineError) return res.status(400).json({ error: lineError });

    const before = await fetchVendorBill(req.params.id, req.user.business_id);
    if (!before) return res.status(404).json({ error: 'Vendor bill not found' });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      const flags = await readBusinessFlags(transaction, req.user.business_id);

      const targetError = await resolveTargets(
        transaction, req.user.business_id, req.body.lines);
      if (targetError) {
        await transaction.rollback();
        return res.status(400).json({ error: targetError });
      }

      // Reverse whatever stock this bill previously added, but only if it was
      // actually applied — inventory may have been off when it was created.
      if (before.stock_applied) {
        for (const li of before.lines) {
          await applyLineStock(transaction, req.user.business_id, li, -1);
        }
      }

      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`DELETE FROM vendor_bill_items WHERE vendor_bill_id = @id`);

      const derivedInterstate = !!(head.gstin && flags.gstin
        && head.gstin.slice(0, 2) !== flags.gstin.slice(0, 2));
      const isInterstate = req.body.is_interstate === undefined
        ? derivedInterstate
        : !!req.body.is_interstate;

      const totals = computeTotals(req.body.lines, {
        gstEnabled: flags.gstEnabled,
        isInterstate,
        discountAmount: req.body.discount_amount,
        roundOff: req.body.round_off,
      });

      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('vendor_name', sql.NVarChar(200), head.vendorName)
        .input('vendor_gstin', sql.NVarChar(15), head.gstin)
        .input('vendor_state', sql.NVarChar(100), head.vendorState)
        .input('invoice_number', sql.NVarChar(50), head.invoiceNumber)
        .input('invoice_date', sql.Date, head.invoiceDate)
        .input('subtotal', sql.Decimal(12, 2), totals.subtotal)
        .input('tax_amount', sql.Decimal(12, 2), totals.taxAmount)
        .input('cgst_amount', sql.Decimal(12, 2), totals.cgst)
        .input('sgst_amount', sql.Decimal(12, 2), totals.sgst)
        .input('igst_amount', sql.Decimal(12, 2), totals.igst)
        .input('discount_amount', sql.Decimal(12, 2), totals.discount)
        .input('round_off', sql.Decimal(10, 2), totals.roundOff)
        .input('total', sql.Decimal(12, 2), totals.total)
        .input('is_interstate', sql.Bit, isInterstate ? 1 : 0)
        .input('itc_eligible', sql.Bit, head.itcEligible ? 1 : 0)
        .input('reverse_charge', sql.Bit, head.reverseCharge ? 1 : 0)
        .input('payment_mode', sql.NVarChar(20), head.paymentMode)
        .input('payment_status', sql.NVarChar(20), head.paymentStatus)
        .input('amount_paid', sql.Decimal(12, 2), head.amountPaid)
        .input('notes', sql.NVarChar(500), head.notes)
        .input('stock_applied', sql.Bit, flags.inventoryEnabled ? 1 : 0)
        .query(`
          UPDATE vendor_bills SET
            vendor_name = @vendor_name, vendor_gstin = @vendor_gstin,
            vendor_state = @vendor_state, invoice_number = @invoice_number,
            invoice_date = @invoice_date, subtotal = @subtotal,
            tax_amount = @tax_amount, cgst_amount = @cgst_amount,
            sgst_amount = @sgst_amount, igst_amount = @igst_amount,
            discount_amount = @discount_amount, round_off = @round_off,
            total = @total, is_interstate = @is_interstate,
            itc_eligible = @itc_eligible, reverse_charge = @reverse_charge,
            payment_mode = @payment_mode, payment_status = @payment_status,
            amount_paid = @amount_paid, notes = @notes,
            stock_applied = @stock_applied, updated_at = GETUTCDATE()
          WHERE id = @id AND business_id = @business_id`);

      for (const li of totals.lines) {
        await transaction.request()
          .input('vendor_bill_id', sql.UniqueIdentifier, req.params.id)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('variant_id', sql.UniqueIdentifier, li.variant_id)
          .input('raw_material_id', sql.UniqueIdentifier, li.raw_material_id)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('unit', sql.NVarChar(20), li.unit)
          .input('unit_price', sql.Decimal(12, 4), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('hsn_code', sql.NVarChar(10), li.hsn_code)
          .input('line_total', sql.Decimal(12, 2), li.line_total)
          .input('sort_order', sql.Int, li.sort_order)
          .query(`
            INSERT INTO vendor_bill_items (
              vendor_bill_id, item_id, variant_id, raw_material_id, item_name,
              quantity, unit, unit_price, tax_rate, hsn_code, line_total, sort_order)
            VALUES (
              @vendor_bill_id, @item_id, @variant_id, @raw_material_id, @item_name,
              @quantity, @unit, @unit_price, @tax_rate, @hsn_code, @line_total, @sort_order)`);
      }

      if (flags.inventoryEnabled) {
        for (const li of totals.lines) {
          await applyLineStock(transaction, req.user.business_id, li, +1);
        }
      }

      await transaction.commit();

      const after = await fetchVendorBill(req.params.id, req.user.business_id);
      audit.logVendorBillUpdated(
        req.user,
        before,
        { ...after, business_id: req.user.business_id },
      ).catch((err) => logger.error({ err }, 'audit vendor_bill_updated failed'));

      return res.json(after);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    if (isDuplicateKey(err)) {
      return res.status(409).json({
        error: 'This invoice number is already recorded for this vendor',
      });
    }
    logger.error({ err }, 'Update vendor bill error');
    return res.status(500).json({ error: 'Failed to update vendor bill' });
  }
});

// ---------------------------------------------------------------------------
// DELETE /api/vendor-bills/:id
// ---------------------------------------------------------------------------
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const before = await fetchVendorBill(req.params.id, req.user.business_id);
    if (!before) return res.status(404).json({ error: 'Vendor bill not found' });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      const flags = await readBusinessFlags(transaction, req.user.business_id);

      // Reversal can drive stock negative when the goods were already sold.
      // That is allowed on purpose — a purchase entered in error must stay
      // correctable — but it is worth a log line when it happens.
      if (before.stock_applied && flags.inventoryEnabled) {
        for (const li of before.lines) {
          await applyLineStock(transaction, req.user.business_id, li, -1);
        }
      }

      const del = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`DELETE FROM vendor_bills
                WHERE id = @id AND business_id = @business_id`);

      if (del.rowsAffected[0] === 0) {
        await transaction.rollback();
        return res.status(404).json({ error: 'Vendor bill not found' });
      }

      await transaction.commit();

      audit.logVendorBillDeleted(
        req.user,
        { ...before, business_id: req.user.business_id },
      ).catch((err) => logger.error({ err }, 'audit vendor_bill_deleted failed'));

      return res.json({ ok: true });
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    logger.error({ err }, 'Delete vendor bill error');
    return res.status(500).json({ error: 'Failed to delete vendor bill' });
  }
});

module.exports = router;
