const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
// Fire-and-forget side effects of POST /api/bills — not under test here.
jest.mock('../../src/customers', () => ({
  ...jest.requireActual('../../src/customers'),
  upsertCustomer: jest.fn(() => Promise.resolve()),
}));
jest.mock('../../src/audit', () => ({ logBillCreated: jest.fn() }));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const Q_ID    = '22222222-2222-4222-8222-222222222222';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const BILL_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

const snapshot = { items: [{ item_id: ITEM_ID, item_name: 'Rice', quantity: 2 }] };
const row = {
  id: Q_ID, quotation_number: 'QT-0001', customer_name: 'Asha', customer_phone: null,
  total: '100.00', created_at: '2026-10-27T10:00:00Z', snapshot: JSON.stringify(snapshot),
};

/// Transaction queries answered by their SQL; records each with its inputs.
function txDb(answer) {
  const txSql = [];
  mockTransaction.request.mockImplementation(() => {
    const r = {
      inputs: {},
      input(k, _t, v) { r.inputs[k] = v; return r; },
      query: jest.fn((sqlText) => {
        txSql.push({ sqlText, inputs: r.inputs });
        return Promise.resolve(answer(sqlText));
      }),
    };
    return r;
  });
  return txSql;
}

beforeEach(() => {
  mockRequest.reset();
  jest.clearAllMocks();
});

describe('POST /api/quotations', () => {
  const post = (body, role = 'owner') =>
    request(app).post('/api/quotations').set(authHeader({ role })).send(body);

  test('numbers the first quotation QT-0001 and stores the snapshot', async () => {
    const txSql = txDb((s) => /COUNT\(\*\)/.test(s)
      ? { recordset: [{ cnt: 0 }] }
      : { recordset: [row], rowsAffected: [1] });
    const res = await post({ customer_name: ' Asha ', total: 100, snapshot });
    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({ quotation_number: 'QT-0001', total: 100, snapshot });
    const insert = txSql.find((c) => /INSERT INTO quotations/.test(c.sqlText));
    expect(insert.inputs).toMatchObject({ number: 'QT-0001', customer_name: 'Asha', total: 100 });
    expect(JSON.parse(insert.inputs.snapshot)).toEqual(snapshot);
    expect(mockTransaction.commit).toHaveBeenCalled();
  });

  test('cashier may quote', async () => {
    txDb((s) => /COUNT/.test(s) ? { recordset: [{ cnt: 4 }] } : { recordset: [row] });
    expect((await post({ total: 1, snapshot }, 'cashier')).status).toBe(201);
  });

  test.each(['server', 'kitchen'])('%s gets 403', async (role) => {
    expect((await post({ total: 1, snapshot }, role)).status).toBe(403);
  });

  test.each([
    ['no total', { snapshot }],
    ['a negative total', { total: -1, snapshot }],
    ['no snapshot', { total: 1 }],
    ['a snapshot without items', { total: 1, snapshot: { items: [] } }],
  ])('rejects %s with 400', async (_n, body) => {
    expect((await post(body)).status).toBe(400);
  });
});

describe('GET /api/quotations', () => {
  test('lists only open quotations, snapshot parsed', async () => {
    mockRequest.recordset = [row];
    const res = await request(app).get('/api/quotations').set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body[0]).toMatchObject({ id: Q_ID, total: 100, snapshot });
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/status = 'open'/);
  });
});

describe('PUT / DELETE /api/quotations/:id', () => {
  test('a converted (or missing) quotation cannot be edited: 409', async () => {
    mockRequest.recordset = [];
    const res = await request(app).put(`/api/quotations/${Q_ID}`)
      .set(authHeader()).send({ total: 5, snapshot });
    expect(res.status).toBe(409);
  });

  test('deletes an open quotation', async () => {
    mockRequest.rowsAffected = [1];
    const res = await request(app).delete(`/api/quotations/${Q_ID}`).set(authHeader());
    expect(res.status).toBe(200);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/status = 'open'/);
  });
});

describe('POST /api/bills with quotation_id', () => {
  /// The bill-create transaction, with the convert UPDATE answering [converted].
  function billDb(converted) {
    return txDb((s) => {
      if (/UPDATE quotations/.test(s)) return { recordset: [], rowsAffected: [converted] };
      if (/AS cnt/.test(s)) return { recordset: [{ cnt: 0, bill_prefix: 'INV' }] };
      if (/inventory_enabled/.test(s)) return { recordset: [{ inventory_enabled: false }] };
      if (/FROM items/.test(s)) return { recordset: [{ id: ITEM_ID, name: 'Rice', price: 50, tax_rate: null }] };
      if (/INSERT INTO bills/.test(s)) return { recordset: [{ id: BILL_ID }], rowsAffected: [1] };
      return { recordset: [], rowsAffected: [1] };
    });
  }
  const postBill = (extra) => request(app).post('/api/bills').set(authHeader()).send({
    items: [{ item_id: ITEM_ID, quantity: 2 }], payment_mode: 'cash', ...extra,
  });

  test('marks the quotation converted inside the bill transaction', async () => {
    const txSql = billDb(1);
    mockRequest.query.mockImplementation(() => Promise.resolve({
      recordset: [{ id: BILL_ID, bill_number: 'INV-0001', subtotal: 100, tax_amount: 0,
        total: 100, payment_mode: 'cash', status: 'finalized', created_at: '2026-10-27T10:00:00Z' }],
      rowsAffected: [1],
    }));
    const res = await postBill({ quotation_id: Q_ID });
    expect(res.status).toBe(201);
    const conv = txSql.find((c) => /UPDATE quotations/.test(c.sqlText));
    expect(conv.inputs).toMatchObject({ quotation_id: Q_ID, bill_id: BILL_ID });
    expect(conv.sqlText).toMatch(/status = 'open'/);
    expect(mockTransaction.commit).toHaveBeenCalled();
  });

  test('an already-converted quotation rolls the bill back with 409', async () => {
    billDb(0);
    mockRequest.query.mockImplementation(() => Promise.resolve({ recordset: [], rowsAffected: [0] }));
    const res = await postBill({ quotation_id: Q_ID });
    expect(res.status).toBe(409);
    expect(mockTransaction.rollback).toHaveBeenCalled();
    expect(mockTransaction.commit).not.toHaveBeenCalled();
  });

  test('a malformed quotation_id is a 400', async () => {
    expect((await postBill({ quotation_id: 'nope' })).status).toBe(400);
  });
});
