const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

// Audit is fire-and-forget (`.catch` is chained on it), so it must resolve.
jest.mock('../../src/audit', () => ({
  logVendorBillCreated: jest.fn(() => Promise.resolve()),
  logVendorBillUpdated: jest.fn(() => Promise.resolve()),
  logVendorBillDeleted: jest.fn(() => Promise.resolve()),
}));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const BILL_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

/**
 * One row that satisfies every SELECT the create/delete flows make against the
 * mocked DB: business flags, target resolution, INSERT ... OUTPUT id, the
 * header re-read and the line re-read.
 */
function universalRow({ inventoryEnabled = 1, stockApplied = 1 } = {}) {
  return {
    id: BILL_ID,
    inventory_enabled: inventoryEnabled,
    gst_enabled: 0,
    gst_number: null,
    state: null,
    vendor_name: 'Acme Traders',
    vendor_gstin: null,
    vendor_state: null,
    invoice_number: 'V-001',
    invoice_date: new Date('2026-08-01T00:00:00Z'),
    subtotal: 250,
    tax_amount: 0,
    cgst_amount: 0,
    sgst_amount: 0,
    igst_amount: 0,
    cess_amount: 0,
    discount_amount: 0,
    round_off: 0,
    total: 250,
    is_interstate: 0,
    itc_eligible: 1,
    reverse_charge: 0,
    payment_mode: 'cash',
    payment_status: 'paid',
    amount_paid: 0,
    notes: null,
    stock_applied: stockApplied,
    created_at: new Date().toISOString(),
    created_by_name: 'Owner',
    // line columns
    item_id: ITEM_ID,
    variant_id: null,
    raw_material_id: null,
    item_name: 'Rice',
    quantity: 5,
    unit: 'kg',
    unit_price: 50,
    tax_rate: null,
    hsn_code: null,
    line_total: 250,
    sort_order: 0,
  };
}

/** Every query the route ran, with a snapshot of the bound inputs at that moment. */
let calls;

beforeEach(() => {
  mockRequest.query.mockReset();
  mockRequest.reset();
  calls = [];
  mockRequest.query.mockImplementation(function (sqlText) {
    calls.push({ sql: String(sqlText), inputs: { ...this.inputs } });
    return Promise.resolve({ recordset: this.recordset, rowsAffected: this.rowsAffected });
  });
});

const stockUpdates = () =>
  calls.filter((c) => /UPDATE items SET stock_quantity = stock_quantity \+ @qty/.test(c.sql));

const validBody = (lineOverrides = {}) => ({
  vendor_name: 'Acme Traders',
  invoice_number: 'V-001',
  invoice_date: '2026-08-01',
  lines: [{ item_id: ITEM_ID, name: 'Rice', quantity: 5, unit_price: 50, unit: 'kg', ...lineOverrides }],
});

describe('vendor bills — auth guard', () => {
  test('POST returns 401 without token', async () => {
    const res = await request(app).post('/api/vendor-bills').send(validBody());
    expect(res.status).toBe(401);
  });

  test('POST returns 403 for non-owner', async () => {
    const res = await request(app)
      .post('/api/vendor-bills')
      .set(authHeader({ role: 'cashier' }))
      .send(validBody());
    expect(res.status).toBe(403);
  });
});

describe('POST /api/vendor-bills — stock receipt', () => {
  test('adds the purchased quantity to the linked item when inventory is on', async () => {
    mockRequest.recordset = [universalRow()];

    const res = await request(app)
      .post('/api/vendor-bills')
      .set(authHeader())
      .send(validBody());

    expect(res.status).toBe(201);
    const updates = stockUpdates();
    expect(updates).toHaveLength(1);
    expect(updates[0].inputs.id).toBe(ITEM_ID);
    expect(updates[0].inputs.qty).toBe(5);
    // Untracked (NULL) stock must never be opted back in by a purchase.
    expect(updates[0].sql).toMatch(/stock_quantity IS NOT NULL/);
  });

  test('does not touch stock when inventory is off', async () => {
    mockRequest.recordset = [universalRow({ inventoryEnabled: 0 })];

    const res = await request(app)
      .post('/api/vendor-bills')
      .set(authHeader())
      .send(validBody());

    expect(res.status).toBe(201);
    expect(stockUpdates()).toHaveLength(0);
  });

  test('a free-text line (no target) moves no stock', async () => {
    mockRequest.recordset = [universalRow()];

    const res = await request(app)
      .post('/api/vendor-bills')
      .set(authHeader())
      .send(validBody({ item_id: undefined, name: 'Freight' }));

    expect(res.status).toBe(201);
    expect(stockUpdates()).toHaveLength(0);
  });

  test('rejects a line naming more than one target', async () => {
    const res = await request(app)
      .post('/api/vendor-bills')
      .set(authHeader())
      .send(validBody({ raw_material_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' }));

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/only one of item, variant or raw material/);
  });
});

describe('DELETE /api/vendor-bills/:id — stock reversal', () => {
  test('subtracts the received quantity when the bill had applied stock', async () => {
    mockRequest.recordset = [universalRow()];

    const res = await request(app)
      .delete(`/api/vendor-bills/${BILL_ID}`)
      .set(authHeader());

    expect(res.status).toBe(200);
    const updates = stockUpdates();
    expect(updates).toHaveLength(1);
    expect(updates[0].inputs.id).toBe(ITEM_ID);
    expect(updates[0].inputs.qty).toBe(-5);
  });

  test('does not reverse stock the bill never applied', async () => {
    mockRequest.recordset = [universalRow({ stockApplied: 0 })];

    const res = await request(app)
      .delete(`/api/vendor-bills/${BILL_ID}`)
      .set(authHeader());

    expect(res.status).toBe(200);
    expect(stockUpdates()).toHaveLength(0);
  });
});
