const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

jest.mock('../../src/audit', () => ({
  logStaffAdded: jest.fn(),
  logStaffDeleted: jest.fn(),
}));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const STAFF_ID    = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

const sampleStaff = {
  id: STAFF_ID,
  business_id: BUSINESS_ID,
  name: 'Bob',
  phone: '9876543210',
  role: 'cashier',
  created_at: new Date().toISOString(),
};

beforeEach(() => {
  jest.clearAllMocks();
  mockRequest.reset();
  mockRequest.query.mockImplementation(function () {
    return Promise.resolve({ recordset: this.recordset, rowsAffected: this.rowsAffected });
  });
});

// ------------------------------------------------------------------
// Auth + role guard
// ------------------------------------------------------------------
describe('staff — auth guard', () => {
  test('GET /api/staff returns 401 without token', async () => {
    const res = await request(app).get('/api/staff');
    expect(res.status).toBe(401);
  });

  test('GET /api/staff returns 403 for non-owner', async () => {
    const res = await request(app)
      .get('/api/staff')
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('POST /api/staff returns 403 for non-owner', async () => {
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'cashier' }))
      .send({ name: 'Bob', phone: '9876543210', pin: '1234' });
    expect(res.status).toBe(403);
  });
});

// ------------------------------------------------------------------
// GET /api/staff
// ------------------------------------------------------------------
describe('GET /api/staff', () => {
  test('returns list of staff', async () => {
    mockRequest.recordset = [sampleStaff];
    const res = await request(app)
      .get('/api/staff')
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0].name).toBe('Bob');
  });

  test('returns empty array when no staff', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/staff')
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });
});

// ------------------------------------------------------------------
// POST /api/staff
// ------------------------------------------------------------------
describe('POST /api/staff', () => {
  test('creates staff and returns 201', async () => {
    // Two queries run: the duplicate-phone check (must be empty), then the
    // INSERT (returns the created row).
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [] })
      .mockResolvedValueOnce({ recordset: [sampleStaff] });
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Bob', phone: '9876543210', pin: '1234' });
    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Bob');
    expect(res.body.role).toBe('cashier');
  });

  test('returns 409 when phone already exists', async () => {
    // Duplicate-phone check finds an existing user.
    mockRequest.query.mockResolvedValueOnce({ recordset: [sampleStaff] });
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Bob', phone: '9876543210', pin: '1234' });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/already registered/i);
  });

  test('returns 400 when name is missing', async () => {
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ phone: '9876543210', pin: '1234' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/name/);
  });

  test('returns 400 when phone is missing', async () => {
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Bob', pin: '1234' });
    expect(res.status).toBe(400);
  });

  test('returns 400 when pin is missing', async () => {
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Bob', phone: '9876543210' });
    expect(res.status).toBe(400);
  });

  test('returns 400 for non-4-digit pin', async () => {
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Bob', phone: '9876543210', pin: '12' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/PIN/);
  });

  test('returns 400 for alphabetic pin', async () => {
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Bob', phone: '9876543210', pin: 'abcd' });
    expect(res.status).toBe(400);
  });

  test('returns 400 for non-10-digit phone', async () => {
    const res = await request(app)
      .post('/api/staff')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Bob', phone: '98765', pin: '1234' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Phone/);
  });
});

// ------------------------------------------------------------------
// DELETE /api/staff/:id
// ------------------------------------------------------------------
describe('DELETE /api/staff/:id', () => {
  test('returns 403 for non-owner', async () => {
    const res = await request(app)
      .delete(`/api/staff/${STAFF_ID}`)
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('deletes staff and returns success', async () => {
    mockRequest.query
      // snapshot lookup
      .mockResolvedValueOnce({ recordset: [sampleStaff], rowsAffected: [1] })
      // bills/expenses reference counts (none → deletable)
      .mockResolvedValueOnce({ recordset: [{ bill_count: 0, expense_count: 0 }], rowsAffected: [1] })
      // fcm_tokens delete + users delete (inside the transaction)
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .delete(`/api/staff/${STAFF_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('blocks deletion when staff has billing history', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleStaff], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ bill_count: 3, expense_count: 0 }], rowsAffected: [1] });

    const res = await request(app)
      .delete(`/api/staff/${STAFF_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(409);
  });

  test('returns 404 when staff member not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .delete(`/api/staff/${STAFF_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(404);
  });
});
