// Other billing devices re-read their item list on { type: 'stock' }. A
// purchase or a manual stock edit moves stock too, so they must announce it.
const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
jest.mock('../../src/audit', () => new Proxy({}, { get: () => jest.fn(() => Promise.resolve()) }));
jest.mock('../../src/realtime', () => ({ attach: jest.fn(), broadcast: jest.fn() }));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const { broadcast } = require('../../src/realtime');

const ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

beforeEach(() => { mockRequest.reset(); broadcast.mockClear(); });

test('a purchase that moves stock announces it', async () => {
  mockRequest.recordset = [{
    id: ID, inventory_enabled: 1, batch_tracking_enabled: 0, gst_enabled: 0, stock_applied: 1,
    vendor_name: 'A', invoice_number: '1', invoice_date: new Date('2026-11-01T00:00:00Z'),
    subtotal: 10, tax_amount: 0, cgst_amount: 0, sgst_amount: 0, igst_amount: 0, cess_amount: 0,
    discount_amount: 0, round_off: 0, total: 10, payment_status: 'paid', amount_paid: 10,
    item_id: ID, quantity: 1, unit_price: 10, line_total: 10,
  }];
  const res = await request(app).post('/api/vendor-bills').set(authHeader()).send({
    vendor_name: 'A', invoice_number: '1', invoice_date: '2026-11-01',
    lines: [{ item_id: ID, name: 'Rice', quantity: 1, unit_price: 10 }],
  });
  expect(res.status).toBe(201);
  expect(broadcast).toHaveBeenCalledWith(expect.anything(), { type: 'stock' });
});

test('a manual stock edit announces it', async () => {
  mockRequest.query.mockImplementation(function (sqlText) {
    const s = String(sqlText);
    let rs = [{ id: ID, business_id: ID, name: 'Rice', price: 10, stock_quantity: 5, variant_count: 0 }];
    if (/FROM stock_batches/.test(s) || /^\s*SELECT v\.id/.test(s) || /SELECT TOP 1 id, name FROM items/.test(s)) rs = [];
    return Promise.resolve({ recordset: rs, rowsAffected: [1] });
  });
  const res = await request(app).put(`/api/items/${ID}`).set(authHeader({ role: 'owner' }))
    .send({ stock_quantity: 3 });
  expect(res.status).toBe(200);
  expect(broadcast).toHaveBeenCalledWith(expect.anything(), { type: 'stock' });
});
