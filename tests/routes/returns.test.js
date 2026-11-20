// Sales returns (credit notes, migration 082): POST/GET/DELETE
// /api/bills/:id/returns. Valued at the bill's own prices and discount; stock
// and batches come back; "credit" comes off a credit bill's due.
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
const LINE = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const ITEM = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const RET = 'abababab-abab-abab-abab-abababababab';

let calls;
const sqlOf = (re) => calls.filter((c) => re.test(c.sql));

/**
 * A settled bill: one line, 4 × Rs. 100 net at 18%, with a Rs. 40 bill
 * discount on a Rs. 400 subtotal (ratio 0.9). [returned] already returned.
 */
function db({ status = 'finalized', paymentStatus = 'paid', returned = 0, due = 0,
  inventory = true, returnedAt = new Date(), bill = true, stockTaken = true, short = false,
  refundMode = 'cash', boom = null, found = true } = {}) {
  calls = [];
  const answer = (sqlText, inputs) => {
    const s = String(sqlText);
    calls.push({ sql: s, inputs: { ...inputs } });
    const ok = (rs = []) => Promise.resolve({ recordset: rs, rowsAffected: [rs.length || 1] });
    if (boom && boom.test(s)) return Promise.reject(new Error('db down'));
    if (short && /SET stock_quantity = stock_quantity - @qty/.test(s)) {
      return Promise.resolve({ recordset: [], rowsAffected: [0] });
    }
    if (/FROM bills b WITH \(UPDLOCK, ROWLOCK\)/.test(s)) {
      if (!bill) return ok([]);
      return ok([{ id: BILL, status, subtotal: 400, discount_amount: 40, tax_amount: 64.8,
        payment_status: paymentStatus, inventory_enabled: inventory }]);
    }
    if (/AS returned\s+FROM bill_items bi/.test(s)) {
      return ok([{ id: LINE, item_id: ITEM, variant_id: null, item_name: 'Tyre', quantity: 4,
        unit_price: 100, tax_rate: 18, hsn_code: '4011', unit_cost: 70, stock_taken: stockTaken, returned }]);
    }
    if (/AS due FROM bills b/.test(s)) return ok([{ due }]);
    if (/MAX\(return_seq\)/.test(s)) return ok([{ seq: 3 }]);
    if (/INSERT INTO sales_returns/.test(s)) return ok([{ id: RET }]);
    if (/FROM sales_returns sr WITH \(UPDLOCK\)/.test(s)) {
      if (!found) return ok([]);
      return ok([{ id: RET, returned_at: returnedAt, refund_mode: refundMode, inventory_enabled: inventory, batch_tracking_enabled: false }]);
    }
    if (/FROM sales_return_items sri\s+JOIN bill_items bi/.test(s)) {
      return ok([{ item_id: ITEM, variant_id: null, item_name: 'Tyre', quantity: 1, stock_taken: true }]);
    }
    if (/SELECT id, stock_quantity FROM items/.test(s)) return ok([{ id: ITEM, stock_quantity: 5 }]);
    if (/FROM sales_returns sr\s+JOIN sales_return_items/.test(s)) {
      return ok([{ id: RET, return_number: 'CN-0003', returned_at: new Date(), refund_mode: 'cash',
        subtotal: 180, tax_amount: 32.4, total: 212.4, bill_item_id: LINE, item_name: 'Tyre',
        quantity: 2, unit_price: 100, tax_rate: 18, net_amount: 180, line_tax: 32.4 }]);
    }
    return ok([]);
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

beforeEach(() => {
  mockRequest.reset();
  mockTransaction.commit.mockClear();
  mockTransaction.rollback.mockClear();
});

const ret = (body, role = 'cashier') => request(app).post(`/api/bills/${BILL}/returns`)
  .set(authHeader({ role })).send(body);
const two = { lines: [{ bill_item_id: LINE, quantity: 2 }], refund_mode: 'cash' };

test('needs lines and a valid refund mode', async () => {
  db();
  expect((await ret({ lines: [], refund_mode: 'cash' })).status).toBe(400);
  expect((await ret({ ...two, refund_mode: 'cheque' })).status).toBe(400);
});

test('a return is valued at the bill\'s own prices, discount and GST', async () => {
  db();
  const res = await ret(two);
  expect(res.status).toBe(201);
  // 2 × 100 × 0.9 = 180 taxable, 18% = 32.40 GST.
  const head = sqlOf(/INSERT INTO sales_returns/)[0].inputs;
  expect(head).toMatchObject({ return_number: 'CN-0003', subtotal: 180, tax_amount: 32.4, total: 212.4, refund_mode: 'cash' });
  const line = sqlOf(/INSERT INTO sales_return_items/)[0].inputs;
  expect(line).toMatchObject({ bill_item_id: LINE, quantity: 2, net_amount: 180, tax_amount: 32.4, unit_cost: 70 });
  expect(res.body.return_number).toBe('CN-0003');
});

test('the goods come back on the shelf, logged as a return, and to their batches', async () => {
  db();
  await ret(two);
  expect(sqlOf(/UPDATE items SET stock_quantity = stock_quantity \+ @qty/)[0].inputs.qty).toBe(2);
  const ledger = sqlOf(/INSERT INTO stock_movements/)[0].inputs;
  expect(ledger).toMatchObject({ type: 'return', qty: 2 });
  expect(sqlOf(/FROM stock_batch_allocations a\s+JOIN stock_batches sb/)).toHaveLength(1);
});

test('more than is left on the line is refused', async () => {
  db({ returned: 3 });
  const res = await ret(two);
  expect(res.status).toBe(400);
  expect(res.body.error).toMatch(/only 1 can be returned/);
  expect(sqlOf(/INSERT INTO sales_returns/)).toHaveLength(0);
});

test('only a settled bill takes a return', async () => {
  db({ status: 'draft' });
  expect((await ret(two)).status).toBe(409);
});

test('a fully returned line loses its warranty', async () => {
  db({ returned: 2 });
  await ret(two);
  expect(sqlOf(/DELETE FROM warranties WHERE bill_item_id/)).toHaveLength(1);
});

test('a partly returned line keeps its warranty', async () => {
  db();
  await ret(two);
  expect(sqlOf(/DELETE FROM warranties/)).toHaveLength(0);
});

test('"credit" comes off a credit bill\'s due and can settle it', async () => {
  db({ paymentStatus: 'unpaid', due: 500 });
  const res = await ret({ ...two, refund_mode: 'credit' });
  expect(res.status).toBe(201);
  expect(sqlOf(/SET b\.payment_status = 'paid'/)).toHaveLength(1);
});

test('"credit" is refused on a bill with nothing owing, or more than owed', async () => {
  db({ paymentStatus: 'paid' });
  expect((await ret({ ...two, refund_mode: 'credit' })).status).toBe(400);
  db({ paymentStatus: 'unpaid', due: 100 });
  expect((await ret({ ...two, refund_mode: 'credit' })).status).toBe(400);
});

test('a bill\'s credit notes are listed with their lines', async () => {
  db();
  const res = await request(app).get(`/api/bills/${BILL}/returns`).set(authHeader({ role: 'cashier' }));
  expect(res.status).toBe(200);
  expect(res.body[0]).toMatchObject({ return_number: 'CN-0003', total: 212.4 });
  expect(res.body[0].items[0]).toMatchObject({ item_name: 'Tyre', quantity: 2 });
});

test('only the owner can undo a return, and only the same day', async () => {
  db();
  const url = `/api/bills/${BILL}/returns/${RET}`;
  expect((await request(app).delete(url).set(authHeader({ role: 'cashier' }))).status).toBe(403);
  db({ returnedAt: new Date('2026-01-01T00:00:00Z') });
  expect((await request(app).delete(url).set(authHeader({ role: 'owner' }))).status).toBe(409);
  db();
  const res = await request(app).delete(url).set(authHeader({ role: 'owner' }));
  expect(res.status).toBe(200);
  // The goods go back out and the note is gone.
  expect(sqlOf(/SET stock_quantity = stock_quantity - @qty/)).toHaveLength(1);
  expect(sqlOf(/DELETE FROM sales_returns WHERE id = @id/)).toHaveLength(1);
});

describe('who may return, and which bills', () => {
  test('needs a login', async () => {
    db();
    const res = await request(app).post(`/api/bills/${BILL}/returns`).send(two);
    expect(res.status).toBe(401);
  });

  test('a waiter cannot take a return', async () => {
    db();
    expect((await ret(two, 'server')).status).toBe(403);
    expect(sqlOf(/INSERT INTO sales_returns/)).toHaveLength(0);
  });

  test('a bill id that is not a uuid is not found', async () => {
    db();
    const res = await request(app).post('/api/bills/123/returns').set(authHeader({ role: 'cashier' })).send(two);
    expect(res.status).toBe(404);
  });

  test("another business's bill is not found, looked up by the token's business", async () => {
    db({ bill: false });
    const res = await ret(two);
    expect(res.status).toBe(404);
    expect(sqlOf(/FROM bills b WITH \(UPDLOCK, ROWLOCK\)/)[0].inputs.business_id)
      .toBe('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    expect(mockTransaction.rollback).toHaveBeenCalled();
    expect(mockTransaction.commit).not.toHaveBeenCalled();
  });
});

describe('bad lines', () => {
  test('a zero quantity or a line id that is not a uuid is refused before the DB', async () => {
    db();
    expect((await ret({ ...two, lines: [{ bill_item_id: LINE, quantity: 0 }] })).status).toBe(400);
    expect((await ret({ ...two, lines: [{ bill_item_id: 'x', quantity: 1 }] })).status).toBe(400);
    expect(calls).toHaveLength(0);
  });

  test('a line from another bill is refused', async () => {
    db();
    const res = await ret({ ...two, lines: [{ bill_item_id: RET, quantity: 1 }] });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/not on this bill/);
  });

  test('a line sent twice adds up against what is left', async () => {
    db({ returned: 1 }); // 3 left; 2 + 2 asked
    const res = await ret({ ...two, lines: [{ bill_item_id: LINE, quantity: 2 }, { bill_item_id: LINE, quantity: 2 }] });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/only 3 can be returned/);
  });

  test('a refused return rolls back and writes nothing', async () => {
    db({ returned: 3 });
    await ret(two);
    expect(mockTransaction.rollback).toHaveBeenCalled();
    expect(mockTransaction.commit).not.toHaveBeenCalled();
  });

  test('a DB failure mid-return rolls back and answers 500', async () => {
    db({ boom: /INSERT INTO sales_return_items/ });
    const res = await ret(two);
    expect(res.status).toBe(500);
    expect(mockTransaction.rollback).toHaveBeenCalled();
    expect(mockTransaction.commit).not.toHaveBeenCalled();
  });
});

describe('stock on a return', () => {
  test('a shop without inventory gets no stock back', async () => {
    db({ inventory: false });
    expect((await ret(two)).status).toBe(201);
    expect(sqlOf(/stock_quantity = stock_quantity \+ @qty/)).toHaveLength(0);
  });

  test('a line that never took stock (online order) gives none back', async () => {
    db({ stockTaken: false });
    expect((await ret(two)).status).toBe(201);
    expect(sqlOf(/stock_quantity = stock_quantity \+ @qty/)).toHaveLength(0);
  });
});

describe('undoing a return', () => {
  const url = `/api/bills/${BILL}/returns/${RET}`;
  const undo = () => request(app).delete(url).set(authHeader({ role: 'owner' }));

  test('an unknown return is not found', async () => {
    db({ found: false });
    expect((await undo()).status).toBe(404);
    expect(sqlOf(/DELETE FROM sales_returns/)).toHaveLength(0);
  });

  test('refused when the goods have been sold again, and nothing is deleted', async () => {
    db({ short: true });
    const res = await undo();
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/not enough stock/);
    expect(sqlOf(/DELETE FROM sales_returns/)).toHaveLength(0);
    expect(mockTransaction.rollback).toHaveBeenCalled();
    expect(mockTransaction.commit).not.toHaveBeenCalled();
  });

  test('undoing a credit refund makes the bill owe again', async () => {
    db({ refundMode: 'credit' });
    expect((await undo()).status).toBe(200);
    expect(sqlOf(/SET b\.payment_status = 'unpaid'/)).toHaveLength(1);
  });
});
