'use strict';

const { netUnitPrice } = require('../../src/money');

// Helper mirroring how billing re-grosses a line: net rate -> what the customer
// pays. An inclusive item must land back on the exact price the owner entered.
const gross = (net, rate) => net * (1 + rate / 100);

describe('netUnitPrice — exclusive pricing (the default)', () => {
  test('returns the price unchanged; tax is added on top by the caller', () => {
    expect(netUnitPrice(100, 5, false)).toBe(100);
    expect(netUnitPrice(100, 18, false)).toBe(100);
  });

  test('is unaffected by the tax rate, since the price is already net', () => {
    expect(netUnitPrice(250, 12, false)).toBe(netUnitPrice(250, 28, false));
  });
});

describe('netUnitPrice — inclusive (MRP) pricing', () => {
  test('strips the tax back out of the gross price', () => {
    // 105 inclusive of 5% GST is 100 net + 5 tax.
    expect(netUnitPrice(105, 5, true)).toBeCloseTo(100, 10);
    // 118 inclusive of 18% GST is 100 net + 18 tax.
    expect(netUnitPrice(118, 18, true)).toBeCloseTo(100, 10);
  });

  test('re-grossing the net rate returns the original MRP exactly', () => {
    // The property that matters at the counter: a 20 MRP snack rings up at 20,
    // not 21. 20/1.05 is non-terminating, so this only holds because the helper
    // returns full precision rather than rounding to paise.
    for (const [mrp, rate] of [[20, 5], [99, 12], [149.5, 18], [10, 28]]) {
      expect(gross(netUnitPrice(mrp, rate, true), rate)).toBeCloseTo(mrp, 10);
    }
  });

  test('an inclusive price is always lower than the same figure treated as net', () => {
    expect(netUnitPrice(100, 18, true)).toBeLessThan(netUnitPrice(100, 18, false));
  });
});

describe('netUnitPrice — when there is no tax to extract', () => {
  // GST off for the business, or an item with no rate set: an inclusive price
  // is the whole amount charged, so both modes must agree.
  test('a null tax rate leaves the price untouched in both modes', () => {
    expect(netUnitPrice(100, null, true)).toBe(100);
    expect(netUnitPrice(100, null, false)).toBe(100);
  });

  test('a zero tax rate leaves the price untouched in both modes', () => {
    expect(netUnitPrice(100, 0, true)).toBe(100);
    expect(netUnitPrice(100, 0, false)).toBe(100);
  });

  test('a zero price stays zero rather than becoming NaN', () => {
    expect(netUnitPrice(0, 18, true)).toBe(0);
  });
});

describe('netUnitPrice — non-numeric input', () => {
  // Prices arrive from mssql as strings/Decimal and can be null for a sized
  // item. Coercing to 0 keeps a bad line finite; callers reject it separately.
  test('accepts numeric strings, as the DB driver returns them', () => {
    expect(netUnitPrice('105', '5', true)).toBeCloseTo(100, 10);
  });

  test('null/undefined price degrades to 0 instead of NaN', () => {
    expect(netUnitPrice(null, 5, true)).toBe(0);
    expect(netUnitPrice(undefined, 5, false)).toBe(0);
  });
});
