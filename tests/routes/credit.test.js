// Credit groups and looks up customers by their CANONICAL number: the billing
// app saves 9876543210, the online store 919876543210 — one person, one debtor.
const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

beforeEach(() => mockRequest.reset());
const sqlOf = (call = 0) => mockRequest.query.mock.calls[call][0];

test('the debtor list groups by canonical phone', async () => {
  mockRequest.recordset = [];
  const res = await request(app).get('/api/credit/customers').set(authHeader());
  expect(res.status).toBe(200);
  expect(sqlOf()).toMatch(/dbo\.canonical_phone\(b\.customer_phone\) AS customer_phone/);
  expect(sqlOf()).toMatch(/GROUP BY x\.customer_phone/);
  // SQL Server refuses SUM() over an expression holding a subquery (error
  // 130) — that broke this list and hid the Credit tab. The due is computed
  // per bill inside, and only the plain column is summed.
  expect(sqlOf()).toMatch(/SUM\(x\.due\)/);
  expect(sqlOf()).not.toMatch(/SUM\(\(/);
});

test.each(['9876543210', '919876543210', '+91 98765 43210'])(
  'summary for %s finds the bills in every stored format', async (typed) => {
    mockRequest.recordset = [{ id: 'b1', due: 100 }, { id: 'b2', due: 50 }];
    const res = await request(app)
      .get(`/api/credit/customers/${encodeURIComponent(typed)}/summary`)
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ outstanding: 150, unpaid_count: 2 });
    expect(mockRequest.inputs.phone).toBe('9876543210');
    expect(sqlOf()).toContain("b.customer_phone IN (@phone, '91' + @phone");
  });

test('a customer’s unpaid bills match every stored format', async () => {
  mockRequest.recordset = [];
  const res = await request(app)
    .get('/api/credit/customers/919876543210/bills')
    .set(authHeader());
  expect(res.status).toBe(200);
  expect(mockRequest.inputs.phone).toBe('9876543210');
  expect(sqlOf()).toContain("b.customer_phone IN (@phone, '91' + @phone");
});

// ── Payment Receipt for a Credit-tab payment (migration 052) ────────────────

const SETTLEMENT_ID = '11111111-2222-3333-4444-555555555555';

test('one WhatsApp for a whole payment lists every bill and the total', async () => {
  mockRequest.recordset = [
    { receipt_token: 'Ab3xK9Ab3xK9Ab3x', customer_phone: '9876543210', mode: 'cash', total: 2920,
      shop_name: 'Hotel Ramtirth', whatsapp_mode: 'deeplink', bill_number: 'INV-0097' },
    { receipt_token: 'Ab3xK9Ab3xK9Ab3x', customer_phone: '9876543210', mode: 'cash', total: 2920,
      shop_name: 'Hotel Ramtirth', whatsapp_mode: 'deeplink', bill_number: 'INV-0098' },
  ];
  const res = await request(app)
    .post(`/api/credit/settlements/${SETTLEMENT_ID}/whatsapp`)
    .set(authHeader());
  expect(res.status).toBe(200);
  expect(res.body).toMatchObject({ mode: 'deeplink', phone: '919876543210' });
  expect(res.body.message).toContain('Bills: #0097, #0098');
  expect(res.body.message).toContain('Total received: Rs.2920.00 (CASH)');
  expect(res.body.receipt_url).toMatch(/\/receipt\/s\/Ab3xK9Ab3xK9Ab3x$/);
  // Scoped to the caller's business — another shop's settlement is a 404.
  expect(sqlOf()).toContain('s.business_id = @business_id');
});

test('settlement WhatsApp: unknown id is a 404, a bad id a 400', async () => {
  mockRequest.recordset = [];
  const missing = await request(app)
    .post(`/api/credit/settlements/${SETTLEMENT_ID}/whatsapp`).set(authHeader());
  expect(missing.status).toBe(404);
  const bad = await request(app)
    .post('/api/credit/settlements/not-a-uuid/whatsapp').set(authHeader());
  expect(bad.status).toBe(400);
});

test('the public Payment Receipt page lists the settled invoices', async () => {
  mockRequest.query
    .mockResolvedValueOnce({ recordset: [{
      id: SETTLEMENT_ID, customer_name: 'Ramesh', customer_phone: '9876543210', mode: 'cash',
      total: 1970, created_at: new Date('2026-10-12T11:00:00Z'), shop_name: 'Hotel Ramtirth',
    }] })
    .mockResolvedValueOnce({ recordset: [
      { bill_number: 'INV-0099', created_at: new Date('2026-10-02T10:00:00Z'), bill_total: 1420, paid: 1420, due: 0 },
      { bill_number: 'INV-0097', created_at: new Date('2026-09-21T10:00:00Z'), bill_total: 800, paid: 550, due: 250 },
    ] });
  const res = await request(app).get('/receipt/s/Ab3xK9Ab3xK9Ab3x');
  expect(res.status).toBe(200);
  expect(res.text).toContain('Settled Invoices');
  expect(res.text).toContain('0099');
  expect(res.text).toContain('Bal due &#8377;250.00');
  expect(res.text).toContain('TOTAL RECEIVED');
  expect(res.text).toContain('&#8377;1970.00');
  // Balance is as of that payment, not today's.
  expect(sqlOf(1)).toContain('p2.created_at <= pay.created_at');
});

test('the public Payment Receipt page 404s an unknown token', async () => {
  mockRequest.recordset = [];
  const res = await request(app).get('/receipt/s/nope');
  expect(res.status).toBe(404);
});
