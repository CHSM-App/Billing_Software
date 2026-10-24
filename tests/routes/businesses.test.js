const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

// A business row as returned by the "snapshot old values" SELECT in
// PUT /api/businesses/profile.
function oldRow(overrides = {}) {
  return {
    name: 'Sharma General Store',
    address: 'Sawantwadi',
    phone: '9876543210',
    email: null,
    website: null,
    city: null,
    state: null,
    pincode: null,
    gst_number: null,
    pan_number: null,
    fssai_number: null,
    logo_url: null,
    bill_prefix: null,
    bill_footer_note: null,
    gst_enabled: false,
    default_sac_code: null,
    round_off_enabled: false,
    ...overrides,
  };
}

beforeEach(() => {
  mockRequest.reset();
  mockRequest.query.mockImplementation(function () {
    return Promise.resolve({ recordset: this.recordset, rowsAffected: this.rowsAffected });
  });
});

// ------------------------------------------------------------------
// GST toggle — requires a GSTIN
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// UPI ID — checked here as well as in the app, because a malformed VPA
// reaches a customer's phone as a Pay button that opens their UPI app on
// an address that does not exist.
// ------------------------------------------------------------------
describe('PUT /api/businesses/profile — UPI ID', () => {
  test('rejects a UPI ID with no @psp', async () => {
    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader())
      .send({ store_upi_id: 'shopname' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/UPI/i);
  });

  test('rejects a UPI ID containing a space', async () => {
    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader())
      .send({ store_upi_id: 'shop name@okhdfcbank' });
    expect(res.status).toBe(400);
  });

  test('accepts a dotted VPA', async () => {
    mockRequest.recordset = [oldRow()];
    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader())
      .send({ store_upi_id: 'shop.name@okhdfcbank' });
    expect(res.status).toBe(200);
  });

  test('accepts a phone-number VPA', async () => {
    mockRequest.recordset = [oldRow()];
    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader())
      .send({ store_upi_id: '9422229951@ybl' });
    expect(res.status).toBe(200);
  });
});

describe('PUT /api/businesses/profile — GST toggle guard', () => {
  test('rejects turning GST on when the business has no GSTIN', async () => {
    // Only the old-values snapshot runs; the request is rejected before UPDATE.
    mockRequest.query.mockResolvedValueOnce({
      recordset: [oldRow({ gst_number: null })],
      rowsAffected: [1],
    });

    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ gst_enabled: true });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/GSTIN/i);
  });

  test('allows turning GST on when a GSTIN is already stored', async () => {
    mockRequest.query
      .mockResolvedValueOnce({
        recordset: [oldRow({ gst_number: '27ABCDE1234F1Z5' })],
        rowsAffected: [1],
      })
      // UPDATE, then the re-SELECT of the updated row.
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [oldRow({ gst_number: '27ABCDE1234F1Z5', gst_enabled: true })],
        rowsAffected: [1],
      });

    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ gst_enabled: true });

    expect(res.status).toBe(200);
  });

  test('allows setting a GSTIN and turning GST on in one request', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [oldRow()], rowsAffected: [1] })
      // GSTIN uniqueness check — no other business holds it.
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [oldRow({ gst_number: '27ABCDE1234F1Z5', gst_enabled: true })],
        rowsAffected: [1],
      });

    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ gst_enabled: true, gst_number: '27ABCDE1234F1Z5' });

    expect(res.status).toBe(200);
  });

  test('rejects turning GST on while clearing the GSTIN in the same request', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [oldRow({ gst_number: '27ABCDE1234F1Z5' })],
      rowsAffected: [1],
    });

    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ gst_enabled: true, gst_number: '' });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/GSTIN/i);
  });

  test('turning GST OFF is always allowed, even with no GSTIN', async () => {
    mockRequest.query
      .mockResolvedValueOnce({
        recordset: [oldRow({ gst_number: null, gst_enabled: true })],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [oldRow()], rowsAffected: [1] });

    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ gst_enabled: false });

    expect(res.status).toBe(200);
  });
});

// ------------------------------------------------------------------
// Shop logo upload — owner-only, JPEG-only (same guard as the store QR).
// ------------------------------------------------------------------
describe('PUT /api/businesses/logo', () => {
  const fs = require('fs');
  const path = require('path');
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);

  test('rejects a non-JPEG body', async () => {
    const res = await request(app)
      .put('/api/businesses/logo')
      .set(authHeader())
      .set('Content-Type', 'image/jpeg')
      .send(Buffer.from('<svg/>'));
    expect(res.status).toBe(400);
  });

  test('a cashier cannot change the logo', async () => {
    const res = await request(app)
      .put('/api/businesses/logo')
      .set(authHeader({ role: 'cashier' }))
      .set('Content-Type', 'image/jpeg')
      .send(jpeg);
    expect(res.status).toBe(403);
  });

  test('owner upload stores the file and returns a cache-busted URL', async () => {
    const res = await request(app)
      .put('/api/businesses/logo')
      .set(authHeader())
      .set('Content-Type', 'image/jpeg')
      .send(jpeg);
    expect(res.status).toBe(200);
    expect(res.body.logo_url).toMatch(/^\/uploads\/logo\/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb\.jpg\?v=\d+$/);
    const file = path.join(__dirname, '..', '..', 'uploads', 'logo', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg');
    expect(fs.existsSync(file)).toBe(true);
    fs.unlinkSync(file);
  });
});

// ------------------------------------------------------------------
// show_item_no — shop-wide "(101) Masala Dosa" on the billing page
// ------------------------------------------------------------------
describe('PUT /api/businesses/profile — show_item_no', () => {
  test.each([
    [true, 1],
    [false, 0],
    ['1', 1],
  ])('show_item_no %p is stored as BIT %p and returned as a boolean', async (sent, bit) => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [oldRow({ show_item_no: !bit })], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [oldRow({ show_item_no: bit })], rowsAffected: [1] });

    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ show_item_no: sent });

    expect(res.status).toBe(200);
    expect(mockRequest.inputs.show_item_no).toBe(bit);
    const updateSql = mockRequest.query.mock.calls.map((c) => c[0]).find((s) => /UPDATE businesses/.test(s));
    expect(updateSql).toMatch(/show_item_no = @show_item_no/);
    expect(res.body.show_item_no).toBe(!!bit);
  });

  test('only the owner can change it', async () => {
    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'cashier' }))
      .send({ show_item_no: true });
    expect(res.status).toBe(403);
  });

  test('GET /profile returns show_item_no (false when the column is 0)', async () => {
    mockRequest.recordset = [oldRow({ show_item_no: 0 })];
    const res = await request(app)
      .get('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body.show_item_no).toBe(false);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/b\.show_item_no/);
  });
});

// Billing Setup (migration 061): an object in, JSON text in the column,
// the parsed object (with defaults) back out.
describe('PUT /api/businesses/profile — bill_settings', () => {
  test('stores validated JSON and returns the parsed settings', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [oldRow()], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [oldRow({ bill_settings: '{"show_cashier":false}' })], rowsAffected: [1] });

    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ bill_settings: { show_cashier: false, bank: { ifsc: 'sbin0001234' } } });

    expect(res.status).toBe(200);
    const stored = JSON.parse(mockRequest.inputs.bill_settings);
    expect(stored.show_cashier).toBe(false);
    expect(stored.bank.ifsc).toBe('SBIN0001234');
    expect(res.body.bill_settings.show_cashier).toBe(false);
    expect(res.body.bill_settings.show_bank).toBe(false);
  });

  test('rejects a bad IFSC', async () => {
    const res = await request(app)
      .put('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }))
      .send({ bill_settings: { show_bank: true, bank: { ifsc: 'BAD' } } });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/IFSC/);
  });

  test('GET /profile returns defaults when the column is NULL', async () => {
    mockRequest.recordset = [oldRow()];
    const res = await request(app)
      .get('/api/businesses/profile')
      .set(authHeader({ role: 'owner' }));
    expect(res.body.bill_settings.show_cashier).toBe(true);
    expect(res.body.bill_settings.show_bank).toBe(false);
  });
});
