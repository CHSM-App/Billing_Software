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

// Only the AI call is faked; normalising, checks and alias keys run for real.
jest.mock('../../src/purchaseScan', () => ({
  ...jest.requireActual('../../src/purchaseScan'),
  extractPurchaseBill: jest.fn(),
}));
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));

const fs = require('fs');
const path = require('path');
const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const purchaseScan = require('../../src/purchaseScan');

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

// ---------------------------------------------------------------------------
// AI bill scanning
// ---------------------------------------------------------------------------

const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const SCAN_ID = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
const JPEG = Buffer.concat([Buffer.from([0xFF, 0xD8, 0xFF, 0xE0]), Buffer.alloc(64)]);

const aiBill = () => ({
  raw: {
    header: {
      vendor_name: 'Shree Traders', vendor_gstin: '27ABCDE1234F1Z5', invoice_number: 'ST/101',
      invoice_date: '2026-10-05', is_interstate: false, subtotal: 500, discount_amount: null,
      total_tax: 60, round_off: null, other_charges: null, total: 560,
    },
    lines: [{
      name: 'Amul Butter 100g', quantity: 10, free_quantity: 2, total_quantity: 12, unit: 'pcs',
      amount: 500, tax_rate: 12, cgst: 30, sgst: 30, igst: null, cess: null, hsn_code: '0405',
    }],
  },
  usage: { model: 'test-model', input_tokens: 1500, output_tokens: 700 },
});

/**
 * Answer each query by what it reads, so the scan flow's several statements
 * each get a sensible row. [state] is mutated per test.
 */
function scanDb(state) {
  mockRequest.query.mockImplementation(function (sqlText) {
    const s = String(sqlText);
    calls.push({ sql: s, inputs: { ...this.inputs } });
    let rs;
    if (/FROM subscriptions/.test(s)) rs = state.sub ? [state.sub] : [];
    else if (/COUNT\(\*\) AS used/.test(s)) rs = [{ used: state.used || 0 }];
    else if (/FROM vendor_item_aliases/.test(s)) rs = state.aliases || [];
    else if (/FROM purchase_scans\s+WHERE id = @scan_id/.test(s)) rs = state.scanOk ? [{ id: SCAN_ID }] : [];
    else if (/INNER JOIN purchase_scans/.test(s)) rs = state.attachment ? [state.attachment] : [];
    else if (/SELECT ps\.id, ps\.file_path/.test(s)) rs = [];
    else rs = [universalRow()];
    return Promise.resolve({ recordset: rs, rowsAffected: [1] });
  });
}

const scan = (body = JPEG, type = 'image/jpeg') => request(app)
  .post('/api/vendor-bills/scan')
  .set(authHeader())
  .set('Content-Type', type)
  .send(body);

const scanRowUpdates = (status) =>
  calls.filter((c) => /UPDATE purchase_scans SET status/.test(c.sql) && c.inputs.status === status);

describe('POST /api/vendor-bills/scan', () => {
  let state;
  beforeEach(() => {
    process.env.ANTHROPIC_API_KEY = 'test-key';
    process.env.PURCHASE_SCAN_MODEL = 'test-model';
    delete process.env.PURCHASE_SCAN_MONTHLY_LIMIT;
    state = { sub: { allow_purchase_scan: 1, purchase_scan_limit: null }, used: 0 };
    scanDb(state);
    purchaseScan.extractPurchaseBill.mockReset();
    purchaseScan.extractPurchaseBill.mockResolvedValue(aiBill());
  });

  afterAll(() => {
    fs.rmSync(path.join(purchaseScan.PRIVATE_DIR, BUSINESS_ID), { recursive: true, force: true });
    delete process.env.ANTHROPIC_API_KEY;
    delete process.env.PURCHASE_SCAN_MODEL;
  });

  test('rejects an unsupported content type', async () => {
    const res = await scan(Buffer.from('hello'), 'text/plain');
    expect(res.status).toBe(400);
    expect(purchaseScan.extractPurchaseBill).not.toHaveBeenCalled();
  });

  test('rejects a body whose bytes are not the declared type', async () => {
    const res = await scan(Buffer.from('not really a jpeg'), 'image/jpeg');
    expect(res.status).toBe(400);
  });

  test('rejects an image over 5 MB', async () => {
    const big = Buffer.concat([JPEG, Buffer.alloc(5 * 1024 * 1024)]);
    const res = await scan(big, 'image/jpeg');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/too large/);
  });

  test('rejects a PDF with too many pages', async () => {
    const pdf = Buffer.from('%PDF-1.4 ' + '/Type /Page '.repeat(21));
    const res = await scan(pdf, 'application/pdf');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/21 pages/);
  });

  test('503 when the server has no API key', async () => {
    delete process.env.ANTHROPIC_API_KEY;
    const res = await scan();
    expect(res.status).toBe(503);
  });

  test('403 when the admin has not enabled scanning (NULL)', async () => {
    state.sub = { allow_purchase_scan: null, purchase_scan_limit: null };
    const res = await scan();
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/Contact Vittam/);
    expect(purchaseScan.extractPurchaseBill).not.toHaveBeenCalled();
  });

  test('429 once the monthly allowance is used', async () => {
    process.env.PURCHASE_SCAN_MONTHLY_LIMIT = '3';
    state.used = 3;
    const res = await scan();
    expect(res.status).toBe(429);
    expect(purchaseScan.extractPurchaseBill).not.toHaveBeenCalled();
  });

  test('the business limit overrides the .env default', async () => {
    process.env.PURCHASE_SCAN_MONTHLY_LIMIT = '100';
    state.sub.purchase_scan_limit = 2;
    state.used = 2;
    expect((await scan()).status).toBe(429);
    state.sub.purchase_scan_limit = 5;
    expect((await scan()).status).toBe(200);
  });

  test('reserves quota under a lock on the subscription row, inside the transaction', async () => {
    const res = await scan();
    expect(res.status).toBe(200);
    const lockAt = calls.findIndex((c) => /FROM subscriptions\s+WITH \(UPDLOCK, HOLDLOCK\)/.test(c.sql));
    const countAt = calls.findIndex((c) => /COUNT\(\*\) AS used/.test(c.sql));
    const insertAt = calls.findIndex((c) => /INSERT INTO purchase_scans/.test(c.sql));
    expect(lockAt).toBeGreaterThanOrEqual(0);
    expect(lockAt).toBeLessThan(countAt);
    expect(countAt).toBeLessThan(insertAt);
    expect(calls[insertAt].sql).toMatch(/'pending'/);
  });

  test('failed scans never count against the allowance', async () => {
    await scan();
    const count = calls.find((c) => /COUNT\(\*\) AS used/.test(c.sql));
    expect(count.sql).toMatch(/status = 'ok'/);
    expect(count.sql).not.toMatch(/'failed'/);
  });

  test('an AI failure is logged as failed and returns 502', async () => {
    purchaseScan.extractPurchaseBill.mockRejectedValue(
      Object.assign(new Error('model refused'), { usage: { model: 'test-model', input_tokens: 900 } }));
    const res = await scan();
    expect(res.status).toBe(502);
    const failed = scanRowUpdates('failed');
    expect(failed).toHaveLength(1);
    expect(failed[0].inputs.failure_reason).toBe('model refused');
    expect(failed[0].sql).toMatch(/file_path = NULL/);
  });

  test('a successful scan returns the normalised draft, warnings and usage', async () => {
    state.used = 4;
    const res = await scan();
    expect(res.status).toBe(200);
    expect(res.body.scan_id).toMatch(/^[0-9a-f-]{36}$/);
    expect(res.body.draft.header.vendor_gstin).toBe('27ABCDE1234F1Z5');
    expect(res.body.draft.lines[0]).toMatchObject({ quantity: 10, free_quantity: 2, amount: 500 });
    expect(res.body.warnings).toEqual([]);
    expect(res.body.scans_used).toBe(5);
    expect(res.body.scans_limit).toBe(100);
    const ok = scanRowUpdates('ok');
    expect(ok).toHaveLength(1);
    expect(ok[0].inputs.input_tokens).toBe(1500);
  });

  test('attaches the saved item mappings for this vendor', async () => {
    state.aliases = [{
      vendor_text: 'amul butter 100g', item_id: ITEM_ID, variant_id: null,
      raw_material_id: null, in_packs: 1,
    }];
    const res = await scan();
    expect(res.body.draft.lines[0].match).toEqual({
      item_id: ITEM_ID, variant_id: null, raw_material_id: null, in_packs: true,
    });
    const lookup = calls.find((c) => /FROM vendor_item_aliases/.test(c.sql));
    expect(lookup.inputs.business_id).toBe(BUSINESS_ID);
    expect(lookup.inputs.vendor_key).toBe('27ABCDE1234F1Z5');
  });
});

describe('GET /api/vendor-bills/scan/status', () => {
  beforeEach(() => {
    process.env.ANTHROPIC_API_KEY = 'test-key';
    process.env.PURCHASE_SCAN_MODEL = 'test-model';
  });
  afterAll(() => {
    delete process.env.ANTHROPIC_API_KEY;
    delete process.env.PURCHASE_SCAN_MODEL;
  });

  test('reports enabled, used and limit', async () => {
    scanDb({ sub: { allow_purchase_scan: 1, purchase_scan_limit: 40 }, used: 7 });
    const res = await request(app).get('/api/vendor-bills/scan/status').set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ enabled: true, used: 7, limit: 40 });
  });

  test('a business without a subscription row is not enabled', async () => {
    scanDb({ sub: null, used: 0 });
    const res = await request(app).get('/api/vendor-bills/scan/status').set(authHeader());
    expect(res.body.enabled).toBe(false);
  });
});

describe('saving a scanned bill', () => {
  const scannedBody = (over = {}) => ({
    ...validBody({ vendor_text: 'Amul Butter 100g', free_quantity: 2 }),
    vendor_gstin: '27ABCDE1234F1Z5',
    scan_id: SCAN_ID,
    ...over,
  });

  test('rejects a scan id that is not a finished scan of this business', async () => {
    scanDb({ scanOk: false });
    const res = await request(app).post('/api/vendor-bills').set(authHeader()).send(scannedBody());
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Unknown bill scan');
    const check = calls.find((c) => /FROM purchase_scans\s+WHERE id = @scan_id/.test(c.sql));
    expect(check.inputs.business_id).toBe(BUSINESS_ID);
    expect(calls.some((c) => /MERGE vendor_item_aliases/.test(c.sql))).toBe(false);
  });

  test('receives paid + free quantity into stock', async () => {
    scanDb({ scanOk: true });
    const res = await request(app).post('/api/vendor-bills').set(authHeader()).send(scannedBody());
    expect(res.status).toBe(201);
    expect(stockUpdates()[0].inputs.qty).toBe(7); // 5 paid + 2 free
  });

  test('learns the vendor mapping only after the bill is saved', async () => {
    scanDb({ scanOk: true });
    const res = await request(app).post('/api/vendor-bills').set(authHeader()).send(scannedBody());
    expect(res.status).toBe(201);
    const mergeAt = calls.findIndex((c) => /MERGE vendor_item_aliases/.test(c.sql));
    const lineInsertAt = calls.findIndex((c) => /INSERT INTO vendor_bill_items/.test(c.sql));
    const stockAt = calls.findIndex((c) => /UPDATE items SET stock_quantity/.test(c.sql));
    expect(mergeAt).toBeGreaterThan(lineInsertAt);
    expect(mergeAt).toBeGreaterThan(stockAt);
    expect(calls[mergeAt].inputs).toMatchObject({
      business_id: BUSINESS_ID, vendor_key: '27ABCDE1234F1Z5',
      vendor_text: 'amul butter 100g', item_id: ITEM_ID,
    });
  });

  test('a hand-typed line (no vendor_text) teaches nothing', async () => {
    scanDb({ scanOk: true });
    await request(app).post('/api/vendor-bills').set(authHeader())
      .send(scannedBody({ lines: validBody().lines }));
    expect(calls.some((c) => /MERGE vendor_item_aliases/.test(c.sql))).toBe(false);
  });
});

describe('GET /api/vendor-bills/:id/attachment', () => {
  test('404 when the bill is not this business or has no file', async () => {
    scanDb({ attachment: null });
    const res = await request(app).get(`/api/vendor-bills/${BILL_ID}/attachment`).set(authHeader());
    expect(res.status).toBe(404);
    const q = calls.find((c) => /INNER JOIN purchase_scans/.test(c.sql));
    expect(q.inputs.business_id).toBe(BUSINESS_ID);
    expect(q.sql).toMatch(/ps\.business_id = vb\.business_id/);
  });

  test('refuses a stored path that escapes the private folder', async () => {
    scanDb({ attachment: { file_path: '../../src/server.js', media_type: 'image/jpeg' } });
    const res = await request(app).get(`/api/vendor-bills/${BILL_ID}/attachment`).set(authHeader());
    expect(res.status).toBe(404);
  });

  test('streams the stored file privately', async () => {
    const rel = `${BUSINESS_ID}/test-attachment.jpg`;
    const abs = path.join(purchaseScan.PRIVATE_DIR, rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, JPEG);
    try {
      scanDb({ attachment: { file_path: rel, media_type: 'image/jpeg' } });
      const res = await request(app).get(`/api/vendor-bills/${BILL_ID}/attachment`).set(authHeader());
      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toMatch(/image\/jpeg/);
      expect(res.headers['cache-control']).toBe('private, no-store');
    } finally {
      fs.rmSync(path.join(purchaseScan.PRIVATE_DIR, BUSINESS_ID), { recursive: true, force: true });
    }
  });

  test('requires the owner', async () => {
    const res = await request(app).get(`/api/vendor-bills/${BILL_ID}/attachment`)
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });
});
