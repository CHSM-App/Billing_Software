// Everything shipped after the 1.1.15+28 deploy (eec6f96) — Billing Setup,
// customer address/GSTIN, warranties, quotations, notification prefs — is
// opt-in. These pin that an OLDER APP build, and a shop that never touched any
// of the new settings, gets exactly the behaviour it had before, plus the
// new-feature edges the per-route suites leave uncovered.
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const bcrypt = require('bcryptjs');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
jest.mock('../../src/customers', () => ({
  ...jest.requireActual('../../src/customers'),
  upsertCustomer: jest.fn(() => Promise.resolve()),
  syncCustomers: jest.fn(() => Promise.resolve()),
}));
jest.mock('../../src/audit'); // every logger a no-op jest.fn

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const billSettings = require('../../src/billSettings');

const BILL_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const BILL_ITEM_ID = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

const sampleBill = {
  id: BILL_ID, bill_number: 'INV-0001', customer_name: 'Alice', customer_phone: '9876543210',
  subtotal: 100, tax_amount: 0, total: 100, payment_mode: 'cash', status: 'finalized',
  created_at: new Date().toISOString(), receipt_token: 'abcdef1234567890',
};

// Fire-and-forget work (autoCreateWarranties) runs after the response.
const flush = async () => { for (let i = 0; i < 10; i++) await new Promise((r) => setImmediate(r)); };

/// Answers every pool query by its SQL and records it with the inputs bound
/// at that moment.
function poolDb(answer) {
  const calls = [];
  mockRequest.query.mockImplementation(function (s) {
    calls.push({ s, inputs: { ...this.inputs } });
    return Promise.resolve(answer(s) || { recordset: [], rowsAffected: [0] });
  });
  return { calls, find: (re) => calls.find((c) => re.test(c.s)) };
}

/// Same for the POST /api/bills transaction.
function txDb() {
  const calls = [];
  mockTransaction.request.mockImplementation(() => {
    const inputs = {};
    const r = {
      input(k, _t, v) { inputs[k] = v; return r; },
      query: jest.fn((s) => {
        calls.push({ s, inputs });
        const ok = (rs = []) => Promise.resolve({ recordset: rs, rowsAffected: [rs.length || 1] });
        if (/COUNT\(\*\) AS cnt/.test(s)) return ok([{ cnt: 0 }]);
        if (/INSERT INTO bills/.test(s)) return ok([{ id: BILL_ID }]);
        if (/FROM businesses/.test(s)) return ok([{ inventory_enabled: false, round_off_enabled: false, gst_enabled: false }]);
        if (/^\s*SELECT[\s\S]*FROM items\b/.test(s)) return ok([{ id: ITEM_ID, name: 'Rice', price: 50, tax_rate: null }]);
        return ok();
      }),
    };
    return r;
  });
  return { calls, find: (re) => calls.find((c) => re.test(c.s)) };
}

beforeEach(() => {
  mockRequest.reset();
  jest.clearAllMocks();
  mockRequest.query.mockImplementation(function () {
    return Promise.resolve({ recordset: this.recordset, rowsAffected: this.rowsAffected });
  });
});

// ------------------------------------------------------------------
// Migrations 060–068 run against live data: every column they add to an
// existing table must be NULL-able or defaulted, or the ALTER fails on a
// populated table / older app inserts start failing.
// ------------------------------------------------------------------
describe('migrations 060–068 are safe on existing data', () => {
  const dir = path.join(__dirname, '../../src/migrations');
  const files = fs.readdirSync(dir).filter((f) => /^06[0-8]_.*\.sql$/.test(f) && !/rollback/.test(f));

  test('every migration in the range is present', () => {
    expect(files.map((f) => f.slice(0, 3)).sort()).toEqual(
      ['060', '061', '062', '063', '064', '065', '066', '067', '068']);
  });

  test.each(files)('%s adds no NOT NULL column without a DEFAULT', (f) => {
    const text = fs.readFileSync(path.join(dir, f), 'utf8').replace(/--.*$/gm, '');
    // Column definitions after ALTER TABLE ... ADD (CREATE TABLE is a new table — exempt).
    const alters = text.match(/ALTER\s+TABLE\s+\w+\s+ADD[\s\S]*?(?=\bGO\b|$)/gi) || [];
    for (const stmt of alters) {
      for (const col of stmt.replace(/ALTER\s+TABLE\s+\w+\s+ADD/i, '').split(',')) {
        if (/NOT\s+NULL/i.test(col)) expect(col).toMatch(/DEFAULT/i);
      }
    }
  });

  test('notification prefs default ON, so existing owners/cashiers keep their pushes', () => {
    const text = fs.readFileSync(path.join(dir, '067_add_user_notify_prefs.sql'), 'utf8');
    expect(text).toMatch(/notify_low_stock\s+BIT NOT NULL DEFAULT 1/);
    expect(text).toMatch(/notify_online_orders\s+BIT NOT NULL DEFAULT 1/);
  });

  test('new feature flags default OFF', () => {
    const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8');
    expect(read('062_add_item_warranty_fields.sql')).toMatch(/warranty_eligible BIT NOT NULL[\s\S]*DEFAULT 0/);
    expect(read('066_convert_retail_warranty_to_flag.sql')).toMatch(/warranty_enabled BIT NOT NULL[\s\S]*DEFAULT 0/);
    expect(read('068_add_quotations.sql')).toMatch(/quotations_enabled BIT NOT NULL[\s\S]*DEFAULT 0/);
  });
});

// ------------------------------------------------------------------
// POST /api/bills — an older app's payload
// ------------------------------------------------------------------
describe('POST /api/bills from an older app', () => {
  const oldPayload = { items: [{ item_id: ITEM_ID, quantity: 2 }], payment_mode: 'cash', status: 'finalized' };

  test('saves exactly as before: no warranty data, no quotation touched', async () => {
    const tx = txDb();
    poolDb((s) => (/FROM bills b/.test(s) ? { recordset: [sampleBill], rowsAffected: [1] } : null));

    const res = await request(app).post('/api/bills').set(authHeader({ role: 'cashier' })).send(oldPayload);

    expect(res.status).toBe(201);
    const bill = tx.find(/INSERT INTO bills/).inputs;
    expect(bill.warranty_extra_data).toBeNull();
    expect(bill.customer_address).toBeNull();
    expect(bill.customer_gstin).toBeNull();
    expect(tx.find(/UPDATE quotations/)).toBeUndefined();
    expect(mockTransaction.commit).toHaveBeenCalled();
  });

  test('an empty warranty_extra_data array is stored as NULL, not "[]"', async () => {
    const tx = txDb();
    poolDb((s) => (/FROM bills b/.test(s) ? { recordset: [sampleBill], rowsAffected: [1] } : null));
    await request(app).post('/api/bills').set(authHeader()).send({ ...oldPayload, warranty_extra_data: [] });
    expect(tx.find(/INSERT INTO bills/).inputs.warranty_extra_data).toBeNull();
  });

  test('warranty_extra_data is stored as JSON when sent', async () => {
    const tx = txDb();
    poolDb((s) => (/FROM bills b/.test(s) ? { recordset: [sampleBill], rowsAffected: [1] } : null));
    const extra = [{ label: 'KM Reading', value: '45230' }];
    const res = await request(app).post('/api/bills').set(authHeader()).send({ ...oldPayload, warranty_extra_data: extra });
    expect(res.status).toBe(201);
    expect(JSON.parse(tx.find(/INSERT INTO bills/).inputs.warranty_extra_data)).toEqual(extra);
  });

  test.each([
    ['not an array', { label: 'KM', value: '1' }],
    ['an entry without a label', [{ value: '1' }]],
    ['a value over 500 chars', [{ label: 'KM', value: 'x'.repeat(501) }]],
    ['more than 30 entries', Array.from({ length: 31 }, (_, i) => ({ label: `f${i}`, value: '1' }))],
  ])('rejects warranty_extra_data that is %s with 400', async (_n, extra) => {
    const res = await request(app).post('/api/bills').set(authHeader()).send({ ...oldPayload, warranty_extra_data: extra });
    expect(res.status).toBe(400);
    expect(mockTransaction.begin).not.toHaveBeenCalled();
  });

  test('a failing warranty lookup never fails the sale', async () => {
    txDb();
    poolDb((s) => {
      if (/warranty_eligible = 1/.test(s)) return Promise.reject(new Error('Invalid object name warranties'));
      return /FROM bills b/.test(s) ? { recordset: [sampleBill], rowsAffected: [1] } : null;
    });
    const res = await request(app).post('/api/bills').set(authHeader()).send(oldPayload);
    await flush();
    expect(res.status).toBe(201);
  });

  test('a draft creates no warranties (they come on finalize)', async () => {
    txDb();
    const db = poolDb((s) => (/FROM bills b/.test(s) ? { recordset: [sampleBill], rowsAffected: [1] } : null));
    await request(app).post('/api/bills').set(authHeader()).send({ ...oldPayload, status: 'draft' });
    await flush();
    expect(db.find(/warranty_eligible = 1/)).toBeUndefined();
  });
});

// ------------------------------------------------------------------
// PUT /api/bills/:id/finalize + autoCreateWarranties
// ------------------------------------------------------------------
describe('PUT /api/bills/:id/finalize — warranties', () => {
  const warrantyRow = (over = {}) => ({
    bill_item_id: BILL_ITEM_ID, item_id: ITEM_ID, item_name: 'MRF Tyre', category: 'Tyres',
    default_warranty_months: 24, customer_name: 'Ravi', customer_phone: '9876543210',
    warranty_extra_data: '[{"label":"KM","value":"12000"}]',
    purchase_date: new Date('2026-03-15T00:00:00Z'), ...over,
  });

  function finalizeDb(warrantyRows = []) {
    return poolDb((s) => {
      if (/SET status = 'finalized'/.test(s)) {
        return { recordset: [{ id: BILL_ID, table_id: null, bill_number: 'INV-0001', payment_mode: 'cash' }], rowsAffected: [1] };
      }
      if (/warranty_eligible = 1/.test(s)) return { recordset: warrantyRows, rowsAffected: [warrantyRows.length] };
      if (/FROM bills b/.test(s)) return { recordset: [sampleBill], rowsAffected: [1] };
      return null;
    });
  }
  const finalize = (body) => request(app).put(`/api/bills/${BILL_ID}/finalize`).set(authHeader()).send(body);

  test('an older app (no warranty_extra_data) never writes the column', async () => {
    const db = finalizeDb();
    const res = await finalize({});
    expect(res.status).toBe(200);
    expect(db.find(/SET warranty_extra_data/)).toBeUndefined();
  });

  test('warranty_extra_data sent at settle time is stored on the bill', async () => {
    const db = finalizeDb();
    const extra = [{ label: 'Vehicle No', value: 'MH07 AB 1234' }];
    expect((await finalize({ warranty_extra_data: extra })).status).toBe(200);
    expect(JSON.parse(db.find(/SET warranty_extra_data/).inputs.warranty_extra_data)).toEqual(extra);
  });

  test('rejects malformed warranty_extra_data before touching the bill', async () => {
    const db = finalizeDb();
    expect((await finalize({ warranty_extra_data: 'KM 1200' })).status).toBe(400);
    expect(db.calls).toHaveLength(0);
  });

  test('only warranty-eligible lines of a warranty-enabled shop are looked up', async () => {
    const db = finalizeDb();
    await finalize({});
    await flush();
    const lookup = db.find(/warranty_eligible = 1/);
    expect(lookup.s).toMatch(/bz\.warranty_enabled = 1/);
    expect(lookup.s).toMatch(/NOT EXISTS \(SELECT 1 FROM warranties w WHERE w\.bill_item_id = bi\.id\)/);
    expect(db.find(/INSERT INTO warranties/)).toBeUndefined();
  });

  test('an eligible line becomes a warranty with expiry = purchase + months', async () => {
    const db = finalizeDb([warrantyRow()]);
    await finalize({});
    await flush();
    const ins = db.find(/INSERT INTO warranties/).inputs;
    expect(ins).toMatchObject({
      bill_id: BILL_ID, bill_item_id: BILL_ITEM_ID, item_name: 'MRF Tyre', category: 'Tyres',
      customer_phone: '9876543210', warranty_months: 24,
      extra_data: '[{"label":"KM","value":"12000"}]',
    });
    expect(ins.expiry_date.toISOString().slice(0, 10)).toBe('2028-03-15');
  });

  test('a month-end purchase expires at the end of the target month, not after it', async () => {
    const db = finalizeDb([warrantyRow({ purchase_date: new Date('2026-01-31T00:00:00Z'), default_warranty_months: 1 })]);
    await finalize({});
    await flush();
    expect(db.find(/INSERT INTO warranties/).inputs.expiry_date.toISOString().slice(0, 10)).toBe('2026-02-28');
  });

  test('no period on the item falls back to 12 months', async () => {
    const db = finalizeDb([warrantyRow({ default_warranty_months: null })]);
    await finalize({});
    await flush();
    const ins = db.find(/INSERT INTO warranties/).inputs;
    expect(ins.warranty_months).toBe(12);
    expect(ins.expiry_date.toISOString().slice(0, 10)).toBe('2027-03-15');
  });

  test('a bill with no customer phone creates no orphan warranty', async () => {
    const db = finalizeDb([warrantyRow({ customer_phone: null })]);
    await finalize({});
    await flush();
    expect(db.find(/INSERT INTO warranties/)).toBeUndefined();
  });

  test('a failing warranty insert never fails the settle', async () => {
    finalizeDb([warrantyRow()]);
    const base = mockRequest.query.getMockImplementation();
    mockRequest.query.mockImplementation(function (s) {
      return /INSERT INTO warranties/.test(s) ? Promise.reject(new Error('boom')) : base.call(this, s);
    });
    const res = await finalize({});
    await flush();
    expect(res.status).toBe(200);
  });
});

// ------------------------------------------------------------------
// Items — an older app never sends the warranty fields
// ------------------------------------------------------------------
describe('items without warranty fields', () => {
  test('POST stores warranty_eligible 0 and no period', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] }); // name is free
    mockRequest.recordset = [{ id: ITEM_ID, name: 'Rice', price: 50 }];
    const res = await request(app).post('/api/items').set(authHeader()).send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.warranty_eligible).toBe(0);
    expect(mockRequest.inputs.default_warranty_months).toBeNull();
  });

  test('PUT of an unrelated field leaves the warranty columns alone', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID, price: 60 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app).put(`/api/items/${ITEM_ID}`).set(authHeader()).send({ price: 60 });
    expect(res.status).toBe(200);
    const update = mockRequest.query.mock.calls.map((c) => c[0]).find((s) => /UPDATE items/.test(s));
    expect(update).toMatch(/SET price = @price\s+OUTPUT/);
  });

  test('POST with warranty on but no period is a 400', async () => {
    const res = await request(app).post('/api/items').set(authHeader())
      .send({ name: 'Tyre', price: 5000, warranty_eligible: true });
    expect(res.status).toBe(400);
  });

  test.each([0, -3])('POST with a %p-month warranty is a 400', async (m) => {
    const res = await request(app).post('/api/items').set(authHeader())
      .send({ name: 'Tyre', price: 5000, warranty_eligible: true, default_warranty_months: m });
    expect(res.status).toBe(400);
  });

  test('re-saving a warranty item needn\'t resend the period already stored', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID, default_warranty_months: 24 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID, warranty_eligible: true }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app).put(`/api/items/${ITEM_ID}`).set(authHeader()).send({ warranty_eligible: true });
    expect(res.status).toBe(200);
  });

  test('PUT turning warranty on with no period anywhere is a 400', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [{ id: ITEM_ID, default_warranty_months: null }], rowsAffected: [1] });
    const res = await request(app).put(`/api/items/${ITEM_ID}`).set(authHeader()).send({ warranty_eligible: true });
    expect(res.status).toBe(400);
    expect(mockRequest.query.mock.calls.some((c) => /UPDATE items/.test(c[0]))).toBe(false);
  });

  test('PUT clearing the period while turning warranty on is a 400, even with one stored', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [{ id: ITEM_ID, default_warranty_months: 24 }], rowsAffected: [1] });
    const res = await request(app).put(`/api/items/${ITEM_ID}`).set(authHeader())
      .send({ warranty_eligible: true, default_warranty_months: null });
    expect(res.status).toBe(400);
  });

  test('turning warranty off needs no period', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID, warranty_eligible: false }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app).put(`/api/items/${ITEM_ID}`).set(authHeader()).send({ warranty_eligible: false });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.warranty_eligible).toBe(0);
  });
});

// ------------------------------------------------------------------
// Business profile — an older Settings screen never sends the new keys
// ------------------------------------------------------------------
describe('PUT /api/businesses/profile from an older app', () => {
  test('saving an old field does not touch bill_settings / warranty / quotations', async () => {
    const old = { name: 'Shop', phone: '9876543210', bill_footer_note: null, gst_enabled: false };
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [old], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ ...old, bill_footer_note: 'Visit again' }], rowsAffected: [1] });
    const res = await request(app).put('/api/businesses/profile').set(authHeader())
      .send({ bill_footer_note: 'Visit again' });
    expect(res.status).toBe(200);
    const update = mockRequest.query.mock.calls.map((c) => c[0]).find((s) => /UPDATE businesses/.test(s));
    expect(update).toMatch(/bill_footer_note = @bill_footer_note/);
    expect(update).not.toMatch(/bill_settings|warranty_enabled|quotations_enabled/);
    // NULL column comes back as the defaults = the bill as it always printed.
    expect(res.body.bill_settings).toEqual(billSettings.defaults());
    expect(res.body.warranty_enabled).toBe(false);
    expect(res.body.quotations_enabled).toBe(false);
  });
});

// ------------------------------------------------------------------
// Login — a shop that never saved any new setting
// ------------------------------------------------------------------
describe('POST /api/login for an untouched shop', () => {
  test('new flags are off and bill_settings are the defaults', async () => {
    const userRow = {
      id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', business_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      name: 'Owner', phone: '9876543210', pin_hash: await bcrypt.hash('1234', 4), role: 'owner',
      failed_attempts: 0, locked_until: null, business_name: 'Shop', business_type: 'retail',
      is_verified: true, inventory_enabled: 0, has_barcode_scanner: 0,
      // Column values after migrations 061/066/068 on an existing row.
      bill_settings: null, warranty_enabled: 0, quotations_enabled: 0, is_active: true,
    };
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });
    const res = await request(app).post('/api/login').send({ phone: '9876543210', pin: '1234' });
    expect(res.status).toBe(200);
    expect(res.body.business).toMatchObject({ warranty_enabled: false, quotations_enabled: false, bill_footer_note: null });
    expect(res.body.business.bill_settings).toEqual(billSettings.defaults());
  });
});

// ------------------------------------------------------------------
// Public receipt / invoice — NULL bill_settings prints what it always did
// ------------------------------------------------------------------
describe('receipt for a shop that never opened Billing Setup', () => {
  const row = {
    bill_number: 'INV-0007', customer_name: 'Alice', customer_phone: '9876543210',
    subtotal: 100, total: 100, payment_mode: 'cash', created_at: new Date('2024-01-15T10:00:00Z'),
    shop_name: 'My Shop', address: '123 Main St', shop_phone: '9876500000',
    gst_number: '27ABCDE1234F1Z5', fssai_number: '12345678901234', bill_footer_note: 'Visit again',
    billed_by: 'Ramesh', bill_settings: null, // + no customer_address / gstin / warranty_extra_data
  };
  const items = [{ item_name: 'Rice', quantity: 2, unit_price: 50, line_total: 100 }];
  const get = (q = '') => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: items, rowsAffected: [1] });
    return request(app).get(`/receipt/abcdef1234567890${q}`);
  };

  test('card receipt still shows every header line, customer, cashier and footer', async () => {
    const res = await get();
    expect(res.status).toBe(200);
    for (const s of ['123 Main St', 'Tel: 9876500000', 'GSTIN: 27ABCDE1234F1Z5',
      'FSSAI: 12345678901234', 'Cashier', 'Ramesh', 'Alice', 'Mob: 9876543210', 'Visit again']) {
      expect(res.text).toContain(s);
    }
    // Opt-in sections stay off.
    expect(res.text).not.toContain('Bank Details');
    expect(res.text).not.toContain('<b>Note</b>');
    expect(res.text).not.toContain('Address:');
    // The footer note prints plain, as before — no new heading over it.
    expect(res.text).toContain('<div class="note">Visit again</div>');
  });

  test('the footer gets its heading once a Note sits beside it', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row, bill_settings: '{"show_note":true,"note":"Free delivery"}' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: items, rowsAffected: [1] });
    const res = await request(app).get('/receipt/abcdef1234567890');
    expect(res.text).toContain('<b>Note</b><br/>Free delivery');
    expect(res.text).toContain('<b>Terms &amp; Conditions</b><br/>Visit again');
  });

  test('…or Bank Details', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row, bill_settings: '{"show_bank":true,"bank":{"account_no":"123456789"}}' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: items, rowsAffected: [1] });
    const res = await request(app).get('/receipt/abcdef1234567890');
    expect(res.text).toContain('A/c No: 123456789');
    expect(res.text).toContain('<b>Terms &amp; Conditions</b><br/>Visit again');
  });

  test('show_terms off hides the footer note entirely', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row, bill_settings: '{"show_terms":false}' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: items, rowsAffected: [1] });
    const res = await request(app).get('/receipt/abcdef1234567890');
    expect(res.text).not.toContain('Visit again');
  });

  test.each(['a4', 'a5'])('%s invoice still shows the header, customer and terms', async (p) => {
    const res = await get(`?p=${p}`);
    expect(res.status).toBe(200);
    for (const s of ['123 Main St', 'Ph: 9876500000', 'FSSAI: 12345678901234', 'Cashier', 'Alice',
      'Contact No.: 9876543210', 'Terms and conditions', 'Visit again']) {
      expect(res.text).toContain(s);
    }
    expect(res.text).not.toContain('Bank Details');
  });

  test('warranty details print on the card receipt when the bill carries them', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row, customer_name: null, customer_phone: null,
        warranty_extra_data: '[{"label":"KM Reading","value":"45230"}]' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: items, rowsAffected: [1] });
    const res = await request(app).get('/receipt/abcdef1234567890');
    expect(res.text).toContain('Billed To');
    expect(res.text).toContain('KM Reading: 45230');
  });

  test('corrupt bill_settings JSON falls back to the defaults, not a 500', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row, bill_settings: '{not json' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: items, rowsAffected: [1] });
    const res = await request(app).get('/receipt/abcdef1234567890');
    expect(res.status).toBe(200);
    expect(res.text).toContain('GSTIN: 27ABCDE1234F1Z5');
  });
});
