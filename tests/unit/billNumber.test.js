const { stripBillPrefix } = require('../../src/billNumber');

describe('stripBillPrefix', () => {
  test('drops the default INV prefix', () => {
    expect(stripBillPrefix('INV-0007')).toBe('0007');
  });

  test('drops a custom letter prefix', () => {
    expect(stripBillPrefix('VT-0042')).toBe('0042');
  });

  test('keeps the device tag on offline-numbered bills', () => {
    expect(stripBillPrefix('INV-a7f4-0001')).toBe('a7f4-0001');
  });

  test('returns prefix-less numbers unchanged', () => {
    expect(stripBillPrefix('0007')).toBe('0007');
    expect(stripBillPrefix('2024/0007')).toBe('2024/0007');
  });

  test('tolerates null/undefined', () => {
    expect(stripBillPrefix(null)).toBe('');
    expect(stripBillPrefix(undefined)).toBe('');
  });
});
