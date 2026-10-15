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

// Customers table sync is fire-and-forget after commit; left real, its query
// would race this file's queued DB mocks. Covered in customers.test.js.
jest.mock('../../src/customers', () => ({
  ...jest.requireActual('../../src/customers'),
  upsertCustomer: jest.fn(() => Promise.resolve()),
  syncCustomers: jest.fn(() => Promise.resolve()),
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
describe('GET /api/bills/charges/suggestions', () => {
  test('aggregates past charge names, most used first (descriptions only)', async () => {
    // Newest first, as the query orders them. "Delivery" appears twice (in two
    // spellings) → uses 2, latest spelling from the newest bill. Amounts are
    // never returned. A row with corrupt JSON is skipped rather than failing.
    mockRequest.recordset = [
      { additional_charges: JSON.stringify([{ name: 'Delivery', amount: 40 }]), created_at: '2026-08-03T00:00:00.000Z' },
      { additional_charges: JSON.stringify([{ name: 'delivery', amount: 30 }, { name: 'Packaging', amount: 10 }]), created_at: '2026-08-02T00:00:00.000Z' },
      { additional_charges: '{not json', created_at: '2026-08-01T00:00:00.000Z' },
    ];

    const res = await request(app)
      .get('/api/bills/charges/suggestions')
      .set(authHeader());

    expect(res.status).toBe(200);
    expect(res.body).toEqual([
      { name: 'Delivery', uses: 2, last_used_at: '2026-08-03T00:00:00.000Z' },
      { name: 'Packaging', uses: 1, last_used_at: '2026-08-02T00:00:00.000Z' },
    ]);
  });

  test('returns an empty list when no bill has carried a charge', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/bills/charges/suggestions')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });
});

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

  // Order-card price edit + item discount: an owner/cashier's override is
  // stored as the DISCOUNTED net rate (so reports follow it) with the ₹ off kept
  // in discount_amount; a waiter's override is ignored.
  test.each([
    // role,    unit_price, discount, line_total
    ['owner',   18, 8, 36],   // (2 × 22 − 8) / 2
    ['cashier', 18, 8, 36],
    ['server',  50, 0, 100],  // catalog price, override ignored
  ])('item override as %s', async (role, unit, disc, lineTotal) => {
    const inputs = {};
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });
    mockTransaction.request.mockImplementation(() => {
      const r = { input: jest.fn((k, _t, v) => { inputs[k] = v; return r; }), query: txQueryMock };
      return r;
    });
    // Every pool query (fetchBill and friends) just returns a fresh bill row.
    mockRequest.query.mockImplementation(() =>
      Promise.resolve({ recordset: [{ ...sampleBill }], rowsAffected: [1] }));

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader({ role }))
      .send({
        items: [{ item_id: ITEM_ID, quantity: 2, price_override: 22, discount_amount: 8 }],
        payment_mode: 'cash',
        status: 'draft',
      });
    expect(res.status).toBe(201);
    expect(inputs.unit_price0).toBeCloseTo(unit, 4);
    expect(inputs.discount_amount0).toBe(disc);
    expect(inputs.line_total0).toBe(lineTotal);
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

    // The bill_items INSERT carries the HSN snapshot. bill_items is now one
    // multi-row INSERT, so its per-line inputs are suffixed by row index
    // (hsn_code0, hsn_code1, ...) rather than a bare name per request.
    const lineInsert = capturedInputs.find((i) => 'hsn_code0' in i);
    expect(lineInsert).toBeDefined();
    expect(lineInsert.hsn_code0).toBe('9963');
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
    const lineInsert = capturedInputs.find((i) => 'hsn_code0' in i);
    expect(lineInsert.tax_rate0).toBeNull();
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

  test('adds additional charges to the total without taxing or discounting them', async () => {
    // Same 5% item, GST on, discount 20: net 100, discounted net 80, tax 4.
    // Charges Delivery 30 + Packaging 10 = 40 ride on top, untaxed and not
    // reduced by the discount: total = 100 + 4 + 40 = 144, payable = 124.
    const taxedItem = { ...sampleItem, tax_rate: 5, hsn_code: '9963' };
    const capturedInputs = [];
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false, gst_enabled: true }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [taxedItem], rowsAffected: [1] })
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
        additional_charges: [
          { name: '  Delivery ', amount: 30 },
          { name: 'Packaging', amount: '10' },
        ],
      });
    expect(res.status).toBe(201);

    const billInsert = capturedInputs.find((i) => 'subtotal' in i);
    expect(billInsert.subtotal).toBe(100);
    expect(billInsert.discount_amount).toBe(20);
    expect(billInsert.tax_amount).toBe(4);        // charges never enter the tax base
    expect(billInsert.charges_amount).toBe(40);
    expect(billInsert.total).toBe(144);           // 100 + 4 + 40
    // Stored detail is normalised: names trimmed, amounts numeric.
    expect(JSON.parse(billInsert.additional_charges)).toEqual([
      { name: 'Delivery', amount: 30 },
      { name: 'Packaging', amount: 10 },
    ]);
  });

  test('rejects malformed additional charges', async () => {
    const base = { items: [{ item_id: ITEM_ID, quantity: 1 }], payment_mode: 'cash' };
    const bad = [
      'delivery',                                  // not an array
      [{ name: '', amount: 10 }],                  // no name
      [{ name: 'Delivery', amount: 0 }],           // non-positive amount
      [{ name: 'Delivery', amount: 'ten' }],       // non-numeric amount
    ];
    for (const additional_charges of bad) {
      const res = await request(app)
        .post('/api/bills')
        .set(authHeader())
        .send({ ...base, additional_charges });
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/additional[ _]charge/i);
    }
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

  test('records the caller as the biller (finalized_by_user_id)', async () => {
    // The waiter who held the order is the creator; whoever settles it is
    // "Billed by" on the receipt and in History.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID, table_id: null, bill_number: 'INV-0001' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader());
    expect(mockRequest.inputs.finalized_by_user_id).toBe(USER_ID);
  });

  test('returns 404 when draft bill not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader());
    expect(res.status).toBe(404);
  });

  // A held bill stores the mode it was PARKED with. Reopening it and settling
  // by a different tender has to overwrite that, or history, reports and the
  // credit ledger all keep reporting the original one.
  test('settling a held bill records the mode it was actually paid with', async () => {
    mockRequest.query
      .mockResolvedValueOnce({
        recordset: [{ id: BILL_ID, table_id: null, bill_number: 'INV-0001',
                      payment_mode: 'upi' }],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader())
      .send({ payment_mode: 'upi' });

    expect(res.status).toBe(200);
    expect(mockRequest.inputs.payment_mode).toBe('upi');
  });

  test('omitting the mode keeps whatever the draft already had', async () => {
    mockRequest.query
      .mockResolvedValueOnce({
        recordset: [{ id: BILL_ID, table_id: null, bill_number: 'INV-0001' }],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader());

    expect(res.status).toBe(200);
    // null → the SQL falls back to the stored mode via COALESCE.
    expect(mockRequest.inputs.payment_mode).toBeNull();
  });

  // A settled table order frees the table straight away — there is no
  // "billed, awaiting mark-paid" step any more.
  test('finalizing a table order sets the table straight to empty', async () => {
    mockRequest.query
      .mockResolvedValueOnce({
        recordset: [{ id: BILL_ID, table_id: 'ffffffff-ffff-ffff-ffff-ffffffffffff', bill_number: 'INV-0001' }],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader());

    expect(res.status).toBe(200);
    const tableSql = mockRequest.query.mock.calls[1][0];
    expect(tableSql).toMatch(/UPDATE tables SET status = 'empty'/);
  });

  test('rejects a payment mode that is not a real tender', async () => {
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader())
      .send({ payment_mode: 'bitcoin' });
    expect(res.status).toBe(400);
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
    mockRequest.recordset = [{ receipt_token: 'tok', status: 'finalized', customer_phone: null, bill_number: 'INV-0001', shop_name: 'Shop' }];
    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({ bill_id: BILL_ID });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/phone/);
  });

  test('returns 400 for invalid phone number', async () => {
    mockRequest.recordset = [{ receipt_token: 'tok', status: 'finalized', customer_phone: 'bad', bill_number: 'INV-0001', shop_name: 'Shop' }];
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
      status: 'finalized',
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
      status: 'finalized',
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

  test('refuses a draft bill', async () => {
    mockRequest.recordset = [{ receipt_token: 'tok', status: 'draft', customer_phone: '9876543210', bill_number: 'D-1', shop_name: 'Shop' }];
    const res = await request(app)
      .post('/api/bills/send-whatsapp')
      .set(authHeader())
      .send({ bill_id: BILL_ID });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/settled/);
    expect(sendBillLink).not.toHaveBeenCalled();
  });
});

describe('POST /api/bills/:id/whatsapp', () => {
  test('refuses a draft bill and does not save a typed phone', async () => {
    mockRequest.recordset = [{ receipt_token: 'tok', status: 'draft', customer_phone: null, bill_number: 'D-1', shop_name: 'Shop', whatsapp_mode: 'deeplink' }];
    const res = await request(app)
      .post(`/api/bills/${BILL_ID}/whatsapp`)
      .set(authHeader())
      .send({ phone: '9876543210' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/settled/);
    expect(mockRequest.query).toHaveBeenCalledTimes(1); // the SELECT only — no UPDATE
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

  // A draft ALREADY deducted its own items from stock when it was created. So
  // when the cashier reopens a held bill and settles it, the new quantities
  // must be checked against stock + whatever this draft is holding — never
  // against the bare current stock, which would reject edits that free stock up.
  test('editing a draft is not rejected when its own reservation covers the new qty', async () => {
    // Rice: 10 in stock, all 10 held by this draft → items.stock_quantity is 0.
    // Cashier reduces the line to 8. That must settle, not 409.
    const restored = [];
    const deducted = [];
    mockTransaction.request.mockImplementation(() => {
      const inputs = {};
      return {
        inputs,
        input: jest.fn(function (name, _type, value) {
          inputs[name] = value;
          return this;
        }),
        query: jest.fn((sqlText) => {
          if (/FROM bills b/.test(sqlText)) {
            return Promise.resolve({
              recordset: [{ id: BILL_ID, status: 'draft', inventory_enabled: true,
                round_off_enabled: false, gst_enabled: false }],
              rowsAffected: [1],
            });
          }
          if (/FROM items\b/.test(sqlText)) {
            return Promise.resolve({
              recordset: [{ ...sampleItem, stock_quantity: 0 }],
              rowsAffected: [1],
            });
          }
          if (/FROM bill_items/.test(sqlText)) {
            return Promise.resolve({
              recordset: [{ item_id: ITEM_ID, variant_id: null, item_name: 'Rice',
                quantity: 10, unit_price: 50, kitchen_status: 'pending', kitchen_done_at: null }],
              rowsAffected: [1],
            });
          }
          if (/stock_quantity \+ @qty/.test(sqlText)) {
            restored.push(inputs.qty);
            return Promise.resolve({ recordset: [], rowsAffected: [1] });
          }
          if (/stock_quantity - @qty/.test(sqlText)) {
            deducted.push(inputs.qty);
            return Promise.resolve({ recordset: [], rowsAffected: [1] });
          }
          return Promise.resolve({ recordset: [], rowsAffected: [1] });
        }),
      };
    });
    // fetchBill after commit: the bill row, then its items.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/update-items`)
      .set(authHeader())
      .send({ items: [{ item_id: ITEM_ID, quantity: 8 }] });

    expect(res.status).toBe(200);
    // The draft's 10 go back, the edited 8 come out — net stock 2, not a 409.
    expect(restored).toEqual([10]);
    expect(deducted).toEqual([8]);
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

// ------------------------------------------------------------------
// Bill date = finalized_at (the sale), not created_at (the order)
// ------------------------------------------------------------------
describe('bill finalized date', () => {
  // POST one cash bill; returns the inputs bound to the bills INSERT.
  async function postBill(extra) {
    const captured = [];
    const txQueryMock = jest.fn()
      .mockResolvedValueOnce({ recordset: [{ inventory_enabled: false }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });
    mockTransaction.request.mockImplementation(() => {
      const inputs = {};
      captured.push(inputs);
      return {
        inputs,
        input: jest.fn(function (name, _type, value) { inputs[name] = value; return this; }),
        query: txQueryMock,
      };
    });
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], payment_mode: 'cash', ...extra });
    expect(res.status).toBe(201);
    const insertSql = txQueryMock.mock.calls.map((c) => c[0]).find((q) => /INSERT INTO bills/.test(q));
    return { inputs: captured.find((i) => 'subtotal' in i), insertSql };
  }

  test('an offline bill keeps the time it was sold, not the sync time', async () => {
    const soldAt = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString();
    const { inputs, insertSql } = await postBill({ finalized_at: soldAt });
    expect(inputs.sale_time.toISOString()).toBe(soldAt);
    expect(insertSql).toMatch(/created_at, finalized_at/);
  });

  test('an implausible client time falls back to server time instead of rejecting', async () => {
    const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    expect((await postBill({ finalized_at: tomorrow })).inputs.sale_time).toBeNull();
    expect((await postBill({ finalized_at: 'yesterday' })).inputs.sale_time).toBeNull();
  });

  test('a draft gets no finalize time until it is settled', async () => {
    const { inputs, insertSql } = await postBill({ status: 'draft', finalized_at: new Date().toISOString() });
    expect(inputs.sale_time).toBeNull();
    expect(insertSql).toMatch(/CASE WHEN @status = 'finalized'/);
  });

  test('finalizing a held bill stamps finalized_at', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID, table_id: null, bill_number: 'INV-0001' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/finalized_at = SYSUTCDATETIME\(\)/);
  });

  test('history filters and sorts by the finalize date, falling back to the order date', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/bills?from=2026-10-12&to=2026-10-12')
      .set(authHeader());
    expect(res.status).toBe(200);
    const sqlText = mockRequest.query.mock.calls[0][0];
    expect(sqlText).toMatch(/COALESCE\(b\.finalized_at, b\.created_at\) >= @from_dt/);
    expect(sqlText).toMatch(/ORDER BY COALESCE\(b\.finalized_at, b\.created_at\) DESC/);
  });
});

// ------------------------------------------------------------------
// Order-card price edit + line discount (applyLineOverrides)
// ------------------------------------------------------------------
describe('order-card line overrides', () => {
  const ITEM2_ID = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  const dal = { ...sampleItem, id: ITEM2_ID, name: 'Dal', price: 30 };

  // Routes every transaction query by its SQL so one mock serves POST,
  // add-items and update-items. lines() = inputs bound to the bill_items
  // INSERT, bill() = inputs bound to the bills INSERT.
  function routeTx({ biz = {}, items = [sampleItem], oldLines = [] } = {}) {
    const calls = [];
    const flags = { inventory_enabled: false, round_off_enabled: false, gst_enabled: false, ...biz };
    mockTransaction.request.mockImplementation(() => {
      const inputs = {};
      const r = {
        inputs,
        input: jest.fn((k, _t, v) => { inputs[k] = v; return r; }),
        query: jest.fn((sqlText) => {
          calls.push({ sqlText, inputs });
          const ok = (rs = []) => Promise.resolve({ recordset: rs, rowsAffected: [rs.length || 1] });
          if (/COUNT\(\*\) AS cnt/.test(sqlText)) return ok([{ cnt: 0 }]);
          if (/INSERT INTO bills/.test(sqlText)) return ok([{ id: BILL_ID }]);
          if (/FROM bills b/.test(sqlText)) return ok([{ id: BILL_ID, status: 'draft', ...flags }]);
          if (/FROM businesses/.test(sqlText)) return ok([flags]);
          if (/^\s*SELECT[\s\S]*FROM items\b/.test(sqlText)) return ok(items);
          if (/^\s*SELECT[\s\S]*FROM bill_items/.test(sqlText)) return ok(oldLines);
          return ok();
        }),
      };
      return r;
    });
    // fetchBill and friends after commit.
    mockRequest.query.mockImplementation(() =>
      Promise.resolve({ recordset: [{ ...sampleBill }], rowsAffected: [1] }));
    const of = (re) => calls.filter((c) => re.test(c.sqlText)).map((c) => c.inputs);
    return {
      lines: () => of(/INSERT INTO bill_items/).pop(),
      bill: () => of(/INSERT INTO bills/).pop(),
      sql: (re) => calls.map((c) => c.sqlText).find((s) => re.test(s)),
    };
  }

  const post = (role, line, extra = {}) => request(app)
    .post('/api/bills')
    .set(authHeader({ role }))
    .send({ items: [{ item_id: ITEM_ID, quantity: 2, ...line }], payment_mode: 'cash', ...extra });

  describe('POST /api/bills', () => {
    test('discount alone (no price edit) comes off the catalog net', async () => {
      const tx = routeTx();
      const res = await post('owner', { discount_amount: 10 });
      expect(res.status).toBe(201);
      expect(tx.lines()).toMatchObject({ unit_price0: 45, discount_amount0: 10, line_total0: 90 });
    });

    test('price edit alone stores the new net rate with no discount', async () => {
      const tx = routeTx();
      await post('cashier', { price_override: 60 });
      expect(tx.lines()).toMatchObject({ unit_price0: 60, discount_amount0: 0, line_total0: 120 });
    });

    test('a discount bigger than the line is clamped to the line (never negative)', async () => {
      const tx = routeTx();
      await post('owner', { discount_amount: 500 });
      expect(tx.lines()).toMatchObject({ unit_price0: 0, discount_amount0: 100, line_total0: 0 });
      expect(tx.bill().subtotal).toBe(0);
    });

    test('a ₹0 price edit is a free line, not "no override"', async () => {
      const tx = routeTx();
      await post('owner', { price_override: 0 });
      expect(tx.lines()).toMatchObject({ unit_price0: 0, line_total0: 0 });
    });

    test.each([
      ['negative price', { price_override: -5 }],
      ['text price', { price_override: 'abc' }],
      ['negative discount', { discount_amount: -3 }],
      ['text discount', { discount_amount: 'ten' }],
      ['null fields', { price_override: null, discount_amount: null }],
    ])('ignores a %s and bills at catalog', async (_name, line) => {
      const tx = routeTx();
      const res = await post('owner', line);
      expect(res.status).toBe(201);
      expect(tx.lines()).toMatchObject({ unit_price0: 50, discount_amount0: 0, line_total0: 100 });
    });

    test('discount is rounded to paise', async () => {
      const tx = routeTx();
      await post('owner', { discount_amount: 3.336 });
      expect(tx.lines().discount_amount0).toBe(3.34);
    });

    test('GST is charged on the discounted net', async () => {
      const tx = routeTx({ biz: { gst_enabled: true }, items: [{ ...sampleItem, tax_rate: 10 }] });
      await post('owner', { price_override: 22, discount_amount: 8 });
      // net 2 × 22 − 8 = 36; tax 10% of 36 = 3.6
      expect(tx.lines().unit_price0).toBeCloseTo(18, 4);
      expect(tx.lines().line_total0).toBe(39.6);
      expect(tx.bill()).toMatchObject({ subtotal: 36, tax_amount: 3.6 });
    });

    test('kitchen role cannot reprice either', async () => {
      const tx = routeTx();
      await post('kitchen', { price_override: 1, discount_amount: 20 });
      expect(tx.lines()).toMatchObject({ unit_price0: 50, discount_amount0: 0 });
    });

    test('a bill settled in one step records its creator as the biller', async () => {
      const tx = routeTx();
      await post('cashier', {});
      const insertSql = tx.sql(/INSERT INTO bills/);
      expect(insertSql).toMatch(/finalized_at, finalized_by_user_id\)/);
      expect(insertSql).toMatch(/CASE WHEN @status = 'finalized' THEN @created_by_user_id END/);
    });
  });

  describe('PUT /api/bills/:id/add-items', () => {
    const add = (role, line) => request(app)
      .put(`/api/bills/${BILL_ID}/add-items`)
      .set(authHeader({ role }))
      .send({ items: [{ item_id: ITEM_ID, quantity: 2, ...line }] });

    test.each([
      // role,    unit, disc, total
      ['owner',   18,   8,    36],
      ['cashier', 18,   8,    36],
      ['server',  50,   0,    100],
    ])('override as %s', async (role, unit, disc, total) => {
      const tx = routeTx();
      const res = await add(role, { price_override: 22, discount_amount: 8 });
      expect(res.status).toBe(200);
      expect(tx.lines().unit_price0).toBeCloseTo(unit, 4);
      expect(tx.lines()).toMatchObject({ discount_amount0: disc, line_total0: total });
      expect(tx.sql(/INSERT INTO bill_items/)).toMatch(/line_total, discount_amount\)/);
    });
  });

  describe('PUT /api/bills/:id/update-items', () => {
    // The draft as the cashier left it: 2 × Rice repriced to 22 less ₹8,
    // stored as 18/unit + discount 8.
    const priced = [{ item_id: ITEM_ID, variant_id: null, item_name: 'Rice', quantity: 2,
      unit_price: 18, discount_amount: 8, kitchen_status: 'pending', kitchen_done_at: null }];
    const update = (role, lines) => request(app)
      .put(`/api/bills/${BILL_ID}/update-items`)
      .set(authHeader({ role }))
      .send({ items: lines });

    test("a waiter changing qty keeps the cashier's price and ₹ discount", async () => {
      const tx = routeTx({ oldLines: priced });
      const res = await update('server', [{ item_id: ITEM_ID, quantity: 3 }]);
      expect(res.status).toBe(200);
      // 3 × 22 − 8 = 58
      expect(tx.lines().unit_price0).toBeCloseTo(58 / 3, 4);
      expect(tx.lines()).toMatchObject({ discount_amount0: 8, line_total0: 58 });
    });

    test("a waiter cannot replace the cashier's values with their own", async () => {
      const tx = routeTx({ oldLines: priced });
      await update('server', [{ item_id: ITEM_ID, quantity: 2, price_override: 1, discount_amount: 0 }]);
      expect(tx.lines()).toMatchObject({ unit_price0: 18, discount_amount0: 8, line_total0: 36 });
    });

    test('a waiter adding a different dish gets catalog price for it', async () => {
      const tx = routeTx({ oldLines: priced, items: [sampleItem, dal] });
      await update('server', [
        { item_id: ITEM_ID, quantity: 2 },
        { item_id: ITEM2_ID, quantity: 1 },
      ]);
      expect(tx.lines()).toMatchObject({
        unit_price0: 18, discount_amount0: 8,
        unit_price1: 30, discount_amount1: 0, line_total1: 30,
      });
    });

    test('a waiter on a never-repriced draft stays at catalog', async () => {
      const tx = routeTx({ oldLines: [{ ...priced[0], unit_price: 50, discount_amount: 0 }] });
      await update('server', [{ item_id: ITEM_ID, quantity: 4 }]);
      expect(tx.lines()).toMatchObject({ unit_price0: 50, discount_amount0: 0, line_total0: 200 });
    });

    test('a cashier can change the override', async () => {
      const tx = routeTx({ oldLines: priced });
      await update('cashier', [{ item_id: ITEM_ID, quantity: 2, price_override: 40, discount_amount: 10 }]);
      expect(tx.lines()).toMatchObject({ unit_price0: 35, discount_amount0: 10, line_total0: 70 });
    });

    test('a cashier sending no override clears it back to catalog', async () => {
      const tx = routeTx({ oldLines: priced });
      await update('owner', [{ item_id: ITEM_ID, quantity: 2 }]);
      expect(tx.lines()).toMatchObject({ unit_price0: 50, discount_amount0: 0, line_total0: 100 });
    });

    test('old lines are read with discount_amount so it can carry over', async () => {
      const tx = routeTx({ oldLines: priced });
      await update('server', [{ item_id: ITEM_ID, quantity: 2 }]);
      expect(tx.sql(/^\s*SELECT[\s\S]*FROM bill_items/)).toMatch(/discount_amount/);
    });
  });
});

// ------------------------------------------------------------------
// "Billed by": finalized_by_user_id, read back as billed_by
// ------------------------------------------------------------------
describe('"Billed by"', () => {
  test('GET /api/bills names the settler, else the creator', async () => {
    mockRequest.recordset = [];
    await request(app).get('/api/bills').set(authHeader());
    const sqlText = mockRequest.query.mock.calls[0][0];
    expect(sqlText).toMatch(/COALESCE\(fu\.name, cu\.name\) AS billed_by/);
    expect(sqlText).toMatch(/LEFT JOIN users fu ON fu\.id = b\.finalized_by_user_id/);
    expect(sqlText).toMatch(/LEFT JOIN users cu ON cu\.id = b\.created_by_user_id/);
  });

  test('GET /api/bills/:id returns billed_by and each line discount_amount', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...sampleBill, billed_by: 'Ramesh Patil' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ item_name: 'Rice', quantity: 2, unit_price: 45, line_total: 90, discount_amount: 10 }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [0] });
    const res = await request(app).get(`/api/bills/${BILL_ID}`).set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body.billed_by).toBe('Ramesh Patil');
    expect(res.body.items[0].discount_amount).toBe(10);
    expect(mockRequest.query.mock.calls[1][0]).toMatch(/discount_amount/);
  });

  test("a cashier settling a waiter's draft is recorded as the biller", async () => {
    const CASHIER_ID = '99999999-9999-9999-9999-999999999999';
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: BILL_ID, table_id: null, bill_number: 'INV-0001' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader({ role: 'cashier', user_id: CASHIER_ID }));
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.finalized_by_user_id).toBe(CASHIER_ID);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/finalized_by_user_id = @finalized_by_user_id/);
  });

  test('a waiter cannot settle, so never becomes the biller', async () => {
    const res = await request(app)
      .put(`/api/bills/${BILL_ID}/finalize`)
      .set(authHeader({ role: 'server' }));
    expect(res.status).toBe(403);
    expect(mockRequest.inputs.finalized_by_user_id).toBeUndefined();
  });
});
