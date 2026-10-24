const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const LIST_ID = '11111111-1111-4111-8111-111111111111';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const VAR_ID  = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

// Every pool query answers by its SQL, so the order of lookups doesn't matter.
function routeDb({ taken = false, items = [{ id: ITEM_ID }], variants = [], list = true } = {}) {
  const calls = [];
  mockRequest.query.mockImplementation((sqlText) => {
    calls.push(sqlText);
    const ok = (rs = []) => Promise.resolve({ recordset: rs, rowsAffected: [rs.length] });
    if (/AS x FROM price_lists/.test(sqlText)) return ok(taken ? [{ x: 1 }] : []);
    if (/FROM item_variants/.test(sqlText)) return ok(variants);
    if (/SELECT id FROM items/.test(sqlText)) return ok(items);
    if (/SELECT id FROM price_lists/.test(sqlText)) return ok(list ? [{ id: LIST_ID }] : []);
    if (/FROM price_list_items/.test(sqlText)) {
      return ok([{ price_list_id: LIST_ID, item_id: ITEM_ID, variant_id: null, price: '120.00' }]);
    }
    if (/FROM price_lists/.test(sqlText)) return ok([{ id: LIST_ID, name: 'Party', adjust_pct: '10.00' }]);
    if (/UPDATE price_lists SET is_active = 0/.test(sqlText)) {
      return Promise.resolve({ recordset: [], rowsAffected: [list ? 1 : 0] });
    }
    return ok();
  });
  const txSql = [];
  mockTransaction.request.mockImplementation(() => {
    const r = {
      inputs: {},
      input(k, _t, v) { r.inputs[k] = v; return r; },
      query: jest.fn((sqlText) => {
        txSql.push({ sqlText, inputs: r.inputs });
        return Promise.resolve({ recordset: [{ id: LIST_ID }], rowsAffected: [1] });
      }),
    };
    return r;
  });
  return { calls, txSql };
}

beforeEach(() => {
  mockRequest.reset();
  jest.clearAllMocks();
});

describe('GET /api/price-lists', () => {
  test('401 without a token', async () => {
    expect((await request(app).get('/api/price-lists')).status).toBe(401);
  });

  test.each(['owner', 'cashier', 'server'])('%s gets the lists with their prices', async (role) => {
    routeDb();
    const res = await request(app).get('/api/price-lists').set(authHeader({ role }));
    expect(res.status).toBe(200);
    expect(res.body).toEqual([{
      id: LIST_ID, name: 'Party', adjust_pct: 10,
      items: [{ item_id: ITEM_ID, variant_id: null, price: 120 }],
    }]);
  });

  test('prices for deleted items are dropped by the join', async () => {
    const { calls } = routeDb();
    await request(app).get('/api/price-lists').set(authHeader());
    expect(calls.find((s) => /FROM price_list_items/.test(s))).toMatch(/i\.is_active = 1/);
  });
});

describe('POST /api/price-lists', () => {
  const post = (body, role = 'owner') =>
    request(app).post('/api/price-lists').set(authHeader({ role })).send(body);

  test('owner creates a list and its prices in one transaction', async () => {
    const { txSql } = routeDb();
    const res = await post({ name: ' Party ', adjust_pct: 10, items: [{ item_id: ITEM_ID, price: 120 }] });
    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Party');
    expect(txSql[0].inputs).toMatchObject({ name: 'Party', adjust_pct: 10 });
    const insert = txSql.find((c) => /INSERT INTO price_list_items/.test(c.sqlText));
    expect(insert.inputs).toMatchObject({ item0: ITEM_ID, var0: null, price0: 120 });
    expect(mockTransaction.commit).toHaveBeenCalled();
  });

  test('a 0% rule is stored as no rule', async () => {
    const { txSql } = routeDb();
    await post({ name: 'Same', adjust_pct: 0 });
    expect(txSql[0].inputs.adjust_pct).toBeNull();
  });

  test.each(['cashier', 'server'])('%s gets 403', async (role) => {
    routeDb();
    expect((await post({ name: 'X' }, role)).status).toBe(403);
  });

  test.each([
    ['no name', { name: '  ' }],
    ['a long name', { name: 'x'.repeat(61) }],
    ['a % below -90', { name: 'X', adjust_pct: -95 }],
    ['a % above 500', { name: 'X', adjust_pct: 501 }],
    ['a text %', { name: 'X', adjust_pct: 'ten' }],
    ['a negative price', { name: 'X', items: [{ item_id: ITEM_ID, price: -1 }] }],
    ['a missing price', { name: 'X', items: [{ item_id: ITEM_ID }] }],
    ['a duplicate item', { name: 'X', items: [{ item_id: ITEM_ID, price: 1 }, { item_id: ITEM_ID, price: 2 }] }],
  ])('rejects %s with 400', async (_n, body) => {
    routeDb();
    expect((await post(body)).status).toBe(400);
  });

  test('a duplicate name is a 409', async () => {
    routeDb({ taken: true });
    expect((await post({ name: 'Party' })).status).toBe(409);
  });

  test("an item from another business is a 400", async () => {
    routeDb({ items: [] });
    const res = await post({ name: 'X', items: [{ item_id: ITEM_ID, price: 1 }] });
    expect(res.status).toBe(400);
    expect(mockTransaction.begin).not.toHaveBeenCalled();
  });

  test("a size listed under the wrong item is a 400", async () => {
    routeDb({ variants: [{ id: VAR_ID, item_id: 'ffffffff-ffff-ffff-ffff-ffffffffffff' }] });
    const res = await post({ name: 'X', items: [{ item_id: ITEM_ID, variant_id: VAR_ID, price: 1 }] });
    expect(res.status).toBe(400);
  });
});

describe('PUT /api/price-lists/:id', () => {
  const put = (body) =>
    request(app).put(`/api/price-lists/${LIST_ID}`).set(authHeader()).send(body);

  test('replaces the name, rule and every price', async () => {
    const { txSql } = routeDb();
    const res = await put({ name: 'Party', adjust_pct: 5, items: [] });
    expect(res.status).toBe(200);
    expect(txSql.map((c) => c.sqlText).join('\n')).toMatch(/DELETE FROM price_list_items/);
  });

  test('404 for a list of another business', async () => {
    routeDb({ list: false });
    expect((await put({ name: 'Party' })).status).toBe(404);
  });
});

describe('DELETE /api/price-lists/:id', () => {
  test('soft-deletes', async () => {
    const { calls } = routeDb();
    const res = await request(app).delete(`/api/price-lists/${LIST_ID}`).set(authHeader());
    expect(res.status).toBe(200);
    expect(calls[0]).toMatch(/SET is_active = 0/);
  });

  test('404 when not found', async () => {
    routeDb({ list: false });
    const res = await request(app).delete(`/api/price-lists/${LIST_ID}`).set(authHeader());
    expect(res.status).toBe(404);
  });

  test('cashier gets 403', async () => {
    const res = await request(app).delete(`/api/price-lists/${LIST_ID}`).set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });
});
