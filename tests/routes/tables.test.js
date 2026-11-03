const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const TABLE_ID = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

const sampleTable = {
  id: TABLE_ID,
  business_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  table_number: 'T1',
  floor_x: 0,
  floor_y: 0,
  status: 'empty',
  created_at: new Date().toISOString(),
  active_bill_id: null,
};

beforeEach(() => {
  mockRequest.reset();
  mockRequest.query.mockImplementation(function () {
    return Promise.resolve({ recordset: this.recordset, rowsAffected: this.rowsAffected });
  });
});

// ------------------------------------------------------------------
// Auth guard
// ------------------------------------------------------------------
describe('tables — auth guard', () => {
  test('GET /api/tables returns 401 without token', async () => {
    const res = await request(app).get('/api/tables');
    expect(res.status).toBe(401);
  });
});

// ------------------------------------------------------------------
// GET /api/tables
// ------------------------------------------------------------------
describe('GET /api/tables', () => {
  test('returns list of tables', async () => {
    mockRequest.recordset = [sampleTable];
    const res = await request(app)
      .get('/api/tables')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0].table_number).toBe('T1');
  });

  test('returns empty array when no tables', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/tables')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  test('cashier can list tables', async () => {
    mockRequest.recordset = [sampleTable];
    const res = await request(app)
      .get('/api/tables')
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(200);
  });
});

// ------------------------------------------------------------------
// POST /api/tables
// ------------------------------------------------------------------
describe('POST /api/tables', () => {
  test('creates table and returns 201', async () => {
    mockRequest.recordset = [sampleTable];
    const res = await request(app)
      .post('/api/tables')
      .set(authHeader({ role: 'owner' }))
      .send({ table_number: 'T1' });
    expect(res.status).toBe(201);
    expect(res.body.table_number).toBe('T1');
  });

  test('returns 400 when table_number is missing', async () => {
    const res = await request(app)
      .post('/api/tables')
      .set(authHeader({ role: 'owner' }))
      .send({});
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/table_number/);
  });

  test('returns 403 for non-owner', async () => {
    const res = await request(app)
      .post('/api/tables')
      .set(authHeader({ role: 'cashier' }))
      .send({ table_number: 'T1' });
    expect(res.status).toBe(403);
  });

  test('creates table with floor coordinates', async () => {
    mockRequest.recordset = [{ ...sampleTable, floor_x: 10, floor_y: 20 }];
    const res = await request(app)
      .post('/api/tables')
      .set(authHeader({ role: 'owner' }))
      .send({ table_number: 'T2', floor_x: 10, floor_y: 20 });
    expect(res.status).toBe(201);
    expect(res.body.floor_x).toBe(10);
  });
});

// ------------------------------------------------------------------
// PUT /api/tables/:id
// ------------------------------------------------------------------
describe('PUT /api/tables/:id', () => {
  test('updates table status', async () => {
    mockRequest.recordset = [{ ...sampleTable, status: 'occupied' }];
    mockRequest.rowsAffected = [1];
    const res = await request(app)
      .put(`/api/tables/${TABLE_ID}`)
      .set(authHeader())
      .send({ status: 'occupied' });
    expect(res.status).toBe(200);
  });

  test('returns 400 with no fields provided', async () => {
    const res = await request(app)
      .put(`/api/tables/${TABLE_ID}`)
      .set(authHeader())
      .send({});
    expect(res.status).toBe(400);
  });

  test('returns 400 for invalid status', async () => {
    const res = await request(app)
      .put(`/api/tables/${TABLE_ID}`)
      .set(authHeader())
      .send({ status: 'flying' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/status/);
  });

  test('returns 404 when table not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .put(`/api/tables/${TABLE_ID}`)
      .set(authHeader())
      .send({ status: 'empty' });
    expect(res.status).toBe(404);
  });
});

// ------------------------------------------------------------------
// DELETE /api/tables/:id
// ------------------------------------------------------------------
describe('DELETE /api/tables/:id', () => {
  test('returns 403 for non-owner', async () => {
    const res = await request(app)
      .delete(`/api/tables/${TABLE_ID}`)
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('deletes table and returns success', async () => {
    // Query 1: active bill check (none found) — Query 2: DELETE (1 row affected)
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });
    const res = await request(app)
      .delete(`/api/tables/${TABLE_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('returns 404 when table not found', async () => {
    // Query 1: active bill check — Query 2: DELETE (0 rows affected)
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .delete(`/api/tables/${TABLE_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(404);
  });
});
