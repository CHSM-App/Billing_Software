const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const EXPENSE_ID = '11111111-1111-1111-1111-111111111111';

const sampleExpense = {
  id: EXPENSE_ID,
  category: 'Rent',
  description: 'Monthly rent',
  amount: 5000,
  payment_mode: 'cash',
  expense_date: { toISOString: () => '2024-01-15T00:00:00.000Z' },
  created_at: new Date().toISOString(),
  created_by_name: 'Owner',
};

beforeEach(() => {
  mockRequest.reset();
});

// ------------------------------------------------------------------
// Auth + role guard
// ------------------------------------------------------------------
describe('expenses — auth guard', () => {
  test('GET /api/expenses returns 401 without token', async () => {
    const res = await request(app).get('/api/expenses');
    expect(res.status).toBe(401);
  });

  test('GET /api/expenses returns 403 for non-owner', async () => {
    const res = await request(app)
      .get('/api/expenses')
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('POST /api/expenses returns 403 for non-owner', async () => {
    const res = await request(app)
      .post('/api/expenses')
      .set(authHeader({ role: 'cashier' }))
      .send({ category: 'Rent', amount: 1000 });
    expect(res.status).toBe(403);
  });
});

// ------------------------------------------------------------------
// GET /api/expenses
// ------------------------------------------------------------------
describe('GET /api/expenses', () => {
  test('returns list of expenses', async () => {
    mockRequest.recordset = [sampleExpense];
    const res = await request(app)
      .get('/api/expenses')
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0].category).toBe('Rent');
    expect(typeof res.body[0].amount).toBe('number');
  });

  test('returns empty array when no expenses', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/expenses')
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  test('filters by date range', async () => {
    mockRequest.recordset = [sampleExpense];
    const res = await request(app)
      .get('/api/expenses?from=2024-01-01&to=2024-01-31')
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
  });

  test('filters by category', async () => {
    mockRequest.recordset = [sampleExpense];
    const res = await request(app)
      .get('/api/expenses?category=Rent')
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
  });
});

// ------------------------------------------------------------------
// POST /api/expenses
// ------------------------------------------------------------------
describe('POST /api/expenses', () => {
  test('creates expense and returns 201', async () => {
    mockRequest.recordset = [{
      id: EXPENSE_ID,
      category: 'Rent',
      description: 'Monthly rent',
      amount: 5000,
      payment_mode: 'cash',
      expense_date: { toISOString: () => '2024-01-15T00:00:00.000Z' },
      created_at: new Date().toISOString(),
    }];
    const res = await request(app)
      .post('/api/expenses')
      .set(authHeader({ role: 'owner' }))
      .send({ category: 'Rent', amount: 5000, description: 'Monthly rent' });
    expect(res.status).toBe(201);
    expect(res.body.category).toBe('Rent');
    expect(res.body.amount).toBe(5000);
  });

  test('returns 400 when category is missing', async () => {
    const res = await request(app)
      .post('/api/expenses')
      .set(authHeader({ role: 'owner' }))
      .send({ amount: 5000 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/category/);
  });

  test('returns 400 when amount is missing', async () => {
    const res = await request(app)
      .post('/api/expenses')
      .set(authHeader({ role: 'owner' }))
      .send({ category: 'Rent' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/amount/);
  });

  test('returns 400 for zero amount', async () => {
    const res = await request(app)
      .post('/api/expenses')
      .set(authHeader({ role: 'owner' }))
      .send({ category: 'Rent', amount: 0 });
    expect(res.status).toBe(400);
  });

  test('returns 400 for negative amount', async () => {
    const res = await request(app)
      .post('/api/expenses')
      .set(authHeader({ role: 'owner' }))
      .send({ category: 'Rent', amount: -100 });
    expect(res.status).toBe(400);
  });

  test('returns 400 for non-numeric amount', async () => {
    const res = await request(app)
      .post('/api/expenses')
      .set(authHeader({ role: 'owner' }))
      .send({ category: 'Rent', amount: 'abc' });
    expect(res.status).toBe(400);
  });
});

// ------------------------------------------------------------------
// DELETE /api/expenses/:id
// ------------------------------------------------------------------
describe('DELETE /api/expenses/:id', () => {
  test('returns 403 for non-owner', async () => {
    const res = await request(app)
      .delete(`/api/expenses/${EXPENSE_ID}`)
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('deletes expense and returns ok', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });
    const res = await request(app)
      .delete(`/api/expenses/${EXPENSE_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  test('returns 404 when expense not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .delete(`/api/expenses/${EXPENSE_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(404);
  });
});
