const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const ORDER_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const BILL_ID = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

const pendingOrder = {
  id: ORDER_ID,
  order_number: 'ORD-0001',
  customer_name: 'Ramesh',
  customer_phone: '9876543210',
  fulfilment: 'delivery',
  address: '12 Beach Road',
  note: null,
  subtotal: 200,
  delivery_charge: 30,
  total: 230,
  amount_due: 46,
  paid_amount: 46,
  payment_txn_id: 'UPI123456789',
  payment_status: 'claimed',
  status: 'pending',
};

const orderLine = {
  item_id: ITEM_ID,
  variant_id: null,
  item_name: 'Chai',
  quantity: 2,
  unit_price: 100,
  tax_rate: 0,
  line_total: 200,
};

/**
 * Wire the transaction queries for POST /:id/accept, in route order:
 *   SELECT online_orders (UPDLOCK) -> SELECT online_order_items
 *   -> SELECT bill count + prefix  -> INSERT bills -> INSERT bill_items (xN)
 *   -> UPDATE online_orders
 *
 * Returns the captured `.input()` values per request so a test can assert what
 * was actually written.
 */
function wireAccept({ order = pendingOrder, lines = [orderLine] } = {}) {
  const txQuery = jest.fn()
    .mockResolvedValueOnce({ recordset: [order], rowsAffected: [1] })
    .mockResolvedValueOnce({ recordset: lines, rowsAffected: [1] })
    .mockResolvedValueOnce({ recordset: [{ cnt: 4, bill_prefix: 'INV' }], rowsAffected: [1] })
    .mockResolvedValueOnce({
      recordset: [{ id: BILL_ID, bill_number: 'INV-0005' }],
      rowsAffected: [1],
    })
    .mockResolvedValue({ recordset: [], rowsAffected: [1] });

  const inputsSeen = [];
  mockTransaction.request.mockImplementation(() => {
    const captured = {};
    inputsSeen.push(captured);
    return {
      inputs: captured,
      input(name, _type, value) { captured[name] = value; return this; },
      query: txQuery,
    };
  });
  return { txQuery, inputsSeen };
}

beforeEach(() => {
  mockRequest.reset();
  mockTransaction.request.mockReset();
  mockTransaction.request.mockImplementation(() => ({ ...mockRequest }));
  mockTransaction.begin.mockClear();
  mockTransaction.commit.mockClear();
  mockTransaction.rollback.mockClear();
});

// ------------------------------------------------------------------
// Auth
// ------------------------------------------------------------------
describe('online orders — auth guard', () => {
  test('GET returns 401 without a token', async () => {
    const res = await request(app).get('/api/online-orders');
    expect(res.status).toBe(401);
  });

  test('a server cannot accept an order', async () => {
    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader({ role: 'server' }));
    expect(res.status).toBe(403);
  });

  test('a kitchen user cannot reject an order', async () => {
    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/reject`)
      .set(authHeader({ role: 'kitchen' }));
    expect(res.status).toBe(403);
  });
});

// ------------------------------------------------------------------
// GET /api/online-orders
// ------------------------------------------------------------------
describe('GET /api/online-orders', () => {
  test('returns orders with their lines attached', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...pendingOrder }], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [{ order_id: ORDER_ID, ...orderLine }],
        rowsAffected: [1],
      });

    const res = await request(app).get('/api/online-orders').set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body[0].order_number).toBe('ORD-0001');
    expect(res.body[0].items).toHaveLength(1);
  });

  test('returns an empty list without a second query', async () => {
    mockRequest.recordset = [];
    const res = await request(app).get('/api/online-orders').set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
    expect(mockRequest.query).toHaveBeenCalledTimes(1);
  });
});

// ------------------------------------------------------------------
// POST /api/online-orders/:id/accept
// ------------------------------------------------------------------
describe('POST /api/online-orders/:id/accept', () => {
  test('creates a table-less draft bill carrying the delivery charge', async () => {
    const { inputsSeen } = wireAccept();

    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({});

    expect(res.status).toBe(200);
    expect(res.body.bill_number).toBe('INV-0005');

    const billInsert = inputsSeen.find((i) => i.bill_number !== undefined);
    expect(billInsert.subtotal).toBe(200);
    expect(billInsert.charges_amount).toBe(30);
    // total = subtotal + charges. Nothing is taxed here; GST is applied when
    // staff finalize the draft.
    expect(billInsert.total).toBe(230);
    expect(JSON.parse(billInsert.additional_charges)).toEqual([
      { name: 'Delivery', amount: 30 },
    ]);
    expect(billInsert.customer_phone).toBe('9876543210');
  });

  test('copies each order line onto the bill as a customer-sourced item', async () => {
    const { inputsSeen } = wireAccept();

    await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({});

    const lineInsert = inputsSeen.find((i) => i.item_name === 'Chai');
    expect(lineInsert.quantity).toBe(2);
    expect(lineInsert.unit_price).toBe(100);
    expect(lineInsert.line_total).toBe(200);
    expect(lineInsert.diner_phone).toBe('9876543210');
  });

  test('a pickup order carries no charge and no charges JSON', async () => {
    const { inputsSeen } = wireAccept({
      order: { ...pendingOrder, fulfilment: 'pickup', address: null, delivery_charge: 0, total: 200 },
    });

    await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({});

    const billInsert = inputsSeen.find((i) => i.bill_number !== undefined);
    expect(billInsert.charges_amount).toBe(0);
    expect(billInsert.additional_charges).toBeNull();
    expect(billInsert.total).toBe(200);
  });

  test('payment_verified marks a claimed payment as verified', async () => {
    const { inputsSeen } = wireAccept();

    await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({ payment_verified: true });

    const update = inputsSeen.find((i) => i.payment_status !== undefined);
    expect(update.payment_status).toBe('verified');
  });

  test('without payment_verified the claim stays a claim', async () => {
    const { inputsSeen } = wireAccept();

    await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({});

    const update = inputsSeen.find((i) => i.payment_status !== undefined);
    expect(update.payment_status).toBe('claimed');
  });

  test('accepting an already-accepted order is a 409 and writes no bill', async () => {
    const { txQuery } = wireAccept({ order: { ...pendingOrder, status: 'accepted' } });

    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({});

    expect(res.status).toBe(409);
    expect(res.body.code).toBe('already_decided');
    // Only the order lookup ran — no line fetch, no INSERT.
    expect(txQuery).toHaveBeenCalledTimes(1);
    expect(mockTransaction.rollback).toHaveBeenCalled();
  });

  test('another business\'s order is a 404', async () => {
    // The route scopes the lookup by business_id, so a foreign id finds nothing.
    wireAccept({ order: undefined });
    mockTransaction.request.mockImplementation(() => ({
      inputs: {},
      input: jest.fn().mockReturnThis(),
      query: jest.fn().mockResolvedValue({ recordset: [], rowsAffected: [0] }),
    }));

    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({});

    expect(res.status).toBe(404);
  });

  test('an order with no lines is refused rather than billed as empty', async () => {
    wireAccept({ lines: [] });

    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/accept`)
      .set(authHeader())
      .send({});

    expect(res.status).toBe(400);
  });
});

// ------------------------------------------------------------------
// POST /api/online-orders/:id/reject
// ------------------------------------------------------------------
describe('POST /api/online-orders/:id/reject', () => {
  test('rejects with a reason and creates no bill', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [pendingOrder], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/reject`)
      .set(authHeader())
      .send({ reason: 'Closed for the day' });

    expect(res.status).toBe(200);
    expect(res.body.order_number).toBe('ORD-0001');
    expect(mockRequest.inputs.reason).toBe('Closed for the day');
    // No transaction was opened at all — nothing is written to bills.
    expect(mockTransaction.begin).not.toHaveBeenCalled();
  });

  test('404 when the order is not this business\'s', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/reject`)
      .set(authHeader())
      .send({ reason: 'x' });
    expect(res.status).toBe(404);
  });

  test('409 when it was already decided', async () => {
    mockRequest.recordset = [{ ...pendingOrder, status: 'accepted' }];
    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/reject`)
      .set(authHeader())
      .send({});
    expect(res.status).toBe(409);
  });

  test('409 when a concurrent accept won the race', async () => {
    // The row read as pending, but the guarded UPDATE matched nothing because
    // another device accepted it in between.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [pendingOrder], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .post(`/api/online-orders/${ORDER_ID}/reject`)
      .set(authHeader())
      .send({});

    expect(res.status).toBe(409);
  });
});
