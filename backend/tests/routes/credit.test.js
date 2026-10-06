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
  expect(sqlOf()).toMatch(/GROUP BY dbo\.canonical_phone\(b\.customer_phone\)/);
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
