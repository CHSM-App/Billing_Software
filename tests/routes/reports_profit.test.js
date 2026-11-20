const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

/** Answer each of /summary's parallel queries by what it selects. */
function db(costs, returns = []) {
  mockRequest.query.mockImplementation((sqlText) => {
    const s = String(sqlText);
    let rs = [];
    if (/FROM sales_returns sr/.test(s)) rs = returns;
    else if (/AS net_sales/.test(s)) rs = [costs];
    else if (/AS bill_count/.test(s)) {
      rs = [{ bill_count: 2, total_revenue: 1180, total_discount: 0, total_round_off: 0, total_tax: 180,
        cash: 1180, upi: 0, card: 0, credit: 0, other: 0 }];
    } else if (/AS total_expenses/.test(s)) rs = [{ total_expenses: 100 }];
    else if (/AS collected/.test(s)) rs = [{ collected: 0 }];
    return Promise.resolve({ recordset: rs, rowsAffected: [rs.length] });
  });
}

const summary = () => request(app).get('/api/reports/summary?from=2026-11-01&to=2026-11-30').set(authHeader());

describe('GET /api/reports/summary — profit from stock batches', () => {
  test('gross profit covers only costed sales; the rest is reported apart', async () => {
    // Rs. 1000 net sales: Rs. 960 of it from batches that cost Rs. 620.
    db({ net_sales: 1000, cost_of_goods: 620, costed_revenue: 960 });
    const res = await summary();
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      costed_revenue: 960, cost_of_goods: 620, gross_profit: 340, uncosted_revenue: 40,
      // The old figure is untouched for older apps and exports.
      net_profit: 1080,
    });
  });

  test('a shop without batches reports every sale as uncosted', async () => {
    db({ net_sales: 1000, cost_of_goods: 0, costed_revenue: 0 });
    const res = await summary();
    expect(res.body).toMatchObject({ gross_profit: 0, uncosted_revenue: 1000 });
  });

  test('cost is read only for finalized bills in the period', async () => {
    db({ net_sales: 0, cost_of_goods: 0, costed_revenue: 0 });
    await summary();
    const q = mockRequest.query.mock.calls.map((c) => c[0]).find((s) => /AS net_sales/.test(s));
    expect(q).toMatch(/b\.status = 'finalized'/);
    expect(q).toMatch(/b\.finalized_at >= @from_dt AND b\.finalized_at < @to_dt/);
  });
});

test('profit reads each line\'s cost snapshot, with round-off spread like the discount', async () => {
  db({ net_sales: 0, cost_of_goods: 0, costed_revenue: 0 });
  await summary();
  const q = mockRequest.query.mock.calls.map((c) => c[0]).find((s) => /AS net_sales/.test(s));
  expect(q).toMatch(/bi\.unit_cost/);
  expect(q).not.toMatch(/stock_batch_allocations/);
  expect(q).toMatch(/ISNULL\(b\.round_off, 0\)/);
});

test('goods returned in the period come off sales, tax, the money by mode and profit', async () => {
  db({ net_sales: 1000, cost_of_goods: 620, costed_revenue: 960 }, [
    { day: new Date('2026-11-10T00:00:00Z'), refund_mode: 'cash', cnt: 1, total: 118, subtotal: 100, tax: 18,
      costed_net: 100, cost: 62 },
  ]);
  const res = await summary();
  expect(res.body).toMatchObject({
    total_revenue: 1062, total_tax: 162, returns_total: 118, returns_count: 1,
    costed_revenue: 860, cost_of_goods: 558, gross_profit: 302,
  });
  expect(res.body.by_payment_mode.cash).toBe(1062);
  // A day with only a return still shows, as a negative.
  expect(res.body.daily).toEqual([{ day: '2026-11-10', revenue: -118, expenses: 0, profit: -118 }]);
});
