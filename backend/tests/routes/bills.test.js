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
    //   3. SELECT item_variants  (findMissingVariantError — none, so no error)
    //   4. SELECT item_recipes JOIN raw_materials  (loadRecipeMap — empty here)
    //   5. SELECT COUNT(*) AS cnt FROM bills  (generateBillNumber)
    //   6. INSERT INTO bills OUTPUT INSERTED.id
    //   7. INSERT INTO bill_items  (one per item)
    // (loadVariantMap is skipped — no variant_id on the line item.)
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
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

  test('rejects a variant item billed without a size', async () => {
    // Regression: Chicken 65 has sizes (half 180 / Full 280) but a base price of
    // 230. Scanning its ITEM-level barcode used to add it with no variant_id,
    // billing the 230 placeholder — a price that isn't on the menu. The server
    // must reject the line whatever the client does.
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      // findMissingVariantError — this item HAS active sizes, so the line is bad.
      .mockResolvedValueOnce({ recordset: [{ name: 'Chicken 65' }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });

    mockTransaction.request.mockImplementation(() => ({
      inputs: {},
      input: jest.fn().mockReturnThis(),
      query: txQueryMock,
    }));
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        payment_mode: 'cash',
      });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Select a size for: Chicken 65/);
    expect(mockTransaction.rollback).toHaveBeenCalled();
  });

  test('snapshots hsn_code onto bill_items without changing totals', async () => {
    // A taxed item (5%) that carries an HSN code.
    const taxedItem = { ...sampleItem, tax_rate: 5, hsn_code: '9963' };

    // Capture every .input() binding across all transaction requests so we can
    // assert the bill_items INSERT received hsn_code, and totals are unchanged.
    const capturedInputs = [];
    const txQueryMock = jest.fn()
      // GST enabled so the taxed item's 5% is applied (tax is ignored when off).
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false, gst_enabled: true }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [taxedItem], rowsAffected: [1] })
      // findMissingVariantError — no variant rows, so the line is allowed.
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });

    mockTransaction.request.mockImplementation(() => {
      const inputs = {};
      capturedInputs.push(inputs);
      return {
        inputs,
        input: jest.fn(function (name, _type, value) { inputs[name] = value; return this; }),
        query: txQueryMock,
      };
    });

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

    // The bill INSERT binds subtotal/tax computed exactly as before:
    // 2 × 50 = 100 taxable, 5% tax = 5, total = 105.
    const billInsert = capturedInputs.find((i) => 'subtotal' in i);
    expect(billInsert.subtotal).toBe(100);
    expect(billInsert.tax_amount).toBe(5);
    expect(billInsert.total).toBe(105);

    // The bill_items INSERT carries the HSN snapshot.
    const lineInsert = capturedInputs.find((i) => 'hsn_code' in i);
    expect(lineInsert).toBeDefined();
    expect(lineInsert.hsn_code).toBe('9963');
  });

  test('ignores tax entirely when GST is disabled for the business', async () => {
    // Same 5% item, but the business has gst_enabled = false → tax must be 0.
    const taxedItem = { ...sampleItem, tax_rate: 5, hsn_code: '9963' };
    const capturedInputs = [];
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false, gst_enabled: false }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [taxedItem], rowsAffected: [1] })
      // findMissingVariantError — no variant rows, so the line is allowed.
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });

    mockTransaction.request.mockImplementation(() => {
      const inputs = {};
      capturedInputs.push(inputs);
      return {
        inputs,
        input: jest.fn(function (name, _type, value) { inputs[name] = value; return this; }),
        query: txQueryMock,
      };
    });
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ items: [{ item_id: ITEM_ID, quantity: 2 }], payment_mode: 'cash' });
    expect(res.status).toBe(201);

    // 2 × 50 = 100 taxable, but GST off → tax 0, total = subtotal.
    const billInsert = capturedInputs.find((i) => 'subtotal' in i);
    expect(billInsert.subtotal).toBe(100);
    expect(billInsert.tax_amount).toBe(0);
    expect(billInsert.total).toBe(100);
    // The stored line's tax_rate is nulled out too (tax ignored entirely).
    const lineInsert = capturedInputs.find((i) => 'hsn_code' in i);
    expect(lineInsert.tax_rate).toBeNull();
  });

  test('applies discount to the net subtotal, then charges tax on the discounted net', async () => {
    // 5% item, GST on. 2 × 50 = 100 net, discount 20 → discounted net 80,
    // tax = 5 × 80/100 = 4. total = subtotal + discounted tax = 104 (discount is
    // stored separately, NOT subtracted from total). Payable = total − discount
    // = 104 − 20 = 84 = discounted net (80) + tax (4).
    const taxedItem = { ...sampleItem, tax_rate: 5, hsn_code: '9963' };
    const capturedInputs = [];
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false, gst_enabled: true }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [taxedItem], rowsAffected: [1] })
      // findMissingVariantError — no variant rows, so the line is allowed.
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });

    mockTransaction.request.mockImplementation(() => {
      const inputs = {};
      capturedInputs.push(inputs);
      return {
        inputs,
        input: jest.fn(function (name, _type, value) { inputs[name] = value; return this; }),
        query: txQueryMock,
      };
    });
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
        discount_amount: 20,
      });
    expect(res.status).toBe(201);

    const billInsert = capturedInputs.find((i) => 'subtotal' in i);
    expect(billInsert.subtotal).toBe(100);
    expect(billInsert.discount_amount).toBe(20);
    expect(billInsert.tax_amount).toBe(4);   // 5 × 80/100
    expect(billInsert.total).toBe(104);      // subtotal 100 + discounted tax 4
    // Payable is total − discount = 84 (discounted net 80 + tax 4).
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
  test('returns 403 for a role that is neither cashier nor owner', async () => {
    const res = await request(app)
      .delete(`/api/bills/${BILL_ID}`)
      .set(authHeader({ role: 'kitchen' }));
    expect(res.status).toBe(403);
  });

  test('returns 404 when bill not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .delete(`/api/bills/${BILL_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(404);
  });

  test('allows a cashier to void/release a table', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ ...sampleBill, status: 'draft', inventory_enabled: false }],
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
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
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

// ------------------------------------------------------------------
// Recipe deduction — per-size raw-material consumption
//
// An item WITHOUT sizes keeps its recipe on the item (variant_id NULL); an item
// WITH sizes carries one per size. A sized line never falls back to the
// item-level rows, so a half plate cannot consume a full plate's ingredients.
// ------------------------------------------------------------------
describe('POST /api/bills — recipe deduction', () => {
  const VARIANT_ID = '11111111-1111-1111-1111-111111111111';
  const RM_ID = '22222222-2222-2222-2222-222222222222';

  /// Wires the transaction so loadRecipeMap returns [recipeRows], and records
  /// every raw_materials UPDATE so a test can assert the deducted amount.
  function billWithRecipe(recipeRows, { variantRows = [] } = {}) {
    const deductions = [];
    let call = 0;
    mockTransaction.request.mockImplementation(() => {
      const inputs = {};
      return {
        inputs,
        input: jest.fn(function (name, _type, value) {
          inputs[name] = value;
          return this;
        }),
        query: jest.fn((sqlText) => {
          call++;
          if (/UPDATE raw_materials/.test(sqlText)) {
            deductions.push({ id: inputs.id, qty: inputs.qty });
            return Promise.resolve({ recordset: [], rowsAffected: [1] });
          }
          if (/FROM item_recipes/.test(sqlText)) {
            return Promise.resolve({ recordset: recipeRows, rowsAffected: [recipeRows.length] });
          }
          if (/FROM item_variants/.test(sqlText)) {
            return Promise.resolve({ recordset: variantRows, rowsAffected: [variantRows.length] });
          }
          if (/FROM businesses/.test(sqlText)) {
            return Promise.resolve({
              recordset: [{ inventory_enabled: true, gst_enabled: false }],
              rowsAffected: [1],
            });
          }
          if (/FROM items/.test(sqlText)) {
            return Promise.resolve({ recordset: [sampleItem], rowsAffected: [1] });
          }
          if (/COUNT\(\*\) AS cnt/.test(sqlText)) {
            return Promise.resolve({ recordset: [{ cnt: 0 }], rowsAffected: [1] });
          }
          if (/INSERT INTO bills/.test(sqlText)) {
            return Promise.resolve({ recordset: [{ id: BILL_ID }], rowsAffected: [1] });
          }
          if (/UPDATE (items|item_variants)/.test(sqlText)) {
            return Promise.resolve({ recordset: [], rowsAffected: [1] });
          }
          return Promise.resolve({ recordset: [], rowsAffected: [1] });
        }),
      };
    });
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    return deductions;
  }

  test('an item with no sizes still deducts its item-level recipe', async () => {
    // BACK-COMPAT: this is the guarantee for dishes that already have recipes.
    const deductions = billWithRecipe([
      { item_id: ITEM_ID, variant_id: null, raw_material_id: RM_ID,
        quantity: 1.5, name: 'Rice', stock_quantity: 100, low_stock_threshold: null },
    ]);

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ items: [{ item_id: ITEM_ID, quantity: 2 }], payment_mode: 'cash' });
    expect(res.status).toBe(201);
    // 2 × 1.5 = 3
    expect(deductions).toEqual([{ id: RM_ID, qty: 3 }]);
  });

  test('a sized line uses its own size\'s recipe, not the item-level one', async () => {
    // Both rows exist for the same material. Billing 2 × the size must deduct
    // 2 × 0.5 = 1 — never the item-level 2 × 1.5, and never their sum.
    const deductions = billWithRecipe(
      [
        { item_id: ITEM_ID, variant_id: null, raw_material_id: RM_ID,
          quantity: 1.5, name: 'Rice', stock_quantity: 100, low_stock_threshold: null },
        { item_id: ITEM_ID, variant_id: VARIANT_ID, raw_material_id: RM_ID,
          quantity: 0.5, name: 'Rice', stock_quantity: 100, low_stock_threshold: null },
      ],
      { variantRows: [{ id: VARIANT_ID, item_id: ITEM_ID, label: 'Half', price: 90, stock_quantity: 50 }] },
    );

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({
        items: [{ item_id: ITEM_ID, variant_id: VARIANT_ID, quantity: 2 }],
        payment_mode: 'cash',
      });
    expect(res.status).toBe(201);
    expect(deductions).toEqual([{ id: RM_ID, qty: 1 }]);
  });

  test('a sized line with no recipe of its own deducts nothing', async () => {
    // Strict: no fallback to the item-level rows. If this ever starts falling
    // back, a half plate silently consumes a full plate's ingredients.
    const deductions = billWithRecipe(
      [
        { item_id: ITEM_ID, variant_id: null, raw_material_id: RM_ID,
          quantity: 1.5, name: 'Rice', stock_quantity: 100, low_stock_threshold: null },
      ],
      { variantRows: [{ id: VARIANT_ID, item_id: ITEM_ID, label: 'Half', price: 90, stock_quantity: 50 }] },
    );

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({
        items: [{ item_id: ITEM_ID, variant_id: VARIANT_ID, quantity: 2 }],
        payment_mode: 'cash',
      });
    expect(res.status).toBe(201);
    expect(deductions).toEqual([]);
  });
});
