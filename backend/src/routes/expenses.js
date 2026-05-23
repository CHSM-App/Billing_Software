const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can access expenses' });
  }
  next();
}

// GET /api/expenses?from=YYYY-MM-DD&to=YYYY-MM-DD&category=xxx
router.get('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { from, to, category } = req.query;

    let query = `
      SELECT e.id, e.category, e.description, e.amount, e.payment_mode,
             e.expense_date, e.created_at, u.name AS created_by_name
      FROM expenses e
      LEFT JOIN users u ON u.id = e.created_by_user_id
      WHERE e.business_id = @business_id
    `;
    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (from) {
      query += ` AND e.expense_date >= @from`;
      request.input('from', sql.Date, from);
    }
    if (to) {
      query += ` AND e.expense_date <= @to`;
      request.input('to', sql.Date, to);
    }
    if (category) {
      query += ` AND e.category = @category`;
      request.input('category', sql.NVarChar(100), category);
    }
    query += ` ORDER BY e.expense_date DESC, e.created_at DESC`;

    const result = await request.query(query);
    return res.json(result.recordset.map(row => ({
      id: row.id,
      category: row.category,
      description: row.description,
      amount: parseFloat(row.amount),
      payment_mode: row.payment_mode,
      expense_date: row.expense_date ? row.expense_date.toISOString().slice(0, 10) : null,
      created_at: row.created_at,
      created_by_name: row.created_by_name,
    })));
  } catch (err) {
    console.error('Get expenses error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch expenses' });
  }
});

// POST /api/expenses
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { category, description, amount, payment_mode, expense_date } = req.body;

    if (!category || !amount) {
      return res.status(400).json({ error: 'category and amount are required' });
    }
    if (isNaN(parseFloat(amount)) || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'amount must be a positive number' });
    }

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('category', sql.NVarChar(100), category.trim())
      .input('description', sql.NVarChar(500), description?.trim() || null)
      .input('amount', sql.Decimal(10, 2), parseFloat(amount))
      .input('payment_mode', sql.NVarChar(20), payment_mode || 'cash')
      .input('expense_date', sql.Date, expense_date || new Date().toISOString().slice(0, 10))
      .input('user_id', sql.UniqueIdentifier, req.user.user_id)
      .query(`
        INSERT INTO expenses (business_id, category, description, amount, payment_mode, expense_date, created_by_user_id)
        OUTPUT INSERTED.id, INSERTED.category, INSERTED.description, INSERTED.amount,
               INSERTED.payment_mode, INSERTED.expense_date, INSERTED.created_at
        VALUES (@business_id, @category, @description, @amount, @payment_mode, @expense_date, @user_id)
      `);

    const row = result.recordset[0];
    return res.status(201).json({
      id: row.id,
      category: row.category,
      description: row.description,
      amount: parseFloat(row.amount),
      payment_mode: row.payment_mode,
      expense_date: row.expense_date ? row.expense_date.toISOString().slice(0, 10) : null,
      created_at: row.created_at,
    });
  } catch (err) {
    console.error('Create expense error:', err);
    return res.status(500).json({ error: err.message || 'Failed to create expense' });
  }
});

// PUT /api/expenses/:id
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { category, description, amount, payment_mode, expense_date } = req.body;

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
      .input('expense_date', sql.Date, expense_date || new Date().toISOString().slice(0, 10))
      .query(`
        UPDATE expenses
        SET category = @category, description = @description, amount = @amount,
            payment_mode = @payment_mode, expense_date = @expense_date
        OUTPUT INSERTED.id, INSERTED.category, INSERTED.description, INSERTED.amount,
               INSERTED.payment_mode, INSERTED.expense_date, INSERTED.created_at
        WHERE id = @id AND business_id = @business_id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Expense not found' });
    }
    const row = result.recordset[0];
    return res.json({
      id: row.id,
      category: row.category,
      description: row.description,
      amount: parseFloat(row.amount),
      payment_mode: row.payment_mode,
      expense_date: row.expense_date ? row.expense_date.toISOString().slice(0, 10) : null,
      created_at: row.created_at,
    });
  } catch (err) {
    console.error('Update expense error:', err.message);
    return res.status(500).json({ error: 'Failed to update expense' });
  }
});

// DELETE /api/expenses/:id
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`DELETE FROM expenses WHERE id = @id AND business_id = @business_id`);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Expense not found' });
    }
    return res.json({ ok: true });
  } catch (err) {
    console.error('Delete expense error:', err.message);
    return res.status(500).json({ error: 'Failed to delete expense' });
  }
});

// GET /api/expenses/categories — distinct categories used by this business
router.get('/categories', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT DISTINCT category FROM expenses
        WHERE business_id = @business_id
        ORDER BY category
      `);
    return res.json(result.recordset.map(r => r.category));
  } catch (err) {
    return res.status(500).json({ error: 'Failed to fetch categories' });
  }
});

module.exports = router;
