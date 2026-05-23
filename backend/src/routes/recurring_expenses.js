const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can access recurring expenses' });
  }
  next();
}

// GET /api/expenses/recurring
router.get('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT id, category, description, amount, payment_mode, created_at
        FROM recurring_expenses
        WHERE business_id = @business_id
        ORDER BY category
      `);
    return res.json(result.recordset.map(r => ({
      id: r.id,
      category: r.category,
      description: r.description,
      amount: parseFloat(r.amount),
      payment_mode: r.payment_mode,
      created_at: r.created_at,
    })));
  } catch (err) {
    console.error('Get recurring expenses error:', err);
    return res.status(500).json({ error: err.message || 'Failed to fetch recurring expenses' });
  }
});

// POST /api/expenses/recurring
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { category, description, amount, payment_mode } = req.body;
    if (!category || !amount) {
      return res.status(400).json({ error: 'category and amount are required' });
    }
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('category', sql.NVarChar(100), category.trim())
      .input('description', sql.NVarChar(500), description?.trim() || null)
      .input('amount', sql.Decimal(10, 2), parseFloat(amount))
      .input('payment_mode', sql.NVarChar(20), payment_mode || 'cash')
      .query(`
        INSERT INTO recurring_expenses (business_id, category, description, amount, payment_mode)
        OUTPUT INSERTED.id, INSERTED.category, INSERTED.description, INSERTED.amount,
               INSERTED.payment_mode, INSERTED.created_at
        VALUES (@business_id, @category, @description, @amount, @payment_mode)
      `);
    const r = result.recordset[0];
    return res.status(201).json({
      id: r.id,
      category: r.category,
      description: r.description,
      amount: parseFloat(r.amount),
      payment_mode: r.payment_mode,
      created_at: r.created_at,
    });
  } catch (err) {
    console.error('Create recurring expense error:', err);
    return res.status(500).json({ error: err.message || 'Failed to create recurring expense' });
  }
});

// PUT /api/expenses/recurring/:id
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { category, description, amount, payment_mode } = req.body;
    if (!category || !amount) {
      return res.status(400).json({ error: 'category and amount are required' });
    }
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('category', sql.NVarChar(100), category.trim())
      .input('description', sql.NVarChar(500), description?.trim() || null)
      .input('amount', sql.Decimal(10, 2), parseFloat(amount))
      .input('payment_mode', sql.NVarChar(20), payment_mode || 'cash')
      .query(`
        UPDATE recurring_expenses
        SET category = @category, description = @description,
            amount = @amount, payment_mode = @payment_mode
        OUTPUT INSERTED.id, INSERTED.category, INSERTED.description,
               INSERTED.amount, INSERTED.payment_mode, INSERTED.created_at
        WHERE id = @id AND business_id = @business_id
      `);
    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Not found' });
    }
    const r = result.recordset[0];
    return res.json({
      id: r.id,
      category: r.category,
      description: r.description,
      amount: parseFloat(r.amount),
      payment_mode: r.payment_mode,
      created_at: r.created_at,
    });
  } catch (err) {
    console.error('Update recurring expense error:', err);
    return res.status(500).json({ error: err.message || 'Failed to update' });
  }
});

// DELETE /api/expenses/recurring/:id
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`DELETE FROM recurring_expenses WHERE id = @id AND business_id = @business_id`);
    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Not found' });
    }
    return res.json({ ok: true });
  } catch (err) {
    console.error('Delete recurring expense error:', err);
    return res.status(500).json({ error: err.message || 'Failed to delete' });
  }
});

module.exports = router;
