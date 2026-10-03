jest.mock('../../src/db', () => ({ sql: {} }));
const { trimPlan } = require('../../src/batches');

describe('trimPlan', () => {
  const batches = [
    { id: 'old', qty_remaining: 3 },
    { id: 'mid', qty_remaining: 5 },
    { id: 'new', qty_remaining: 10 },
  ];

  test('takes from the oldest batches first', () => {
    expect(trimPlan(6, batches)).toEqual([
      { id: 'old', take: 3 },
      { id: 'mid', take: 3 },
    ]);
  });

  test('never takes more than a batch holds', () => {
    expect(trimPlan(100, batches)).toEqual([
      { id: 'old', take: 3 },
      { id: 'mid', take: 5 },
      { id: 'new', take: 10 },
    ]);
  });

  test('nothing to trim', () => {
    expect(trimPlan(0, batches)).toEqual([]);
  });

  test('decimal quantities stay exact', () => {
    expect(trimPlan(0.3, [{ id: 'a', qty_remaining: 0.1 }, { id: 'b', qty_remaining: 0.25 }]))
      .toEqual([{ id: 'a', take: 0.1 }, { id: 'b', take: 0.2 }]);
  });
});
