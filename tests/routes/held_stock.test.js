// Online/QR order lines arrive without taking stock (bill_items.stock_taken
// = 0). A void or edit must not give that stock back, and a shop that
// maintains batches takes it when the bill is settled — never failing the
// settle.
const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
jest.mock('../../src/audit', () => new Proxy({}, { get: () => jest.fn(() => Promise.resolve()) }));
jest.mock('../../src/realtime', () => ({ attach: jest.fn(), broadcast: jest.fn() }));
jest.mock('../../src/fcm', () => new Proxy({}, { get: () => jest.fn(() => Promise.resolve()) }));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const BILL = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const ITEM = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const BATCH = 'abababab-abab-abab-abab-abababababab';

let calls;
const sqlOf = (re) => calls.filter((c) => re.test(c.sql));

/** One answer per statement, by what it does. [held] = the finalize's answer. */
function db({ held, short = false } = {}) {
  calls = [];
  const answer = (sqlText, inputs) => {
    const s = String(sqlText);
    calls.push({ sql: s, inputs: { ...inputs } });
    const ok = (rs = [], extra = {}) => Promise.resolve({ recordset: rs, recordsets: [rs], rowsAffected: [rs.length || 1], ...extra });
    if (/UPDATE bills\s+SET status = 'finalized'/.test(s)) {
      const row = [{ id: BILL, table_id: null, bill_number: 'INV-1', payment_mode: 'cash' }];
      return ok(row, { recordsets: [row, [{ take_held: held ? 1 : 0 }]] });
    }
    if (/WHERE bill_id = @bill_id AND stock_taken = 0/.test(s)) {
      return ok([{ id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', item_id: ITEM, variant_id: null, item_name: 'Rice', quantity: 2, batch_id: null }]);
    }
    if (/SELECT id, stock_quantity FROM items/.test(s)) return ok([{ id: ITEM, stock_quantity: 10 }]);
    if (/SET stock_quantity = stock_quantity - @qty/.test(s)) return ok([], { rowsAffected: [short ? 0 : 1] });
    if (/FROM stock_batches WITH \(UPDLOCK\)/.test(s)) return ok([{ id: BATCH, qty_remaining: 5 }]);
    if (/FROM item_recipes/.test(s)) return ok([]);
    return ok([{ id: BILL, bill_number: 'INV-1', status: 'finalized', items: [] }]);
  };
  mockRequest.query.mockImplementation(function (sqlText) { return answer(sqlText, this.inputs); });
  mockTransaction.request.mockImplementation(() => {
    const inputs = {};
    const r = {
      input: jest.fn((k, _t, v) => { inputs[k] = v; return r; }),
      query: jest.fn((sqlText) => answer(sqlText, inputs)),
    };
    return r;
  });
}

beforeEach(() => mockRequest.reset());

const settle = () => request(app).put(`/api/bills/${BILL}/finalize`).set(authHeader()).send({});

test('every finalize asks, in the same statement, whether held stock needs taking', async () => {
  db({ held: false });
  await settle();
  expect(sqlOf(/UPDATE bills\s+SET status = 'finalized'/)[0].sql).toMatch(/AS take_held/);
  // No: nothing else runs — a shop without batches settles exactly as before.
  expect(sqlOf(/stock_taken = 0/).filter((c) => !/take_held/.test(c.sql))).toHaveLength(0);
});

test('a batch shop takes the stock of its online/QR lines at finalize', async () => {
  db({ held: true });
  const res = await settle();
  expect(res.status).toBe(200);
  expect(sqlOf(/SET stock_quantity = stock_quantity - @qty/)).toHaveLength(1);
  expect(sqlOf(/SET qty_sold = qty_sold \+ @qty/)[0].inputs).toMatchObject({ id: BATCH, qty: 2 });
  expect(sqlOf(/UPDATE bill_items SET stock_taken = 1/)).toHaveLength(1);
  expect(sqlOf(/UPDATE bi SET unit_cost/)).toHaveLength(1);
});

test('a line that is short is skipped and the bill still settles', async () => {
  db({ held: true, short: true });
  const res = await settle();
  expect(res.status).toBe(200);
  expect(sqlOf(/ROLLBACK TRANSACTION held_line/)).toHaveLength(1);
  expect(sqlOf(/UPDATE bill_items SET stock_taken = 1/)).toHaveLength(0);
});

test('a void gives back only stock the lines actually took', async () => {
  db({});
  mockRequest.query.mockImplementation(function (sqlText) {
    calls.push({ sql: String(sqlText), inputs: { ...this.inputs } });
    return Promise.resolve({ recordset: [{ id: BILL, status: 'finalized', inventory_enabled: true }], rowsAffected: [1] });
  });
  await request(app).delete(`/api/bills/${BILL}`).set(authHeader());
  const restoreRead = sqlOf(/SELECT item_id, variant_id, item_name, quantity FROM bill_items WHERE bill_id = @bill_id/)[0];
  expect(restoreRead.sql).toMatch(/AND stock_taken = 1/);
});
