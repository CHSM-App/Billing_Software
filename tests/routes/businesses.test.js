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
