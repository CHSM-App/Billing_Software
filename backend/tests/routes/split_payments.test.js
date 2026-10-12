// Split payments (migration 050) and paying old credit off with a new bill
// (migration 051): one bill paid in several modes, optionally with a credit
// part, optionally collecting old dues.
const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();
jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/audit', () => ({
  logBillCreated: jest.fn(),
  logBillFinalized: jest.fn(),
  logBillVoided: jest.fn(),
}));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const { pourIntoModes } = require('../../src/creditPayments');

const BILL_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const OLD_ID = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

beforeEach(() => {
  mockRequest.reset();
  jest.clearAllMocks();
});

const sqls = () => mockRequest.query.mock.calls.map((c) => c[0]);
const ran = (re) => sqls().some((s) => re.test(s));
const finalize = (body) => request(app)
  .put(`/api/bills/${BILL_ID}/finalize`)
  .set(authHeader())
  .send(body);
const ok = (recordset = [], n = 1) => ({ recordset, rowsAffected: [n] });

// The locked draft finalizeWithTenders reads its payable from: ₹700.
const draftRow = (over = {}) => ({
  id: BILL_ID, table_id: null, bill_number: 'INV-0001', payment_mode: 'cash',
  customer_name: 'Asha', customer_phone: '9876543210',
  total: 699.6, discount_amount: 0, round_off: 0.4, ...over,
});

// draft, UPDATE, INSERT parts, then fetchBill: bill row, items, parts.
function queueSplitFinalize() {
  mockRequest.query
    .mockResolvedValueOnce(ok([draftRow()]))
    .mockResolvedValueOnce(ok())
    .mockResolvedValueOnce(ok([], 3))
    .mockResolvedValueOnce(ok([{ id: BILL_ID, payment_mode: 'split' }]))
    .mockResolvedValueOnce(ok([], 0))
    .mockResolvedValueOnce(ok([{ bill_id: BILL_ID, mode: 'cash', amount: 300 }]));
}

describe('PUT /api/bills/:id/finalize — split', () => {
  test('records each part and the credit part as the due', async () => {
    queueSplitFinalize();

    const res = await finalize({
      payment_mode: 'split',
      payments: [
        { mode: 'cash', amount: 300 },
        { mode: 'upi', amount: 200 },
        { mode: 'credit', amount: 200 },
      ],
    });

    expect(res.status).toBe(200);
    expect(mockRequest.inputs).toMatchObject({
      payment_mode: 'split', payment_status: 'unpaid', credit_amount: 200,
      pay_mode0: 'cash', pay_amount0: 300,
      pay_mode1: 'upi', pay_amount1: 200,
      pay_mode2: 'credit', pay_amount2: 200,
    });
    expect(ran(/INSERT INTO bill_payments/)).toBe(true);
    expect(mockTransaction.commit).toHaveBeenCalled();
    expect(res.body.payments).toEqual([{ mode: 'cash', amount: 300 }]);
  });

  test('without a credit part the bill is paid', async () => {
    queueSplitFinalize();
    const res = await finalize({
      payment_mode: 'split',
      payments: [{ mode: 'cash', amount: 500 }, { mode: 'card', amount: 200 }],
    });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.credit_amount).toBeNull();
    expect(mockRequest.inputs.payment_status).toBe('paid');
  });

  test('parts that do not add up to the payable are refused', async () => {
    mockRequest.query.mockResolvedValueOnce(ok([draftRow()]));
    const res = await finalize({
      payment_mode: 'split',
      payments: [{ mode: 'cash', amount: 300 }, { mode: 'upi', amount: 300 }],
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/add up to ₹600\.00 but the bill is ₹700\.00/);
    expect(mockTransaction.rollback).toHaveBeenCalled();
    expect(ran(/INSERT INTO bill_payments/)).toBe(false);
  });

  // The app totals the bill itself; a paisa of rounding against the server's
  // figure must not refuse a split — the last part absorbs it.
  test('a paisa of rounding is absorbed by the last part', async () => {
    queueSplitFinalize();
    const res = await finalize({
      payment_mode: 'split',
      payments: [{ mode: 'cash', amount: 500 }, { mode: 'credit', amount: 199.99 }],
    });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs).toMatchObject({ pay_mode1: 'credit', pay_amount1: 200, credit_amount: 200 });
  });

  test('more than ₹0.10 off is still refused', async () => {
    mockRequest.query.mockResolvedValueOnce(ok([draftRow()]));
    const res = await finalize({
      payment_mode: 'split',
      payments: [{ mode: 'cash', amount: 500 }, { mode: 'upi', amount: 199.8 }],
    });
    expect(res.status).toBe(400);
  });

  test('a credit part needs the customer name and phone', async () => {
    mockRequest.query.mockResolvedValueOnce(ok([draftRow({ customer_name: null })]));
    const res = await finalize({
      payment_mode: 'split',
      payments: [{ mode: 'cash', amount: 500 }, { mode: 'credit', amount: 200 }],
    });
    expect(res.status).toBe(400);
    expect(mockTransaction.rollback).toHaveBeenCalled();
  });

  test.each([
    ['one part', [{ mode: 'cash', amount: 700 }]],
    ['a mode twice', [{ mode: 'cash', amount: 300 }, { mode: 'cash', amount: 400 }]],
    ['a zero amount', [{ mode: 'cash', amount: 700 }, { mode: 'upi', amount: 0 }]],
    ['split inside split', [{ mode: 'cash', amount: 300 }, { mode: 'split', amount: 400 }]],
  ])('refuses %s without touching the DB', async (_, payments) => {
    const res = await finalize({ payment_mode: 'split', payments });
    expect(res.status).toBe(400);
    expect(mockRequest.query).not.toHaveBeenCalled();
  });

  test('a single-mode finalize is unchanged and writes no parts', async () => {
    mockRequest.query
      .mockResolvedValueOnce(ok([{ id: BILL_ID, table_id: null, bill_number: 'INV-0001', payment_mode: 'upi' }]))
      .mockResolvedValueOnce(ok([{ id: BILL_ID, payment_mode: 'upi' }]))
      .mockResolvedValueOnce(ok([], 0));
    const res = await finalize({ payment_mode: 'upi' });
    expect(res.status).toBe(200);
    expect(mockTransaction.begin).not.toHaveBeenCalled();
    expect(ran(/bill_payments|credit_payments/)).toBe(false);
  });
});

describe('PUT /api/bills/:id/finalize — collecting old credit', () => {
  // draft, old bill's due, UPDATE, [parts], INSERT credit_payments, settle,
  // then fetchBill: bill row, items, [parts], collected list.
  function queueCollect({ due = 500, split = false } = {}) {
    mockRequest.query
      .mockResolvedValueOnce(ok([draftRow()]))
      .mockResolvedValueOnce(ok([{ id: OLD_ID, bill_number: 'INV-0007', due }]))
      .mockResolvedValueOnce(ok());
    if (split) mockRequest.query.mockResolvedValueOnce(ok([], 2));
    mockRequest.query
      .mockResolvedValueOnce(ok())
      .mockResolvedValueOnce(ok())
      .mockResolvedValueOnce(ok([{ id: BILL_ID, payment_mode: 'cash', credit_collected: 300 }]))
      .mockResolvedValueOnce(ok([], 0))
      .mockResolvedValueOnce(ok([{ paid_in_bill_id: BILL_ID, bill_id: OLD_ID, bill_number: 'INV-0007', amount: 300 }]));
  }

  test('one mode pays the bill and the old due together', async () => {
    queueCollect();
    const res = await finalize({
      payment_mode: 'cash',
      collect: [{ bill_id: OLD_ID, amount: 300 }],
    });

    expect(res.status).toBe(200);
    // The new bill is a plain cash bill; ₹300 of the cash paid the old one.
    expect(mockRequest.inputs).toMatchObject({
      payment_mode: 'cash', payment_status: 'paid', credit_collected: 300,
      cp_bill0: OLD_ID, cp_mode0: 'cash', cp_amount0: 300, cp_paid_in: BILL_ID,
    });
    expect(ran(/INSERT INTO credit_payments/)).toBe(true);
    expect(res.body.collected).toEqual([{ bill_id: OLD_ID, bill_number: 'INV-0007', amount: 300 }]);
  });

  test('split money: the old due comes out of the biggest mode', async () => {
    queueCollect({ split: true });
    // ₹700 bill + ₹300 old due = ₹1,000, as Cash 600 + UPI 400.
    const res = await finalize({
      payment_mode: 'split',
      payments: [{ mode: 'cash', amount: 600 }, { mode: 'upi', amount: 400 }],
      collect: [{ bill_id: OLD_ID, amount: 300 }],
    });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs).toMatchObject({
      cp_mode0: 'cash', cp_amount0: 300,
      pay_mode0: 'cash', pay_amount0: 300,
      pay_mode1: 'upi', pay_amount1: 400,
      payment_mode: 'split', credit_collected: 300,
    });
  });

  test('more than the old bill owes is refused', async () => {
    mockRequest.query
      .mockResolvedValueOnce(ok([draftRow()]))
      .mockResolvedValueOnce(ok([{ id: OLD_ID, bill_number: 'INV-0007', due: 200 }]));
    const res = await finalize({ payment_mode: 'cash', collect: [{ bill_id: OLD_ID, amount: 300 }] });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/INV-0007 owes ₹200\.00/);
    expect(mockTransaction.rollback).toHaveBeenCalled();
  });

  test('an old bill already paid is refused', async () => {
    mockRequest.query
      .mockResolvedValueOnce(ok([draftRow()]))
      .mockResolvedValueOnce(ok([]));
    const res = await finalize({ payment_mode: 'cash', collect: [{ bill_id: OLD_ID, amount: 100 }] });
    expect(res.status).toBe(409);
  });

  test('old credit cannot be paid with credit', async () => {
    mockRequest.query
      .mockResolvedValueOnce(ok([draftRow()]))
      .mockResolvedValueOnce(ok([{ id: OLD_ID, bill_number: 'INV-0007', due: 500 }]));
    const res = await finalize({ payment_mode: 'credit', collect: [{ bill_id: OLD_ID, amount: 300 }] });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/cannot go on credit/);
  });
});

describe('DELETE /api/bills/:id — voiding a bill that collected old credit', () => {
  test('takes the money back: the old bill owes it again', async () => {
    mockRequest.query
      .mockResolvedValueOnce(ok([{ id: BILL_ID, status: 'finalized', table_id: null,
        bill_number: 'INV-0012', total: 700, credit_collected: 300, inventory_enabled: false }]))
      .mockResolvedValueOnce(ok([], 1))                     // status → voided
      .mockResolvedValueOnce(ok([{ bill_id: OLD_ID }]))      // DELETE credit_payments
      .mockResolvedValueOnce(ok([], 1));                    // reopen old bill

    const res = await request(app).delete(`/api/bills/${BILL_ID}`).set(authHeader());

    expect(res.status).toBe(200);
    expect(ran(/DELETE FROM credit_payments/)).toBe(true);
    expect(ran(/SET payment_status = 'unpaid', settled_at = NULL/)).toBe(true);
    expect(mockRequest.inputs).toMatchObject({ cp_paid_in: BILL_ID, cp_reopen0: OLD_ID });
  });
});

describe('pourIntoModes', () => {
  test('one old bill can be paid from two modes', () => {
    const r = pourIntoModes(
      [{ bill_id: 'a', amount: 900 }],
      [{ mode: 'cash', amount: 600 }, { mode: 'upi', amount: 400 }],
    );
    expect(r.rows).toEqual([
      { bill_id: 'a', mode: 'cash', amount: 600 },
      { bill_id: 'a', mode: 'upi', amount: 300 },
    ]);
    expect(Object.fromEntries(r.left)).toEqual({ cash: 0, upi: 100 });
  });

  test('a credit part never pays old credit', () => {
    const r = pourIntoModes(
      [{ bill_id: 'a', amount: 100 }],
      [{ mode: 'credit', amount: 700 }],
    );
    expect(r.error).toBeDefined();
  });
});

describe('POST /api/bills — split', () => {
  test('a draft cannot be split', async () => {
    const res = await request(app)
      .post('/api/bills')
      .set(authHeader())
      .send({
        items: [{ item_id: 'cccccccc-cccc-cccc-cccc-cccccccccccc', quantity: 1 }],
        payment_mode: 'split', status: 'draft',
        payments: [{ mode: 'cash', amount: 1 }, { mode: 'upi', amount: 1 }],
      });
    expect(res.status).toBe(400);
  });
});

describe('credit dues', () => {
  test('owe the credit part less what has been paid on it', async () => {
    mockRequest.recordset = [];
    await request(app).get('/api/credit/customers').set(authHeader());
    await request(app).get('/api/credit/customers/9876543210/summary').set(authHeader());
    const [list, summary] = sqls();
    for (const q of [list, summary]) {
      expect(q).toContain('ISNULL(b.credit_amount, b.total - b.discount_amount + ISNULL(b.round_off, 0))');
      expect(q).toContain('FROM credit_payments cp WHERE cp.bill_id = b.id');
    }
  });

  test('the Credit tab can pay part of a bill', async () => {
    mockRequest.query
      .mockResolvedValueOnce(ok([{ id: OLD_ID, bill_number: 'INV-0007', due: 500 }]))
      .mockResolvedValueOnce(ok()) // credit_settlements insert
      .mockResolvedValueOnce(ok())
      .mockResolvedValueOnce(ok())
      .mockResolvedValueOnce(ok([{
        id: OLD_ID, bill_number: 'INV-0007', payment_mode: 'credit', additional_charges: null,
        total: 800, discount_amount: 0, round_off: 0, due: 300, customer_phone: '9876543210',
        created_at: new Date('2026-10-01T10:00:00Z'),
      }]))
      .mockResolvedValueOnce(ok([], 0))
      .mockResolvedValueOnce(ok([{ bill_id: OLD_ID, amount: 200, mode: 'upi', created_at: new Date(), paid_in_bill_number: null }]));

    const res = await request(app)
      .post('/api/credit/settle')
      .set(authHeader())
      .send({ payment_mode: 'upi', payments: [{ bill_id: OLD_ID, amount: 200 }] });

    expect(res.status).toBe(200);
    expect(mockRequest.inputs).toMatchObject({ cp_mode0: 'upi', cp_amount0: 200, cp_paid_in: null });
    expect(res.body.bills[0].credit_paid).toBe(200);

    // One Payment Receipt for the call: its payments carry the settlement id,
    // and the line shows what was paid NOW and what is still owed after it.
    const { settlement } = res.body;
    expect(mockRequest.inputs.cp_settlement).toBe(settlement.id);
    expect(settlement.receipt_token).toMatch(/^[A-Za-z0-9]{16}$/);
    expect(settlement).toMatchObject({ mode: 'upi', total: 200, customer_phone: '9876543210' });
    expect(settlement.lines).toEqual([expect.objectContaining({
      bill_number: 'INV-0007', bill_total: 800, paid: 200, due: 300,
    })]);
    expect(sqls().some((q) => /INSERT INTO credit_settlements/.test(q))).toBe(true);
  });

  test('the older whole-bill settle pays everything owed', async () => {
    mockRequest.query
      .mockResolvedValueOnce(ok([{ id: OLD_ID, bill_number: 'INV-0007', due: 450 }]))
      .mockResolvedValueOnce(ok()) // credit_settlements insert
      .mockResolvedValueOnce(ok())
      .mockResolvedValueOnce(ok())
      .mockResolvedValueOnce(ok([{ id: OLD_ID, payment_mode: 'credit', additional_charges: null }]))
      .mockResolvedValueOnce(ok([], 0))
      .mockResolvedValueOnce(ok([]));

    const res = await request(app)
      .post('/api/credit/settle')
      .set(authHeader())
      .send({ payment_mode: 'cash', bill_ids: [OLD_ID] });

    expect(res.status).toBe(200);
    expect(mockRequest.inputs).toMatchObject({ cp_mode0: 'cash', cp_amount0: 450 });
  });
});
