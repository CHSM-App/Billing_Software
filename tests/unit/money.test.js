'use strict';

const { computeRoundOff } = require('../../src/money');

describe('computeRoundOff', () => {
  test('returns 0 when rounding is disabled (any amount)', () => {
    expect(computeRoundOff(125.22, false)).toBe(0);
    expect(computeRoundOff(125.6, false)).toBe(0);
    expect(computeRoundOff(999.99, false)).toBe(0);
  });

  test('rounds down when fraction < .5 (negative round-off)', () => {
    // 125.22 -> 125.00, adjustment -0.22
    expect(computeRoundOff(125.22, true)).toBe(-0.22);
  });

  test('rounds up when fraction >= .5 (positive round-off)', () => {
    // 125.60 -> 126.00, adjustment +0.40
    expect(computeRoundOff(125.6, true)).toBe(0.4);
  });

  test('rounds half up at exactly .50', () => {
    // 125.50 -> 126.00, adjustment +0.50
    expect(computeRoundOff(125.5, true)).toBe(0.5);
  });

  test('whole-rupee amounts have zero round-off', () => {
    expect(computeRoundOff(200, true)).toBe(0);
  });

  test('final payable reconciles: payable + round_off === rounded rupee', () => {
    for (const payable of [125.22, 125.6, 125.5, 0.49, 0.5, 999.01]) {
      const ro = computeRoundOff(payable, true);
      const finalPayable = parseFloat((payable + ro).toFixed(2));
      expect(Number.isInteger(finalPayable)).toBe(true);
    }
  });

  test('handles 0 and non-numeric safely', () => {
    expect(computeRoundOff(0, true)).toBe(0);
    expect(computeRoundOff(null, true)).toBe(0);
    expect(computeRoundOff(undefined, true)).toBe(0);
  });
});
