// =============================================================================
// Quotations — a priced quote given to a customer before the sale.
//
// Deliberately NOT a bill: no stock moves and no invoice number is used, and
// nothing that reads `bills` (reports, history, credit) ever sees one. The
// app stores its cart snapshot (a Bill-shaped JSON, built by the billing page)
// verbatim; pricing is redone by the normal bill path when the quotation is
// converted — POST /api/bills with quotation_id, which marks it converted in
// the same transaction (routes/bills.js).
// =============================================================================
const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { validateNumber, validateText } = require('../validate');

const router = express.Router();

// Owners and cashiers quote; a captain only builds orders, a chef only cooks.
function canQuote(req, res, next) {
  if (req.user.role === 'server' || req.user.role === 'kitchen') {
    return res.status(403).json({ error: 'Only owners and cashiers can make quotations' });
  }
  next();
}

/// Checks a POST/PUT body. Returns { error } or the cleaned fields.
function cleanBody(body) {
  const { customer_name, customer_phone, total, snapshot } = body;
  const nameErr = validateText(customer_name, 'Customer name', 200);
  if (nameErr) return { error: nameErr };
  const phoneErr = validateText(customer_phone, 'Customer phone', 20);
  if (phoneErr) return { error: phoneErr };
  if (total === undefined || total === null || total === '') return { error: 'total is required' };
  const totalErr = validateNumber(total, 'Total');
  if (totalErr) return { error: totalErr };
  if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot) ||
      !Array.isArray(snapshot.items) || snapshot.items.length === 0) {
    return { error: 'snapshot must be a bill with at least one item' };
  }
  return {
    customerName: customer_name ? String(customer_name).trim() || null : null,
    customerPhone: customer_phone ? String(customer_phone).trim() || null : null,
    total: parseFloat(total),
    snapshot: JSON.stringify(snapshot),
  };
}

function format(row) {
  let snapshot = null;
  try { snapshot = JSON.parse(row.snapshot); } catch (_) { /* keep null */ }
  return {
    id: row.id,
    quotation_number: row.quotation_number,
    customer_name: row.customer_name,
    customer_phone: row.customer_phone,
    total: Number(row.total),
    created_at: row.created_at,
    snapshot,
  };
}

const COLUMNS = 'id, quotation_number, customer_name, customer_phone, total, created_at, snapshot';

// GET /api/quotations — the open ones, newest first. Converted ones leave the list.
router.get('/', requireAuth, canQuote, async (req, res) => {
  try {
    await poolConnect;
    const r = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT ${COLUMNS} FROM quotations
        WHERE business_id = @business_id AND status = 'open'
        ORDER BY created_at DESC
      `);
    return res.json(r.recordset.map(format));
  } catch (err) {
    logger.error({ err }, 'Get quotations error');
    return res.status(500).json({ error: 'Failed to fetch quotations' });
  }
});

// POST /api/quotations — { customer_name?, customer_phone?, total, snapshot }
router.post('/', requireAuth, canQuote, async (req, res) => {
  const body = cleanBody(req.body || {});
  if (body.error) return res.status(400).json({ error: body.error });
  try {
    await poolConnect;
    const transaction = pool.transaction();
    await transaction.begin();
    let row;
    try {
      // Same COUNT+1 scheme as generateBillNumber (routes/bills.js); the
      // UNIQUE (business_id, quotation_number) constraint backs it up.
      const cnt = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query('SELECT COUNT(*) AS cnt FROM quotations WITH (UPDLOCK, HOLDLOCK) WHERE business_id = @business_id');
      const number = 'QT-' + String(cnt.recordset[0].cnt + 1).padStart(4, '0');
      const ins = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('number', sql.NVarChar(50), number)
        .input('customer_name', sql.NVarChar(200), body.customerName)
        .input('customer_phone', sql.NVarChar(20), body.customerPhone)
        .input('total', sql.Decimal(10, 2), body.total)
        .input('snapshot', sql.NVarChar(sql.MAX), body.snapshot)
        .input('user_id', sql.UniqueIdentifier, req.user.user_id)
        .query(`
          INSERT INTO quotations (business_id, quotation_number, customer_name, customer_phone,
                                  total, snapshot, created_by_user_id)
          OUTPUT INSERTED.id, INSERTED.quotation_number, INSERTED.customer_name,
                 INSERTED.customer_phone, INSERTED.total, INSERTED.created_at, INSERTED.snapshot
          VALUES (@business_id, @number, @customer_name, @customer_phone,
                  @total, @snapshot, @user_id)
        `);
      row = ins.recordset[0];
      await transaction.commit();
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
    return res.status(201).json(format(row));
  } catch (err) {
    logger.error({ err }, 'Create quotation error');
    return res.status(500).json({ error: 'Failed to create quotation' });
  }
});

// PUT /api/quotations/:id — same body as POST; only while still open.
router.put('/:id', requireAuth, canQuote, async (req, res) => {
  const body = cleanBody(req.body || {});
  if (body.error) return res.status(400).json({ error: body.error });
  try {
    await poolConnect;
    const r = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('customer_name', sql.NVarChar(200), body.customerName)
      .input('customer_phone', sql.NVarChar(20), body.customerPhone)
      .input('total', sql.Decimal(10, 2), body.total)
      .input('snapshot', sql.NVarChar(sql.MAX), body.snapshot)
      .query(`
        UPDATE quotations
        SET customer_name = @customer_name, customer_phone = @customer_phone,
            total = @total, snapshot = @snapshot, updated_at = SYSUTCDATETIME()
        OUTPUT INSERTED.id, INSERTED.quotation_number, INSERTED.customer_name,
               INSERTED.customer_phone, INSERTED.total, INSERTED.created_at, INSERTED.snapshot
        WHERE id = @id AND business_id = @business_id AND status = 'open'
      `);
    if (r.recordset.length === 0) {
      return res.status(409).json({ error: 'Quotation not found or already converted' });
    }
    return res.json(format(r.recordset[0]));
  } catch (err) {
    logger.error({ err }, 'Update quotation error');
    return res.status(500).json({ error: 'Failed to update quotation' });
  }
});

// DELETE /api/quotations/:id — a quote that went nowhere. Converted ones stay
// (their bill points back at them).
router.delete('/:id', requireAuth, canQuote, async (req, res) => {
  try {
    await poolConnect;
    const r = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        DELETE FROM quotations
        WHERE id = @id AND business_id = @business_id AND status = 'open'
      `);
    if (!r.rowsAffected[0]) return res.status(404).json({ error: 'Quotation not found' });
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete quotation error');
    return res.status(500).json({ error: 'Failed to delete quotation' });
  }
});

module.exports = router;
