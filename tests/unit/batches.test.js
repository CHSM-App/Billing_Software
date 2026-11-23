// Pure functions only: keep the real db module from opening a connection.
jest.mock('../../src/db', () => ({ sql: {} }));
const { fifoPlan, unitCost, batchCode } = require('../../src/batches');

const A = 'AAAAAAAA-0000-0000-0000-000000000001';
const B = 'BBBBBBBB-0000-0000-0000-000000000002';
const batches = [{ id: A, qty_remaining: 5 }, { id: B, qty_remaining: 5 }];

describe('fifoPlan', () => {
  test('takes the oldest batch first, then the next', () => {
    expect(fifoPlan(7, batches)).toEqual([{ id: A, take: 5 }, { id: B, take: 2 }]);
  });

  test('the preferred batch goes first, matched case-insensitively', () => {
    expect(fifoPlan(7, batches, B.toLowerCase()))
      .toEqual([{ id: B, take: 5 }, { id: A, take: 2 }]);
  });

  test('a preferred batch that is not open falls back to oldest first', () => {
    expect(fifoPlan(3, batches, 'cccccccc-0000-0000-0000-000000000003'))
      .toEqual([{ id: A, take: 3 }]);
  });

  test('never takes more than the batches hold; the rest is opening stock', () => {
    expect(fifoPlan(12, batches)).toEqual([{ id: A, take: 5 }, { id: B, take: 5 }]);
  });

  test('decimal quantities stay exact', () => {
    expect(fifoPlan(0.3, [{ id: A, qty_remaining: 0.1 }, { id: B, qty_remaining: 0.2 }]))
      .toEqual([{ id: A, take: 0.1 }, { id: B, take: 0.2 }]);
  });
});

describe('unitCost', () => {
  // 10 bought at Rs. 50 net, 18% GST (Rs. 90), 2 free.
  const line = { quantity: 10, free_quantity: 2, _net: 500, _tax: 90 };

  test('free goods lower the cost of every unit received', () => {
    expect(unitCost(line, 1, false)).toBe(41.6667);
  });

  test('a bill discount scales the cost', () => {
    expect(unitCost({ ...line, free_quantity: 0 }, 0.9, false)).toBe(45);
  });

  test('GST is cost when it cannot be claimed back', () => {
    expect(unitCost({ ...line, free_quantity: 0 }, 1, true)).toBe(59);
  });
});

test('batchCode pads to four digits', () => {
  expect(batchCode(42)).toBe('B-0042');
  expect(batchCode(12345)).toBe('B-12345');
});

describe('fifoPlan with old (pre-batch) stock', () => {
  test('old stock goes first and produces no batch take', () => {
    // 2 old, then oldest batch.
    expect(fifoPlan(7, batches, null, 2)).toEqual([{ id: A, take: 5 }]);
  });
  test("the cashier's pick still comes before old stock", () => {
    expect(fifoPlan(7, batches, B, 2)).toEqual([{ id: B, take: 5 }]);
  });
  test('old stock covering the whole sale takes no batch', () => {
    expect(fifoPlan(3, batches, null, 10)).toEqual([]);
  });
});
