const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const d = (s) => new Date(`${s}T00:00:00Z`);

beforeEach(() => mockRequest.reset());

describe('stock reports', () => {
  test('owner only', async () => {
    const res = await request(app)
      .get('/api/reports/stock-summary?from=2026-11-01&to=2026-11-02')
      .set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  // Opening 100; day 1 sells 10 (closes 90); day 2 a purchase of 50 arrives
  // mid-day and is dated that day: opens 90, closes 140.
  test('stock-daily chains each closing into the next opening', async () => {
    mockRequest.recordset = [
      { d: d('2026-11-01'), t: 'opening', qty: '100' },
      { d: d('2026-11-01'), t: 'sale', qty: '-10' },
      { d: d('2026-11-02'), t: 'purchase', qty: '50' },
    ];
    const res = await request(app)
      .get('/api/reports/stock-daily?from=2026-11-01&to=2026-11-03&item_id=11111111-1111-1111-1111-111111111111')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body.days.map((x) => [x.opening, x.purchased, x.sold, x.closing])).toEqual([
      [100, 0, 10, 90],
      [90, 50, 0, 140],
      [140, 0, 0, 140],
    ]);
  });

  test('stock-daily needs exactly one target', async () => {
    const res = await request(app)
      .get('/api/reports/stock-daily?from=2026-11-01&to=2026-11-03')
      .set(authHeader());
    expect(res.status).toBe(400);
  });

  // Beer bought at 70 and sold at 100: 10 sold = 300 profit. A line with no
  // cost is reported, not guessed.
  test('item-profit = (sell - buy) x qty, flags lines without a cost', async () => {
    mockRequest.recordset = [
      { name: 'Beer', item_id: 'a', variant_id: null, qty: '10', sales: '1000',
        cost: '700', costed_sales: '1000', qty_no_cost: '0' },
      { name: 'Wine', item_id: 'b', variant_id: null, qty: '2', sales: '400',
        cost: null, costed_sales: null, qty_no_cost: '2' },
    ];
    const res = await request(app)
      .get('/api/reports/item-profit?from=2026-11-01&to=2026-11-30')
      .set(authHeader());
    expect(res.status).toBe(200);
    const beer = res.body.rows.find((r) => r.name === 'Beer');
    expect(beer.profit).toBe(300);
    expect(beer.avg_cost).toBe(70);
    expect(beer.avg_sell).toBe(100);
    expect(res.body.totals.profit).toBe(300);
    expect(res.body.totals.qty_no_cost).toBe(2);
  });
});
