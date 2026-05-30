const request = require('supertest');

// ------------------------------------------------------------------
// Mock DB before requiring the app
// ------------------------------------------------------------------
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

// Mock whatsapp module to avoid real API calls
jest.mock('../../src/whatsapp', () => ({
  sendBillLink: jest.fn(),
  normalisePhone: jest.fn((p) => p),
}));

// Mock audit module — fire-and-forget, no need to test here
jest.mock('../../src/audit', () => ({
  logBillCreated: jest.fn(),
  logBillFinalized: jest.fn(),
  logBillItemsAdded: jest.fn(),
  logBillItemsUpdated: jest.fn(),
  logBillVoided: jest.fn(),
}));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const { sendBillLink, normalisePhone } = require('../../src/whatsapp');

const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const BILL_ID     = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const ITEM_ID     = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const USER_ID     = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

const sampleBill = {
  id: BILL_ID,
  business_id: BUSINESS_ID,
  bill_number: 'INV-0001',
  table_id: null,
  customer_name: 'Alice',
  customer_phone: '9876543210',
  subtotal: 100.00,
  tax_amount: 0.00,
  total: 100.00,
  payment_mode: 'cash',
  status: 'finalized',
  created_by_user_id: USER_ID,
  created_at: new Date().toISOString(),
  receipt_token: 'abcdef1234567890',
  items: [],
};

const sampleItem = {
  id: ITEM_ID,
  name: 'Rice',
  price: 50.00,
  tax_rate: null,
  stock_quantity: 100,
};

beforeEach(() => {
  // mockReset clears queued once-values AND the implementation
  mockRequest.query.mockReset();
  mockRequest.reset();
  // Restore default implementation
  mockRequest.query.mockImplementation(() =>
    Promise.resolve({ recordset: mockRequest.recordset, rowsAffected: mockRequest.rowsAffected })
  );
  // Re-apply clearAllMocks for other mocks (whatsapp, audit)
  jest.clearAllMocks();
  // Restore default implementation again after clearAllMocks
  mockRequest.query.mockImplementation(() =>
    Promise.resolve({ recordset: mockRequest.recordset, rowsAffected: mockRequest.rowsAffected })
  );
  normalisePhone.mockImplementation((p) => p);
});

// ------------------------------------------------------------------
// Auth guard
// ------------------------------------------------------------------
describe('bills — auth guard', () => {
  test('GET /api/bills returns 401 without token', async () => {
    const res = await request(app).get('/api/bills');
    expect(res.status).toBe(401);
  });

  test('POST /api/bills returns 401 without token', async () => {
    const res = await request(app).post('/api/bills').send({});
    expect(res.status).toBe(401);
  });
});

// ------------------------------------------------------------------
// GET /api/bills
// ------------------------------------------------------------------
describe('GET /api/bills', () => {
  test('returns list of bills for today', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .get('/api/bills')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  test('returns empty array when no bills', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/bills')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  test('returns 400 for invalid from date', async () => {
    const res = await request(app)
      .get('/api/bills?from=not-a-date')
      .set(authHeader());
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/from/);
  });

  test('returns 400 for invalid to date', async () => {
    const res = await request(app)
      .get('/api/bills?to=2024-13-99')
      .set(authHeader());
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/to/);
  });

  test('accepts valid date range', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .get('/api/bills?from=2024-01-01&to=2024-01-31')
      .set(authHeader());
    expect(res.status).toBe(200);
  });
});

// ------------------------------------------------------------------
// GET /api/bills/:id
// ------------------------------------------------------------------
describe('GET /api/bills/:id', () => {
  test('returns bill by id', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .get(`/api/bills/${BILL_ID}`)
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(BILL_ID);
  });

  test('returns 404 when bill not found', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get(`/api/bills/${BILL_ID}`)
      .set(authHeader());
    expect(res.status).toBe(404);
  });
});

// ------------------------------------------------------------------
// POST /api/bills
// ------------------------------------------------------------------
describe('POST /api/bills', () => {
  test('returns 400 when items array is missing', async () => {
    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ payment_mode: 'cash' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/items/);
  });

  test('returns 400 when items array is empty', async () => {
    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ items: [], payment_mode: 'cash' });
    expect(res.status).toBe(400);
  });

  test('returns 400 when payment_mode is missing', async () => {
    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }] });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/payment_mode/);
  });

  test('returns 400 for invalid payment_mode', async () => {
    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], payment_mode: 'bitcoin' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/payment_mode/);
  });

  test('returns 400 for invalid client_bill_id', async () => {
    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], payment_mode: 'cash', client_bill_id: 'not-a-uuid' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/client_bill_id/);
  });

  test('creates bill and returns 201', async () => {
    // Build a per-call query mock for the transaction.
    // The route makes these calls in order inside the transaction:
    //   1. SELECT inventory_enabled FROM businesses
    //   2. SELECT items WHERE id IN (...)
    //   3. SELECT COUNT(*) AS cnt FROM bills  (generateBillNumber)
    //   4. INSERT INTO bills OUTPUT INSERTED.id
    //   5. INSERT INTO bill_items  (one per item)
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });

    mockTransaction.request.mockImplementation(() => ({
      inputs: {},
      input: jest.fn().mockReturnThis(),
      query: txQueryMock,
    }));

    // pool.request() calls (outside transaction):
    //   1. idempotency check — no duplicate found
    //   2. fetchBill: SELECT FROM bills
    //   3. fetchBill: SELECT FROM bill_items
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 2 }],
        payment_mode: 'cash',
      });
    expect(res.status).toBe(201);
  });

  test('returns 200 for duplicate client_bill_id (idempotent)', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        payment_mode: 'cash',
        client_bill_id: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
      });
    expect(res.status).toBe(200);
  });
});

// ------------------------------------------------------------------
// PUT /api/bills/:id/finalize
// ------------------------------------------------------------------
describe('PUT /api/bills/:id/finalize', () => {
  test('finalizes a draft bill', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID, table_id: null, bill_number: 'INV-0001' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader());
    expect(res.status).toBe(200);
  });

  test('returns 404 when draft bill not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader());
    expect(res.status).toBe(404);
  });
});

// ------------------------------------------------------------------
// DELETE /api/bills/:id (void)
// ------------------------------------------------------------------
describe('DELETE /api/bills/:id', () => {
  test('returns 403 for non-owner', async () => {
    const res = await request(app)
      .delete(`/api/bills/${BILL_ID}`)
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('returns 404 when bill not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .delete(`/api/bills/${BILL_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(404);
  });

  test('returns 409 when bill already voided', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ ...sampleBill, status: 'voided', inventory_enabled: false }],
      rowsAffected: [1],
    });
    const res = await request(app)
      .delete(`/api/bills/${BILL_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(409);
  });

  test('voids a finalized bill', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ ...sampleBill, status: 'finalized', inventory_enabled: false }],
      rowsAffected: [1],
    });
    mockTransaction.request.mockImplementation(() => ({
      ...mockRequest,
      input: jest.fn().mockReturnThis(),
      query: jest.fn()
        .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] }),
    }));
    const res = await request(app)
      .delete(`/api/bills/${BILL_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });
});

// ------------------------------------------------------------------
// POST /api/bills/send-whatsapp
// ------------------------------------------------------------------
describe('POST /api/bills/send-whatsapp', () => {
  test('returns 400 when bill_id is missing', async () => {
    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({});
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/bill_id/);
  });

  test('returns 404 when bill not found', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({ bill_id: BILL_ID });
    expect(res.status).toBe(404);
  });

  test('returns 400 when bill has no customer phone', async () => {
    mockRequest.recordset = [{ receipt_token: 'tok', customer_phone: null, bill_number: 'INV-0001', shop_name: 'Shop' }];
    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({ bill_id: BILL_ID });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/phone/);
  });

  test('returns 400 for invalid phone number', async () => {
    mockRequest.recordset = [{ receipt_token: 'tok', customer_phone: 'bad', bill_number: 'INV-0001', shop_name: 'Shop' }];
    normalisePhone.mockReturnValue(null);
    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({ bill_id: BILL_ID });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/phone/);
  });

  test('sends WhatsApp and returns success', async () => {
    mockRequest.recordset = [{
      receipt_token: 'tok123',
      customer_phone: '9876543210',
      bill_number: 'INV-0001',
      shop_name: 'My Shop',
    }];
    normalisePhone.mockReturnValue('919876543210');
    sendBillLink.mockResolvedValue({ sent: true, campaignId: 'camp-1' });

    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({ bill_id: BILL_ID });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.campaign_id).toBe('camp-1');
  });

  test('returns skipped when WhatsApp is disabled', async () => {
    mockRequest.recordset = [{
      receipt_token: 'tok123',
      customer_phone: '9876543210',
      bill_number: 'INV-0001',
      shop_name: 'My Shop',
    }];
    normalisePhone.mockReturnValue('919876543210');
    sendBillLink.mockResolvedValue({ skipped: true });

    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({ bill_id: BILL_ID });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(false);
    expect(res.body.skipped).toBe(true);
  });
});

// ------------------------------------------------------------------
// PUT /api/bills/:id/add-items
// ------------------------------------------------------------------
describe('PUT /api/bills/:id/add-items', () => {
  test('returns 400 when items array missing', async () => {
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/add-items`)
      .set(authHeader())
      .send({});
    expect(res.status).toBe(400);
  });

  test('returns 400 when items array empty', async () => {
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/add-items`)
      .set(authHeader())
      .send({ items: [] });
    expect(res.status).toBe(400);
  });
});

// ------------------------------------------------------------------
// PUT /api/bills/:id/update-items
// ------------------------------------------------------------------
describe('PUT /api/bills/:id/update-items', () => {
  test('returns 400 when items array missing', async () => {
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/update-items`)
      .set(authHeader())
      .send({});
    expect(res.status).toBe(400);
  });
});
