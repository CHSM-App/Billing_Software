const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const BATCH = 'abababab-abab-abab-abab-abababababab';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

beforeEach(() => mockRequest.reset());

describe('GET /api/stock-batches/report', () => {
  test('owner only', async () => {
    const res = await request(app).get('/api/stock-batches/report').set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('works out each batch: revenue less cost of what sold and of what was written off', async () => {
    // Bought 10 at Rs. 50; 8 billed for Rs. 640 net; 1 written off.
    mockRequest.recordset = [{
      id: BATCH, batch_no: 'B-0001', unit_cost: 50, received_date: new Date('2026-11-01T00:00:00Z'),
      qty_received: 10, qty_sold: 8, qty_lost: 1, qty_remaining: 1,
      item_name: 'Rice', variant_label: '5 kg', vendor_name: 'Shree Traders', invoice_number: 'ST/1',
      billed_qty: 8, revenue: 640,
    }];
    const res = await request(app).get('/api/stock-batches/report').set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body[0]).toMatchObject({
      code: 'B-0001', item_name: 'Rice (5 kg)', received_date: '2026-11-01',
      revenue: 640, cost_of_sold: 400, lost_cost: 50, profit: 190, remaining: 1,
    });
    const sqlText = mockRequest.query.mock.calls[0][0];
    expect(sqlText).toMatch(/b\.status = 'finalized'/);
    expect(sqlText).toMatch(/sb\.qty_remaining > 0/);
  });

  test('settled lists the batches with nothing left', async () => {
    mockRequest.recordset = [];
    await request(app).get('/api/stock-batches/report?status=settled').set(authHeader());
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/sb\.qty_remaining <= 0/);
  });
});

describe('GET /api/stock-batches', () => {
  test('needs an item or size id', async () => {
    const res = await request(app).get('/api/stock-batches').set(authHeader());
    expect(res.status).toBe(400);
  });

  test("lists a size's open batches, oldest first", async () => {
    mockRequest.recordset = [{ id: BATCH, batch_no: 'L9', unit_cost: 60, qty_remaining: 4 }];
    const res = await request(app).get(`/api/stock-batches?variant_id=${ITEM_ID}`).set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([{ id: BATCH, code: 'L9', unit_cost: 60, remaining: 4 }]);
    const sqlText = mockRequest.query.mock.calls[0][0];
    expect(sqlText).toMatch(/variant_id = @id/);
    expect(sqlText).toMatch(/ORDER BY received_date, created_at/);
  });
});

test('report status=all lists every batch, open or settled', async () => {
  mockRequest.recordset = [];
  await request(app).get('/api/stock-batches/report?status=all').set(authHeader());
  const sqlText = mockRequest.query.mock.calls[0][0];
  expect(sqlText).not.toMatch(/sb\.qty_remaining [<>]/);
});

describe('GET /api/stock-batches/codes', () => {
  test('earlier batch nos., newest first, with whether any item is still open', async () => {
    mockRequest.recordset = [
      { batch_no: 'B-001', received_date: new Date('2026-11-16T00:00:00Z'), items: 5, open_items: 3 },
      { batch_no: 'B-0001', received_date: new Date('2026-11-10T00:00:00Z'), items: 2, open_items: 0 },
    ];
    const res = await request(app).get('/api/stock-batches/codes').set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([
      { code: 'B-001', received_date: '2026-11-16', items: 5, open: true },
      { code: 'B-0001', received_date: '2026-11-10', items: 2, open: false },
    ]);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/GROUP BY batch_no\s+ORDER BY MAX\(created_at\) DESC/);
  });

  test('owner only', async () => {
    const res = await request(app).get('/api/stock-batches/codes').set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });
});

describe('auth and errors', () => {
  test('every batch endpoint needs a login', async () => {
    for (const url of ['/api/stock-batches/report', '/api/stock-batches/codes', `/api/stock-batches?item_id=${ITEM_ID}`]) {
      expect((await request(app).get(url)).status).toBe(401);
    }
  });

  test('an id that is not a uuid is refused before the DB', async () => {
    const res = await request(app).get('/api/stock-batches?item_id=1%20OR%201=1').set(authHeader());
    expect(res.status).toBe(400);
    expect(mockRequest.query).not.toHaveBeenCalled();
  });

  test('a DB failure answers 500', async () => {
    mockRequest.query.mockRejectedValueOnce(new Error('db down'));
    const res = await request(app).get('/api/stock-batches/report').set(authHeader());
    expect(res.status).toBe(500);
  });
});

test("an item's batches are looked up by item, in the token's business", async () => {
  mockRequest.recordset = [];
  await request(app).get(`/api/stock-batches?item_id=${ITEM_ID}`).set(authHeader());
  expect(mockRequest.query.mock.calls[0][0]).toMatch(/AND item_id = @id/);
  expect(mockRequest.inputs).toMatchObject({ id: ITEM_ID, business_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' });
});

test('report: held stock shows, oversold remaining shows as 0, a plain item has no size', async () => {
  mockRequest.recordset = [{
    id: BATCH, batch_no: 'B-2', unit_cost: 10, received_date: '2026-11-05',
    qty_received: 5, qty_sold: 6, qty_lost: 0, qty_remaining: -1,
    item_name: 'Soap', variant_label: null, vendor_name: null, invoice_number: null,
    billed_qty: null, revenue: null, held_qty: 2,
  }];
  const res = await request(app).get('/api/stock-batches/report?status=all').set(authHeader());
  expect(res.body[0]).toMatchObject({
    item_name: 'Soap', vendor_name: null, received_date: '2026-11-05',
    sold: 0, held: 2, remaining: 0, revenue: 0, profit: 0,
  });
});
