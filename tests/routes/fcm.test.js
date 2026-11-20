const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const { lowStockText } = require('../../src/fcm');

beforeEach(() => {
  jest.clearAllMocks();
  mockRequest.reset();
});

describe('notification prefs', () => {
  test('GET returns the caller\'s switches as booleans', async () => {
    mockRequest.recordset = [{ notify_low_stock: true, notify_online_orders: false }];
    const res = await request(app).get('/api/fcm/prefs').set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ notify_low_stock: true, notify_online_orders: false });
  });

  test('PUT updates only the sent key, on the caller\'s own row', async () => {
    const res = await request(app)
      .put('/api/fcm/prefs')
      .set(authHeader({ role: 'cashier' }))
      .send({ notify_online_orders: false, role: 'owner' });
    expect(res.status).toBe(200);
    const q = mockRequest.query.mock.calls[0][0];
    expect(q).toMatch(/SET notify_online_orders = @notify_online_orders WHERE id = @id/);
    expect(mockRequest.inputs.id).toBe('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(mockRequest.inputs.notify_online_orders).toBe(0);
  });

  test('PUT rejects non-boolean and empty bodies', async () => {
    let res = await request(app).put('/api/fcm/prefs').set(authHeader())
      .send({ notify_low_stock: 'no' });
    expect(res.status).toBe(400);
    res = await request(app).put('/api/fcm/prefs').set(authHeader()).send({});
    expect(res.status).toBe(400);
    expect(mockRequest.query).not.toHaveBeenCalled();
  });
});

describe('lowStockText', () => {
  test('title carries the business-wide count, body caps at 3 names', () => {
    const items = ['A', 'B', 'C', 'D'].map((name) => ({ name, remaining: 1 }));
    expect(lowStockText(items, 9)).toEqual({
      title: 'Low stock — 9 items',
      body: 'A (1 left), B (1 left), C (1 left) …and 1 more',
    });
    expect(lowStockText([{ name: 'Sugar', remaining: 4 }], 1))
      .toEqual({ title: 'Low stock', body: 'Sugar (4 left)' });
  });
});
