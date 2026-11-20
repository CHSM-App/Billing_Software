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
  matchLines: jest.fn(),
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

  test('reverses applied stock even when inventory has since been turned off', async () => {
    mockRequest.recordset = [universalRow({ inventoryEnabled: 0 })];

    const res = await request(app)
      .delete(`/api/vendor-bills/${BILL_ID}`)
      .set(authHeader());

    expect(res.status).toBe(200);
    const updates = stockUpdates();
    expect(updates).toHaveLength(1);
    expect(updates[0].inputs.qty).toBe(-5);
  });
});

describe('PUT / DELETE read the bill under a row lock', () => {
  const headerReads = () => calls.filter((c) => /FROM vendor_bills vb\b/.test(c.sql)
    && /has_attachment/.test(c.sql));

  test.each([
    ['DELETE', () => request(app).delete(`/api/vendor-bills/${BILL_ID}`)],
    ['PUT', () => request(app).put(`/api/vendor-bills/${BILL_ID}`).send(validBody())],
  ])('%s locks the bill before reversing stock', async (_, send) => {
    mockRequest.recordset = [universalRow()];

    const res = await send().set(authHeader());

    expect(res.status).toBe(200);
    // The first read of the bill is the locked one, ahead of any stock move.
    const lockAt = calls.indexOf(headerReads()[0]);
    expect(calls[lockAt].sql).toMatch(/FROM vendor_bills vb WITH \(UPDLOCK, HOLDLOCK\)/);
    expect(lockAt).toBeLessThan(calls.indexOf(stockUpdates()[0]));
  });
});

describe('amount_paid follows the payment status', () => {
  const billInsert = () => calls.find((c) => /INSERT INTO vendor_bills \(/.test(c.sql));

  test.each([
    ['paid', undefined, 250],
    ['unpaid', 500, 0],
    ['partial', 100, 100],
  ])('%s with %s saves %s', async (status, amountPaid, saved) => {
    mockRequest.recordset = [universalRow()];

    const res = await request(app)
      .post('/api/vendor-bills')
      .set(authHeader())
      .send({ ...validBody(), payment_status: status, amount_paid: amountPaid });

    expect(res.status).toBe(201);
    expect(billInsert().inputs.amount_paid).toBe(saved);
  });

  test.each([0, 250, 300])('partial with %s is rejected', async (amountPaid) => {
    mockRequest.recordset = [universalRow()];

    const res = await request(app)
      .post('/api/vendor-bills')
      .set(authHeader())
      .send({ ...validBody(), payment_status: 'partial', amount_paid: amountPaid });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Amount paid/);
    expect(billInsert()).toBeUndefined();
  });

  test('an edit applies the same rule', async () => {
    mockRequest.recordset = [universalRow()];

    const res = await request(app)
      .put(`/api/vendor-bills/${BILL_ID}`)
      .set(authHeader())
      .send({ ...validBody(), payment_status: 'partial', amount_paid: 250 });

    expect(res.status).toBe(400);
    expect(calls.some((c) => /UPDATE vendor_bills SET/.test(c.sql))).toBe(false);
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
    else if (/SELECT business_type FROM businesses/.test(s)) rs = [{ business_type: state.type || 'retail' }];
    else if (/FROM raw_materials/.test(s)) rs = state.materials || [];
    else if (/LEFT JOIN item_variants/.test(s)) rs = state.catalogue || [];
    else if (/input_tokens = input_tokens \+/.test(s)) rs = [];
    else if (/AS duplicate_id/.test(s)) rs = state.duplicate ? [state.duplicate] : [];
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
    purchaseScan.matchLines.mockReset();
    purchaseScan.matchLines.mockResolvedValue({ results: [], usage: { input_tokens: 0, output_tokens: 0 } });
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
    state.catalogue = [{ item_id: ITEM_ID, variant_id: null, name: 'Amul Butter 100g' }];
    const res = await scan();
    expect(res.body.draft.lines[0].match).toEqual({
      item_id: ITEM_ID, variant_id: null, raw_material_id: null, in_packs: true,
    });
    const lookup = calls.find((c) => /FROM vendor_item_aliases/.test(c.sql));
    expect(lookup.inputs.business_id).toBe(BUSINESS_ID);
    expect(lookup.inputs.vendor_key).toBe('27ABCDE1234F1Z5');
    // Every line known: the catalogue is never sent to the AI.
    expect(purchaseScan.matchLines).not.toHaveBeenCalled();
  });

  test('a mapping to a since-deleted item is dropped and re-matched', async () => {
    state.aliases = [{
      vendor_text: 'amul butter 100g', item_id: ITEM_ID, variant_id: null,
      raw_material_id: null, in_packs: 0,
    }];
    state.catalogue = [{ item_id: BILL_ID, variant_id: null, name: 'Butter' }];
    const res = await scan();
    expect(res.body.draft.lines[0].match).toBeUndefined();
    expect(purchaseScan.matchLines).toHaveBeenCalledTimes(1);
  });

  describe('AI item matching', () => {
    const VARIANT_A = 'a0000000-0000-0000-0000-00000000000a';
    const VARIANT_B = 'b0000000-0000-0000-0000-00000000000b';
    beforeEach(() => {
      state.catalogue = [
        { item_id: ITEM_ID, variant_id: null, major_category: 'Dairy', category: 'Butter', name: 'Amul Butter 100g' },
        { item_id: BILL_ID, variant_id: VARIANT_A, name: 'Amul Butter', label: 'Salted' },
        { item_id: BILL_ID, variant_id: VARIANT_B, name: 'Amul Butter', label: 'Unsalted' },
      ];
    });

    test('sends unmatched lines with the category-path catalogue, names only', async () => {
      await scan();
      const [lines, catalogue] = purchaseScan.matchLines.mock.calls[0];
      expect(lines).toEqual([expect.objectContaining({ line: 0, text: 'Amul Butter 100g', unit: 'pcs' })]);
      expect(catalogue).toEqual(['Dairy > Butter > Amul Butter 100g', 'Amul Butter > Salted', 'Amul Butter > Unsalted']);
      const q = calls.find((c) => /LEFT JOIN item_variants/.test(c.sql));
      expect(q.inputs.business_id).toBe(BUSINESS_ID);
      expect(q.sql).not.toMatch(/price|stock/);
    });

    test('one ref links the line, marked as an AI match', async () => {
      purchaseScan.matchLines.mockResolvedValue({ results: [{ line: 0, refs: [2] }], usage: {} });
      const res = await scan();
      expect(res.body.draft.lines[0].match).toEqual({
        item_id: null, variant_id: VARIANT_A, raw_material_id: null, in_packs: false, source: 'ai',
      });
    });

    test('several refs become choices, not a link', async () => {
      purchaseScan.matchLines.mockResolvedValue({ results: [{ line: 0, refs: [2, 3] }], usage: {} });
      const res = await scan();
      expect(res.body.draft.lines[0].match).toBeUndefined();
      expect(res.body.draft.lines[0].suggest).toEqual([{ variant_id: VARIANT_A }, { variant_id: VARIANT_B }]);
    });

    test('refs outside the list sent are ignored', async () => {
      purchaseScan.matchLines.mockResolvedValue({ results: [{ line: 0, refs: [99] }], usage: {} });
      const res = await scan();
      expect(res.body.draft.lines[0].match).toBeUndefined();
      expect(res.body.draft.lines[0].suggest).toBeUndefined();
    });

    test('its tokens are added to the same scan', async () => {
      purchaseScan.matchLines.mockResolvedValue({ results: [], usage: { input_tokens: 800, output_tokens: 40 } });
      await scan();
      const add = calls.find((c) => /input_tokens = input_tokens \+/.test(c.sql));
      expect(add.inputs).toMatchObject({ input_tokens: 800, output_tokens: 40, business_id: BUSINESS_ID });
    });

    test('a matching failure still returns the scan, lines unlinked', async () => {
      purchaseScan.matchLines.mockRejectedValue(new Error('timeout'));
      const res = await scan();
      expect(res.status).toBe(200);
      expect(res.body.draft.lines[0].match).toBeUndefined();
      expect(scanRowUpdates('ok')).toHaveLength(1);
    });

    test('a sized bill sends only fitting entries and maps the answer back', async () => {
      const bill = aiBill();
      bill.raw.lines[0] = { ...bill.raw.lines[0], name: 'Apollo 215/65 R16 GOSS', free_quantity: 0, total_quantity: null };
      purchaseScan.extractPurchaseBill.mockResolvedValue(bill);
      state.catalogue = [
        { item_id: ITEM_ID, variant_id: null, name: 'Apollo Tyres 185/65 R15', label: null },
        { item_id: BILL_ID, variant_id: VARIANT_A, name: 'Apollo Tyres 215/65 R16', label: 'G055' },
        { item_id: BILL_ID, variant_id: VARIANT_B, name: 'Apollo Tyres 215/65 R16', label: 'G015' },
      ];
      purchaseScan.matchLines.mockResolvedValue({ results: [{ line: 0, refs: [1] }], usage: {} });
      const res = await scan();
      expect(purchaseScan.matchLines.mock.calls[0][1])
        .toEqual(['Apollo Tyres 215/65 R16 > G055', 'Apollo Tyres 215/65 R16 > G015']);
      // "1" is the first entry SENT — G055 — not the catalogue's first row.
      expect(res.body.draft.lines[0].match).toMatchObject({ variant_id: VARIANT_A, source: 'ai' });
    });

    test('a restaurant matches against its raw materials', async () => {
      state.type = 'restaurant_with_tables';
      state.materials = [{ id: ITEM_ID, name: 'Butter' }];
      purchaseScan.matchLines.mockResolvedValue({ results: [{ line: 0, refs: [1] }], usage: {} });
      const res = await scan();
      expect(purchaseScan.matchLines.mock.calls[0][1]).toEqual(['Butter']);
      expect(res.body.draft.lines[0].match).toMatchObject({ raw_material_id: ITEM_ID, item_id: null });
    });
  });

  test('warns first when this vendor invoice is already recorded', async () => {
    state.duplicate = { duplicate_id: BILL_ID, invoice_date: new Date('2026-10-05T00:00:00Z') };
    const res = await scan();
    expect(res.status).toBe(200);
    expect(res.body.warnings[0]).toEqual({
      code: 'duplicate_invoice', bill_id: BILL_ID, invoice_date: '2026-10-05',
    });
    const q = calls.find((c) => /AS duplicate_id/.test(c.sql));
    expect(q.sql).toMatch(/vendor_gstin = @gstin/);
    expect(q.inputs.business_id).toBe(BUSINESS_ID);
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

// ---------------------------------------------------------------------------
// Stock batches (batches.js)
// ---------------------------------------------------------------------------

describe('stock batches on purchases', () => {
  const NEW_BATCH = 'abababab-abab-abab-abab-abababababab';
  const OLD_BATCH = 'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd';

  /** Answers by what each statement reads; [state] is per test. */
  function batchDb(state) {
    mockRequest.query.mockImplementation(function (sqlText) {
      const s = String(sqlText);
      calls.push({ sql: s, inputs: { ...this.inputs } });
      let rs;
      if (/SELECT stock_quantity FROM/.test(s)) rs = [{ stock_quantity: state.stock === undefined ? 20 : state.stock }];
      else if (/MAX\(batch_seq\)/.test(s)) rs = [{ seq: 7 }];
      else if (/INSERT INTO stock_batches/.test(s)) rs = [{ id: NEW_BATCH }];
      else if (/FROM stock_batches WITH \(UPDLOCK\)\s+WHERE id = @id/.test(s)) rs = state.batch ? [state.batch] : [];
      else if (/created_by_vendor_bill_id = @vendor_bill_id AND batch_seq IS NOT NULL/.test(s)) rs = state.keptSeq ? [{ batch_seq: state.keptSeq }] : [];
      else if (/AND batch_no = @batch_no AND ABS\(unit_cost - @unit_cost\)/.test(s)) rs = state.sameBatch ? [{ id: state.sameBatch }] : [];
      else if (/FROM stock_batches WITH \(UPDLOCK\)\s+WHERE business_id/.test(s)) rs = state.open || [];
      else {
        rs = [{
          ...universalRow(),
          batch_tracking_enabled: state.on ? 1 : 0,
          batch_id: state.lineBatch || null,
        }];
      }
      return Promise.resolve({ recordset: rs, rowsAffected: [1] });
    });
  }

  const batchSql = () => calls.filter((c) => /stock_batches/.test(c.sql)
    && !/LEFT JOIN stock_batches/.test(c.sql));
  const lineInsert = () => calls.find((c) => /INSERT INTO vendor_bill_items/.test(c.sql));
  const batchInsert = () => calls.find((c) => /INSERT INTO stock_batches/.test(c.sql));
  const post = (body) => request(app).post('/api/vendor-bills').set(authHeader()).send(body);

  test('with batches off, a purchase runs no batch statements', async () => {
    batchDb({ on: false });
    const res = await post(validBody());
    expect(res.status).toBe(201);
    expect(batchSql()).toHaveLength(0);
    expect(lineInsert().inputs.batch_id).toBeNull();
  });

  test('a tracked line opens a new batch at its unit cost, numbered automatically', async () => {
    batchDb({ on: true });
    const res = await post(validBody());
    expect(res.status).toBe(201);
    const ins = batchInsert();
    expect(ins.inputs).toMatchObject({ batch_seq: 7, batch_no: 'B-0007', unit_cost: 50, qty: 5 });
    expect(ins.inputs.vendor_bill_id).toBe(BILL_ID);
    expect(lineInsert().inputs.batch_id).toBe(NEW_BATCH);
  });

  test('a typed batch no. is used as given, with no automatic number', async () => {
    batchDb({ on: true });
    await post(validBody({ batch_no: ' L-77 ' }));
    expect(batchInsert().inputs).toMatchObject({ batch_seq: null, batch_no: 'L-77' });
    expect(calls.some((c) => /MAX\(batch_seq\)/.test(c.sql))).toBe(false);
  });

  test('all new batches of one purchase share its batch no.', async () => {
    batchDb({ on: true });
    const OTHER = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
    await post({ ...validBody(), lines: [
      { item_id: ITEM_ID, name: 'Rice', quantity: 5, unit_price: 50 },
      { item_id: OTHER, name: 'Sugar', quantity: 2, unit_price: 40 },
    ] });
    const ins = calls.filter((c) => /INSERT INTO stock_batches/.test(c.sql)).map((c) => c.inputs.batch_no);
    expect(ins).toEqual(['B-0007', 'B-0007']);
    // One number for the purchase, not one per line.
    expect(calls.filter((c) => /MAX\(batch_seq\)/.test(c.sql))).toHaveLength(1);
  });

  test('reusing a batch no. for the same item at the same rate tops up that batch', async () => {
    batchDb({ on: true, sameBatch: OLD_BATCH });
    await post(validBody({ batch_no: 'B-001' }));
    expect(batchInsert()).toBeUndefined();
    const add = calls.find((c) => /SET qty_received = qty_received \+ @qty/.test(c.sql));
    expect(add.inputs).toMatchObject({ id: OLD_BATCH, qty: 5 });
    const look = calls.find((c) => /AND batch_no = @batch_no/.test(c.sql));
    expect(look.inputs).toMatchObject({ batch_no: 'B-001', unit_cost: 50 });
    expect(lineInsert().inputs.batch_id).toBe(OLD_BATCH);
  });

  test('an edit keeps the purchase\'s automatic number', async () => {
    batchDb({ on: true, keptSeq: 3 });
    await request(app).put(`/api/vendor-bills/${BILL_ID}`).set(authHeader()).send(validBody());
    expect(batchInsert().inputs).toMatchObject({ batch_seq: 3, batch_no: 'B-0003' });
    expect(calls.some((c) => /MAX\(batch_seq\)/.test(c.sql))).toBe(false);
  });

  test('the bill discount and free goods lower the unit cost', async () => {
    batchDb({ on: true });
    // Rs. 250 for 5 + 5 free, Rs. 25 off the bill: 225 / 10.
    const res = await post({ ...validBody({ free_quantity: 5 }), discount_amount: 25 });
    expect(res.status).toBe(201);
    expect(batchInsert().inputs).toMatchObject({ unit_cost: 22.5, qty: 10 });
  });

  test('a batch shop starts tracking an untracked item, then batches it', async () => {
    batchDb({ on: true, stock: 5 }); // what the item holds once received
    const res = await post(validBody());
    expect(res.status).toBe(201);
    const apply = calls.find((c) => /UPDATE items SET stock_quantity = ISNULL\(stock_quantity, 0\) \+ @qty/.test(c.sql));
    expect(apply).toBeDefined();
    // Never the parent of a sized item: its stock lives on the sizes.
    expect(apply.sql).toMatch(/NOT EXISTS \(\s*SELECT 1 FROM item_variants/);
    // Stock first, so the batch sees the newly tracked item.
    expect(calls.indexOf(apply)).toBeLessThan(calls.indexOf(batchInsert()));
  });

  test('with batches off, receiving still never starts tracking', async () => {
    batchDb({ on: false });
    await post(validBody());
    const apply = calls.find((c) => /UPDATE items SET stock_quantity/.test(c.sql));
    expect(apply.sql).toMatch(/AND stock_quantity IS NOT NULL/);
    expect(apply.sql).not.toMatch(/ISNULL/);
  });

  test('stock that stays untracked (a sized item\'s parent) gets no batch', async () => {
    batchDb({ on: true, stock: null });
    const res = await post(validBody());
    expect(res.status).toBe(201);
    expect(batchInsert()).toBeUndefined();
  });

  test('topping up an existing batch at the same rate adds to it', async () => {
    batchDb({ on: true, batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 50, batch_no: 'B-0003' } });
    const res = await post(validBody({ batch_id: OLD_BATCH }));
    expect(res.status).toBe(201);
    expect(batchInsert()).toBeUndefined();
    const add = calls.find((c) => /SET qty_received = qty_received \+ @qty/.test(c.sql));
    expect(add.inputs).toMatchObject({ id: OLD_BATCH, qty: 5 });
    expect(add.sql).not.toMatch(/unit_cost = @unit_cost/);
    expect(lineInsert().inputs.batch_id).toBe(OLD_BATCH);
  });

  test('topping up at a different rate is refused', async () => {
    batchDb({ on: true, batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 40, batch_no: 'B-0003' } });
    const res = await post(validBody({ batch_id: OLD_BATCH }));
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/rate differs from batch B-0003/);
    expect(lineInsert()).toBeUndefined();
  });

  test("another item's batch is refused", async () => {
    batchDb({ on: true, batch: { id: OLD_BATCH, item_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', unit_cost: 50, batch_no: 'B-0003' } });
    const res = await post(validBody({ batch_id: OLD_BATCH }));
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/not for this item/);
  });

  test('an edit takes back the old receipt and re-prices the batch it opened', async () => {
    batchDb({
      on: true,
      lineBatch: OLD_BATCH,
      keptSeq: 3,
      batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 50, batch_no: 'B-0003', created_by_vendor_bill_id: BILL_ID },
    });
    const res = await request(app).put(`/api/vendor-bills/${BILL_ID}`).set(authHeader())
      .send(validBody({ batch_id: OLD_BATCH, unit_price: 60 }));
    expect(res.status).toBe(200);
    const back = calls.find((c) => /SET qty_received = qty_received - @qty/.test(c.sql));
    expect(back.inputs).toMatchObject({ id: OLD_BATCH, qty: 5 });
    const add = calls.find((c) => /SET qty_received = qty_received \+ @qty/.test(c.sql));
    expect(add.sql).toMatch(/unit_cost = @unit_cost/);
    expect(add.inputs).toMatchObject({ unit_cost: 60 });
    // No batch no. sent: the batch keeps the name it has (#3).
    expect(add.sql).not.toMatch(/batch_no = @batch_no/);
    // Emptied batches go only after the re-receive, so the line keeps its id.
    const dropAt = calls.findIndex((c) => /DELETE FROM stock_batches/.test(c.sql));
    expect(dropAt).toBeGreaterThan(calls.indexOf(add));
  });

  test('an edit that types a batch no. renames the batch it opened', async () => {
    batchDb({
      on: true, lineBatch: OLD_BATCH,
      batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 50, batch_no: 'B-0003', created_by_vendor_bill_id: BILL_ID },
    });
    await request(app).put(`/api/vendor-bills/${BILL_ID}`).set(authHeader())
      .send(validBody({ batch_id: OLD_BATCH, batch_no: 'L-9' }));
    const add = calls.find((c) => /SET qty_received = qty_received \+ @qty/.test(c.sql));
    expect(add.inputs).toMatchObject({ batch_no: 'L-9', batch_seq: null });
  });

  test('an edit cannot take a batch below what was already sold', async () => {
    batchDb({
      on: true, lineBatch: OLD_BATCH,
      // After the old 5 are taken back: 0 received, 4 sold.
      batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 50, batch_no: 'B-0003',
        created_by_vendor_bill_id: BILL_ID, qty_received: 0, qty_sold: 4, qty_lost: 0 },
    });
    const res = await request(app).put(`/api/vendor-bills/${BILL_ID}`).set(authHeader())
      .send(validBody({ batch_id: OLD_BATCH, quantity: 3 }));
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/4 already sold from batch B-0003/);
  });

  test("an edited line in another purchase's batch moves to a new batch on a rate change", async () => {
    batchDb({
      on: true, lineBatch: OLD_BATCH,
      batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 50, batch_no: 'B-0002', batch_seq: 2,
        created_by_vendor_bill_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' },
    });
    const res = await request(app).put(`/api/vendor-bills/${BILL_ID}`).set(authHeader())
      .send(validBody({ batch_id: OLD_BATCH, unit_price: 60 }));
    expect(res.status).toBe(200);
    // Same batch no., its own row at the corrected cost.
    expect(batchInsert().inputs).toMatchObject({ batch_no: 'B-0002', batch_seq: 2, unit_cost: 60 });
  });

  test('a fresh top-up of another purchase\'s batch at a new rate is still refused', async () => {
    batchDb({
      on: true,
      batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 50, batch_no: 'B-0002',
        created_by_vendor_bill_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' },
    });
    const res = await post(validBody({ batch_id: OLD_BATCH, unit_price: 60 }));
    expect(res.status).toBe(400);
  });

  test('freight on the bill is spread into the goods\' cost', async () => {
    batchDb({ on: true });
    // Rice 5 × 50 = 250, freight 100: every rupee lands on the rice → 70 a unit.
    await post({ ...validBody(), lines: [
      { item_id: ITEM_ID, name: 'Rice', quantity: 5, unit_price: 50 },
      { name: 'Freight', quantity: 1, unit_price: 100 },
    ] });
    expect(batchInsert().inputs).toMatchObject({ unit_cost: 70, qty: 5 });
  });

  test('correcting the rate on a batch this bill opened re-costs its past sales', async () => {
    batchDb({
      on: true, lineBatch: OLD_BATCH,
      batch: { id: OLD_BATCH, item_id: ITEM_ID, unit_cost: 50, batch_no: 'B-0003', created_by_vendor_bill_id: BILL_ID },
    });
    await request(app).put(`/api/vendor-bills/${BILL_ID}`).set(authHeader())
      .send(validBody({ batch_id: OLD_BATCH, unit_price: 60 }));
    const clear = calls.find((c) => /UPDATE bi SET bi\.unit_cost = NULL/.test(c.sql));
    expect(clear.inputs.batch_id).toBe(OLD_BATCH);
  });

  test('a purchase never starts tracking a service', async () => {
    batchDb({ on: true, stock: 5 });
    await post(validBody());
    const apply = calls.find((c) => /UPDATE items SET stock_quantity = ISNULL/.test(c.sql));
    expect(apply.sql).toMatch(/is_service = 0/);
  });


  test('a delete takes back what its lines received', async () => {
    batchDb({ on: true, lineBatch: OLD_BATCH });
    const res = await request(app).delete(`/api/vendor-bills/${BILL_ID}`).set(authHeader());
    expect(res.status).toBe(200);
    expect(calls.some((c) => /SET qty_received = qty_received - @qty/.test(c.sql))).toBe(true);
    expect(calls.some((c) => /DELETE FROM stock_batches/.test(c.sql))).toBe(true);
  });

  test('a delete of a bill without batches runs no batch statements', async () => {
    batchDb({ on: true });
    const res = await request(app).delete(`/api/vendor-bills/${BILL_ID}`).set(authHeader());
    expect(res.status).toBe(200);
    expect(batchSql()).toHaveLength(0);
  });
});
