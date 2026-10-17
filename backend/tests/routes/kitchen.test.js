const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const ITEM_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

beforeEach(() => mockRequest.reset());

const put = (role, kitchen_status) => request(app)
  .put(`/api/kitchen/items/${ITEM_ID}`)
  .set(authHeader({ role }))
  .send({ kitchen_status });

describe('PUT /api/kitchen/items/:id — who may move a dish where', () => {
  test('a captain can mark a ready dish delivered', async () => {
    mockRequest.recordset = [{ id: ITEM_ID, kitchen_status: 'delivered' }];
    const res = await put('server', 'delivered');
    expect(res.status).toBe(200);
    // Only from ready/delivered — a pending dish cannot be delivered.
    expect(mockRequest.inputs.from0).toBe('ready');
    expect(mockRequest.inputs.from1).toBe('delivered');
  });

  test('a captain cannot mark a dish ready-from-pending or pending', async () => {
    expect((await put('server', 'pending')).status).toBe(403);
    expect((await put('owner', 'pending')).status).toBe(403);
  });

  test('a captain delivering a not-yet-ready dish matches no row → 404', async () => {
    mockRequest.rowsAffected = [0];
    expect((await put('cashier', 'delivered')).status).toBe(404);
  });

  test('the kitchen cannot mark a dish delivered', async () => {
    expect((await put('kitchen', 'delivered')).status).toBe(403);
  });

  test('the kitchen marks ready only from pending/ready — never undoes a delivery', async () => {
    const res = await put('kitchen', 'ready');
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.from0).toBe('pending');
    expect(mockRequest.inputs.from1).toBe('ready');
    expect(mockRequest.inputs.from2).toBeUndefined();
  });

  // An older kitchen app sees a delivered dish as 'ready' (see GET below); if
  // the chef un-ticks it, that is a deliberate "cook it again" and must work.
  test('the kitchen may send any dish, delivered included, back to pending', async () => {
    const res = await put('kitchen', 'pending');
    expect(res.status).toBe(200);
    expect([mockRequest.inputs.from0, mockRequest.inputs.from1, mockRequest.inputs.from2])
      .toEqual(['pending', 'ready', 'delivered']);
  });

  test('rejects an unknown status', async () => {
    expect((await put('kitchen', 'burnt')).status).toBe(400);
  });
});

describe('PUT /api/kitchen/items/:id — retail tick', () => {
  // First query is the business-type lookup; the rest fall back to defaults.
  const retailPut = (role, status) => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [{ business_type: 'retail' }] });
    return put(role, status);
  };

  test('staff tick an item straight from pending (no kitchen step)', async () => {
    const res = await retailPut('cashier', 'delivered');
    expect(res.status).toBe(200);
    expect([mockRequest.inputs.from0, mockRequest.inputs.from1]).toEqual(['pending', 'delivered']);
  });

  test('and untick it back to pending', async () => {
    const res = await retailPut('owner', 'pending');
    expect(res.status).toBe(200);
    expect([mockRequest.inputs.from0, mockRequest.inputs.from1]).toEqual(['pending', 'delivered']);
  });

  test('there is no "ready" step in retail', async () => {
    expect((await retailPut('cashier', 'ready')).status).toBe(403);
  });

  test('a restaurant captain still cannot deliver from pending', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [{ business_type: 'restaurant_with_tables' }] });
    const res = await put('server', 'delivered');
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.from0).toBe('ready');
  });
});

describe('GET /api/kitchen/orders', () => {
  const ordersWith = (statuses, query = '?statuses=delivered') => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: 'b1', bill_number: 'INV-1' }] })
      .mockResolvedValueOnce({
        recordset: statuses.map((s, i) => ({ id: `i${i}`, bill_id: 'b1', kitchen_status: s })),
      });
    return request(app).get(`/api/kitchen/orders${query}`).set(authHeader());
  };

  test('all_delivered: completed (current app) only once every dish is served', async () => {
    expect((await ordersWith(['delivered', 'delivered'])).body[0].all_delivered).toBe(true);
    expect((await ordersWith(['ready', 'delivered'])).body[0].all_delivered).toBe(false);
  });

  test('all_ready keeps its original meaning: every dish cooked', async () => {
    expect((await ordersWith(['ready', 'delivered'])).body[0].all_ready).toBe(true);
    expect((await ordersWith(['ready', 'ready'])).body[0].all_ready).toBe(true);
    expect((await ordersWith(['ready', 'pending'])).body[0].all_ready).toBe(false);
  });

  test('the current app (statuses=delivered) sees real statuses', async () => {
    const res = await ordersWith(['ready', 'delivered']);
    expect(res.body[0].items.map((i) => i.kitchen_status)).toEqual(['ready', 'delivered']);
  });

  // Released apps (≤ 1.1.12) know only pending/ready: a delivered dish must
  // reach them as 'ready', or their kitchen display shows it as un-cooked.
  test('an older app (no statuses param) sees delivered dishes as ready', async () => {
    const res = await ordersWith(['pending', 'delivered'], '');
    expect(res.body[0].items.map((i) => i.kitchen_status)).toEqual(['pending', 'ready']);
    expect(res.body[0].all_ready).toBe(false);
  });
});
