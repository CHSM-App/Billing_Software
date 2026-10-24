const request = require('supertest');
const jwt = require('jsonwebtoken');

const { publicTokenSecret } = require('../../src/auth');
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
// The storefront's 30/min per-IP ceiling is real and this suite exercises the
// same endpoints well past it; without this the later tests 429 on the limiter
// rather than reaching the code under test.
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
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
// gst_enabled rides along on the row because priceLines joins businesses to
// read it — an MRP price may only have its tax stripped while GST is on.
const catalogItem = {
  id: ITEM_ID,
  name: 'Chai',
  price: 100,
  tax_rate: 0,
  price_inclusive_tax: false,
  gst_enabled: true,
};

function storeAuth(over = {}) {
  const token = jwt.sign(
    { typ: 'store', phone: '9876543210', business_id: BUSINESS_ID, ...over },
    publicTokenSecret('store'),
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
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });
    expect(res.status).toBe(401);
  });

  test('401 for a token minted for another business', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth({ business_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' }))
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });
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
        name: 'Ramesh',
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
    // 105 gross at 5% GST -> 100 net stored on the line, because bill_items
    // holds net rates everywhere. The customer is still charged the full 105:
    // the tax is added back into the order total rather than dropped, which is
    // what used to make the shop collect 100 for a 105 item.
    const { inputsSeen } = wirePlaceOrder({
      item: { ...catalogItem, price: 105, tax_rate: 5, price_inclusive_tax: true },
    });

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });

    expect(res.status).toBe(201);
    expect(res.body.total).toBe(105);            // the MRP, not the net rate
    const lineInsert = inputsSeen.find((i) => i.line_total !== undefined);
    expect(lineInsert.unit_price).toBeCloseTo(100, 6);  // net, as bill_items stores it
  });

  test('with GST off an MRP price is charged as-is, not stripped', async () => {
    // A Rs.50 coffee carrying a leftover 10% rate from when GST was on. The
    // menu shows Rs.50, so the order must be Rs.50 — not 50/1.1 = 45.45.
    const { inputsSeen } = wirePlaceOrder({
      item: {
        ...catalogItem,
        price: 50,
        tax_rate: 10,
        price_inclusive_tax: true,
        gst_enabled: false,
      },
    });

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });

    expect(res.status).toBe(201);
    expect(res.body.total).toBe(50);
    const lineInsert = inputsSeen.find((i) => i.line_total !== undefined);
    expect(lineInsert.unit_price).toBe(50);
    // The leftover rate is not recorded either — the line carries no tax.
    expect(lineInsert.tax_rate).toBeNull();
  });

  test('the delivery charge comes from the shop, not the request', async () => {
    const { inputsSeen } = wirePlaceOrder();

    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        name: 'Ramesh',
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
      .send({ items: [{ item_id: ITEM_ID, quantity: 5 }], name: 'Ramesh', fulfilment: 'pickup' });

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
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });

    expect(res.status).toBe(400);
  });

  test('rejects an item quantity of zero', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 0 }], name: 'Ramesh', fulfilment: 'pickup' });
    expect(res.status).toBe(400);
  });
});

// ------------------------------------------------------------------
// POST /store/:token — fulfilment + payment rules
// ------------------------------------------------------------------
describe('POST /store/:token — fulfilment and payment', () => {
  test('an order with no name is rejected', async () => {
    // The name used to live in the OTP sheet, which a returning customer never
    // sees again for 4h — so real orders arrived with customer_name NULL and a
    // counter had only a phone number to call out.
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], fulfilment: 'pickup' });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('name_required');
  });

  test('a whitespace-only name is rejected', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: '   ', fulfilment: 'pickup' });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('name_required');
  });

  test('the name is trimmed and stored on the order', async () => {
    const { inputsSeen } = wirePlaceOrder();
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({
        items: [{ item_id: ITEM_ID, quantity: 1 }],
        name: '  Ramesh Kadam  ',
        fulfilment: 'pickup',
      });
    expect(res.status).toBe(201);
    const orderInsert = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(orderInsert.customer_name).toBe('Ramesh Kadam');
  });

  test('delivery without an address is rejected', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'delivery', address: '   ' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/address/i);
  });

  test('delivery is rejected when the shop does not deliver', async () => {
    mockRequest.recordset = [store({ store_delivery_enabled: false })];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'delivery', address: 'x' });
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
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });
    expect(res.status).toBe(201);
  });

  test('an unknown fulfilment value is rejected', async () => {
    mockRequest.recordset = [store()];
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'teleport' });
    expect(res.status).toBe(400);
  });

  test('payment_required with no transaction id is rejected', async () => {
    wirePlaceOrder({ storeRow: store({ store_payment_required: true }) });
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });
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
        name: 'Ramesh',
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
        name: 'Ramesh',
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
        name: 'Ramesh',
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
        name: 'Ramesh',
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
        name: 'Ramesh',
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
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });

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
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });

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

// ---------------------------------------------------------------------------
// The number on the menu must be the number the customer pays. Online orders
// used to total the NET sum with no tax term, so a tax-inclusive MRP collected
// less than it advertised and the accepted bill recorded tax_amount = 0.
// ---------------------------------------------------------------------------
describe('menu price === amount collected', () => {
  const order = async (item) => {
    const { inputsSeen } = wirePlaceOrder({ item });
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 1 }], name: 'Ramesh', fulfilment: 'pickup' });
    expect(res.status).toBe(201);
    return { res, inputsSeen };
  };

  test('MRP (inclusive) with GST on: menu Rs.105 -> collect Rs.105, tax split out', async () => {
    const { res, inputsSeen } = await order({
      ...catalogItem, price: 105, tax_rate: 5, price_inclusive_tax: true, gst_enabled: true,
    });
    expect(res.body.total).toBe(105);              // was 100 — the shop ate the GST
    const ins = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(ins.subtotal).toBe(100);                // net, as bill_items stores it
    expect(ins.total).toBe(105);
  });

  test('exclusive with GST on: net Rs.100 + 5% -> collect Rs.105', async () => {
    const { res } = await order({
      ...catalogItem, price: 100, tax_rate: 5, price_inclusive_tax: false, gst_enabled: true,
    });
    expect(res.body.total).toBe(105);
  });

  test('GST off: the leftover rate is ignored entirely', async () => {
    const { res } = await order({
      ...catalogItem, price: 50, tax_rate: 10, price_inclusive_tax: true, gst_enabled: false,
    });
    expect(res.body.total).toBe(50);
  });

  test('the menu quotes tax-in, so an exclusive price is not advertised bare', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [store()], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{
        ...catalogItem, price: 100, tax_rate: 5, price_inclusive_tax: false,
        gst_enabled: true, category: 'Drinks',
      }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app).get(`/store/${STORE_TOKEN}/menu`);
    expect(res.status).toBe(200);
    expect(res.body.items[0].price).toBe(105);
    // The shop's tax configuration is not the customer's business.
    expect(res.body.items[0].gst_enabled).toBeUndefined();
    expect(res.body.items[0].price_inclusive_tax).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// bill_items.line_total is GROSS everywhere (routes/bills.js builds it that
// way), and the recompute a staff edit triggers derives a bill's tax as
// SUM(line_total - quantity * unit_price). The public flows used to write a NET
// line_total, making that difference zero — so editing a bill built from a
// customer order silently erased its GST.
// ---------------------------------------------------------------------------
describe('customer lines store a GROSS line_total', () => {
  test('line_total carries the tax; unit_price stays net', async () => {
    const { inputsSeen } = wirePlaceOrder({
      item: { ...catalogItem, price: 105, tax_rate: 5, price_inclusive_tax: true, gst_enabled: true },
    });
    const res = await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 2 }], name: 'Ramesh', fulfilment: 'pickup' });

    expect(res.status).toBe(201);
    const line = inputsSeen.find((i) => i.line_total !== undefined);
    expect(line.unit_price).toBeCloseTo(100, 6);   // net
    expect(line.line_total).toBeCloseTo(210, 2);   // 2 x 105 gross
    // The difference is the tax a staff edit will re-derive — non-zero is the
    // whole point of this test.
    expect(line.line_total - line.quantity * line.unit_price).toBeCloseTo(10, 2);

    // And the order's own money still adds up: net subtotal + tax = gross.
    const ins = inputsSeen.find((i) => i.subtotal !== undefined);
    expect(ins.subtotal).toBe(200);
    expect(ins.total).toBe(210);
  });

  test('with GST off there is no tax, so gross equals net', async () => {
    const { inputsSeen } = wirePlaceOrder({
      item: { ...catalogItem, price: 50, tax_rate: 10, price_inclusive_tax: true, gst_enabled: false },
    });
    await request(app)
      .post(`/store/${STORE_TOKEN}`)
      .set(storeAuth())
      .send({ items: [{ item_id: ITEM_ID, quantity: 2 }], name: 'Ramesh', fulfilment: 'pickup' });

    const line = inputsSeen.find((i) => i.line_total !== undefined);
    expect(line.line_total).toBeCloseTo(100, 2);
    expect(line.line_total - line.quantity * line.unit_price).toBeCloseTo(0, 6);
  });
});
