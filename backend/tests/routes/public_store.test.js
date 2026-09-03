const request = require('supertest');
const jwt = require('jsonwebtoken');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
// The OTP path talks to an external WhatsApp API; the tests care about the order
// rules, not the delivery of a code.
jest.mock('../../src/whatsapp', () => ({
  sendOtp: jest.fn(() => Promise.resolve({ dev_otp: '123456' })),
  verifyOtp: jest.fn(() => Promise.resolve(true)),
  normalisePhone: (p) => String(p).replace(/\D/g, '').slice(-10),
}));

const app = require('../../src/server');

const STORE_TOKEN = 'a'.repeat(32);
const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const ORDER_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

// A shop with the store on: pickup + delivery, Rs.30 delivery, 20% advance.
const baseStore = {
  business_id: BUSINESS_ID,
  shop_name: 'Test Shop',
  address: '1 Main Road',
  phone: '9876543210',
  logo_url: null,
  store_enabled: true,
  store_delivery_enabled: true,
  store_delivery_charge: 30,
  store_payment_qr_url: '/uploads/store/x.jpg',
  store_upi_id: 'testshop@okhdfcbank',
  store_advance_percent: 20,
  store_payment_required: false,
};

const store = (over = {}) => ({ ...baseStore, ...over });

// The catalog row the server re-prices from. Note price 100 — every test that
// posts a cheaper price is asserting the client value is thrown away.
const catalogItem = {
  id: ITEM_ID,
  name: 'Chai',
  price: 100,
  tax_rate: 0,
  price_inclusive_tax: false,
};

function storeAuth(over = {}) {
  const token = jwt.sign(
    { typ: 'store', phone: '9876543210', business_id: BUSINESS_ID, ...over },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '4h' },
  );
  return { Authorization: `Bearer ${token}` };
}

/**
 * Wire the query mocks for a successful POST /store/:token.
 *
 * pool.request() order:  resolveStore -> pending-count
 * transaction.request(): priceLines(items) -> priceLines(which items are sized?)
 *                        -> order-number COUNT -> INSERT online_orders
 *                        -> INSERT line (per item)
 *
 * The sized-item lookup runs for every line posted without a variant_id, which
 * is all of them here; it returns nothing, i.e. "these items have no sizes".
 *
 * Returns the transaction query mock so a test can read back what was inserted.
 */
function wirePlaceOrder({ storeRow = store(), pending = 0, item = catalogItem } = {}) {
  mockRequest.query
    .mockResolvedValueOnce({ recordset: [storeRow], rowsAffected: [1] })
    .mockResolvedValueOnce({ recordset: [{ cnt: pending }], rowsAffected: [1] });

  const txQuery = jest.fn()
    .mockResolvedValueOnce({ recordset: [item], rowsAffected: [1] })
    .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
    .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] })
    .mockResolvedValueOnce({
      recordset: [{ id: ORDER_ID, order_number: 'ORD-0001' }],
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
});

// ------------------------------------------------------------------
// Store gate
// ------------------------------------------------------------------
describe('public store — availability', () => {
  test('menu 404s when the store is switched off', async () => {
    mockRequest.recordset = [store({ store_enabled: false })];
    const res = await request(app).get(`/store/${STORE_TOKEN}/menu`);
    expect(res.status).toBe(404);
  });

  test('menu 404s for an unknown token', async () => {
    mockRequest.recordset = [];
    const res = await request(app).get(`/store/${STORE_TOKEN}/menu`);
    expect(res.status).toBe(404);
  });

  test('menu returns the catalog and the store settings', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [store()], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ ...catalogItem, category: 'Drinks' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app).get(`/store/${STORE_TOKEN}/menu`);
    expect(res.status).toBe(200);
    expect(res.body.shop_name).toBe('Test Shop');
    // No pickup flag: pickup is unconditional, so there is nothing to report.
    expect(res.body.store).toEqual({
      delivery_enabled: true,
      delivery_charge: 30,
      payment_qr_url: '/uploads/store/x.jpg',
      // Public by design: a VPA is what a shop prints on its counter QR, and
      // checkout needs it to build the upi:// intent.
      upi_id: 'testshop@okhdfcbank',
      advance_percent: 20,
      payment_required: false,
    });
    expect(res.body.items).toHaveLength(1);
  });
});

// ------------------------------------------------------------------
// POST /store/:token — the OTP gate
// ------------------------------------------------------------------
describe('POST /store/:token — auth', () => {
  test('401 without a verified store token', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });
    expect(res.status).toBe(401);
  });

  test('401 for a token minted for another business', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth({ business_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' }))
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });
    expect(res.status).toBe(401);
  });
});

// ------------------------------------------------------------------
// POST /store/:token — pricing
// ------------------------------------------------------------------
describe('POST /store/:token — pricing is server-side', () => {
  test("a client-supplied price is ignored; the catalog price is stored", async () => {
    const { inputsSeen } = wirePlaceOrder();

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      // The browser claims Chai costs 1 rupee. The catalog says 100.
      .send({
        items: [{ item_id: ITEM_ID, quantity: 2, price: 1, unit_price: 1, line_total: 2 }],
        fulfilment: 'pickup',
      });

    expect(res.status).toBe(201);
    // 2 x 100 = 200, no delivery on pickup.
    expect(res.body.total).toBe(200);
    // 20% advance of 200.
    expect(res.body.amount_due).toBe(40);

    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(orderInsert.subtotal).toBe(200);
    expect(orderInsert.total).toBe(200);
    const lineInsert = inputsSeen.find((i) => i.line_total !== undefined);
    expect(lineInsert.unit_price).toBe(100);
    expect(lineInsert.line_total).toBe(200);
  });

  test('an MRP (tax-inclusive) price is stored back-calculated to the net rate', async () => {
    // 105 gross at 5% GST -> 100 net, so the subtotal the customer is shown does
    // not grow again when staff finalize the bill and tax is added on top.
    const { inputsSeen } = wirePlaceOrder({
      item: { ...catalogItem, price: 105, tax_rate: 5, price_inclusive_tax: true },
    });

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });

    expect(res.status).toBe(201);
    expect(res.body.total).toBe(100);
    const lineInsert = inputsSeen.find((i) => i.line_total !== undefined);
    expect(lineInsert.unit_price).toBeCloseTo(100, 6);
  });

  test('the delivery charge comes from the shop, not the request', async () => {
    const { inputsSeen } = wirePlaceOrder();

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        fulfilment: 'delivery',
        address: '12 Beach Road',
        delivery_charge: 0,          // ignored
      });

    expect(res.status).toBe(201);
    expect(res.body.total).toBe(130);  // 100 + the shop's 30
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(orderInsert.delivery_charge).toBe(30);
    expect(orderInsert.address).toBe('12 Beach Road');
  });

  test('a sized item posted with no size is refused, not billed as zero', async () => {
    // The regression this pins: liquor and Half/Full dishes carry a NULL base
    // price because they are only sold by size. Number(null) is 0, so a bare
    // item_id used to price the whole line at zero — a free bottle of whisky.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [store()], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] });

    const txQuery = jest.fn()
      // priceLines: items lookup — a sized item, so price is NULL
      .mockResolvedValueOnce({
        recordset: [{ ...catalogItem, price: null }], rowsAffected: [1] })
      // priceLines: "which of these have active variants?" — this one does
      .mockResolvedValueOnce({ recordset: [{ item_id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });
    mockTransaction.request.mockImplementation(() => ({
      inputs: {}, input() { return this; }, query: txQuery,
    }));

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 5 }], fulfilment: 'pickup' });

    expect(res.status).toBe(400);
    expect(res.body.code).toBe('size_required');
  });

  test('an item with no price and no sizes cannot be ordered', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [store()], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 0 }], rowsAffected: [1] });

    const txQuery = jest.fn()
      .mockResolvedValueOnce({
        recordset: [{ ...catalogItem, price: null }], rowsAffected: [1] })
      // No variants for it either — a half-edited catalog row.
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });
    mockTransaction.request.mockImplementation(() => ({
      inputs: {}, input() { return this; }, query: txQuery,
    }));

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });

    expect(res.status).toBe(400);
  });

  test('rejects an item quantity of zero', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 0 }], fulfilment: 'pickup' });
    expect(res.status).toBe(400);
  });
});

// ------------------------------------------------------------------
// POST /store/:token — fulfilment + payment rules
// ------------------------------------------------------------------
describe('POST /store/:token — fulfilment and payment', () => {
  test('delivery without an address is rejected', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'delivery', address: '   ' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/address/i);
  });

  test('delivery is rejected when the shop does not deliver', async () => {
    mockRequest.recordset = [store({ store_delivery_enabled: false })];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'delivery', address: 'x' });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('delivery_unavailable');
  });

  test('pickup is always accepted — it has no switch to be off', async () => {
    // The page hides the chooser for a pickup-only shop, but the browser is not
    // trusted: the server has to be the one that says pickup is always fine.
    wirePlaceOrder({ storeRow: store({ store_delivery_enabled: false }) });
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });
    expect(res.status).toBe(201);
  });

  test('an unknown fulfilment value is rejected', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'teleport' });
    expect(res.status).toBe(400);
  });

  test('payment_required with no transaction id is rejected', async () => {
    wirePlaceOrder({ storeRow: store({ store_payment_required: true }) });
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('payment_required');
  });

  test('payment_required is satisfied by a transaction id, recorded as claimed', async () => {
    const { inputsSeen } = wirePlaceOrder({
      storeRow: store({ store_payment_required: true }),
    });

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        fulfilment: 'pickup',
        payment_txn_id: 'UPI123456789',
      });

    expect(res.status).toBe(201);
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    // 'claimed', never 'verified' — nothing here can check a UPI reference.
    expect(orderInsert.payment_status).toBe('claimed');
    expect(orderInsert.payment_txn_id).toBe('UPI123456789');
    expect(orderInsert.paid_amount).toBe(20);   // 20% of 100
  });

  test('paying full records the whole total, not just the advance', async () => {
    const { inputsSeen } = wirePlaceOrder();

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        fulfilment: 'pickup',
        payment_choice: 'full',
        payment_txn_id: 'UPI-FULL-1',
      });

    expect(res.status).toBe(201);
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    // amount_due stays what the SHOP required (20% of 100) — the customer
    // choosing to pay more does not change the shop's condition.
    expect(orderInsert.amount_due).toBe(20);
    expect(orderInsert.paid_amount).toBe(100);
    expect(res.body.paid_amount).toBe(100);
  });

  test('choosing the advance records only the advance', async () => {
    const { inputsSeen } = wirePlaceOrder();

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        fulfilment: 'pickup',
        payment_choice: 'advance',
        payment_txn_id: 'UPI-ADV-1',
      });

    expect(res.status).toBe(201);
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(orderInsert.amount_due).toBe(20);
    expect(orderInsert.paid_amount).toBe(20);
  });

  test('a claimed amount in the request body is ignored', async () => {
    const { inputsSeen } = wirePlaceOrder();

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        fulfilment: 'pickup',
        payment_choice: 'advance',
        payment_txn_id: 'UPI-LIAR',
        // The browser insists it paid five thousand rupees.
        paid_amount: 5000,
        amount_due: 5000,
      });

    expect(res.status).toBe(201);
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(orderInsert.paid_amount).toBe(20);
    expect(orderInsert.amount_due).toBe(20);
  });

  test('pay-full is inert when the shop collects nothing up front', async () => {
    // advance 0% means the shop asked for nothing, so there is no online
    // payment to make full — the order must not record a phantom prepayment.
    const { inputsSeen } = wirePlaceOrder({
      storeRow: store({ store_advance_percent: 0 }),
    });

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        fulfilment: 'pickup',
        payment_choice: 'full',
        payment_txn_id: 'UPI-X',
      });

    expect(res.status).toBe(201);
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(orderInsert.amount_due).toBe(0);
    expect(orderInsert.paid_amount).toBe(0);
  });

  test('no advance asked for leaves the order unpaid', async () => {
    const { inputsSeen } = wirePlaceOrder({
      storeRow: store({ store_advance_percent: 0, store_payment_required: true }),
    });

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });

    // payment_required only bites when there is actually something to pay.
    expect(res.status).toBe(201);
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(orderInsert.payment_status).toBe('unpaid');
    expect(orderInsert.amount_due).toBe(0);
  });

  test('a phone with too many waiting orders is turned away', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [store()], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ cnt: 3 }], rowsAffected: [1] });

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });

    expect(res.status).toBe(429);
    expect(res.body.code).toBe('too_many_pending');
  });
});

// ------------------------------------------------------------------
// GET /store/:token/orders
// ------------------------------------------------------------------
describe('GET /store/:token/orders', () => {
  test('reports unverified without a store token', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app).get(`/store/${STORE_TOKEN}/orders`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ verified: false, orders: [] });
  });

  test('returns the caller phone\'s orders with their status', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [store()], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [{ id: ORDER_ID, order_number: 'ORD-0001', status: 'rejected',
                      reject_reason: 'Closed for the day', total: 100 }],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({
        recordset: [{ order_id: ORDER_ID, item_name: 'Chai', quantity: 1, line_total: 100 }],
        rowsAffected: [1],
      });

    const res = await request(app)
      .get(`/store/${STORE_TOKEN}/orders`)
      .set(storeAuth());

    expect(res.status).toBe(200);
    expect(res.body.verified).toBe(true);
    expect(res.body.orders[0].reject_reason).toBe('Closed for the day');
    expect(res.body.orders[0].items).toHaveLength(1);
    // Scoped to the token's phone, not to anything the caller could supply.
    expect(mockRequest.inputs.phone).toBe('9876543210');
  });
});
