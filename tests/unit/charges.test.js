const { parseAdditionalCharges, serializeCharges, attachCharges } = require('../../src/charges');

describe('parseAdditionalCharges', () => {
  test('treats undefined/null as no charges', () => {
    expect(parseAdditionalCharges(undefined)).toEqual({ charges: [], chargesAmount: 0 });
    expect(parseAdditionalCharges(null)).toEqual({ charges: [], chargesAmount: 0 });
  });

  test('normalises names and amounts and sums them', () => {
    const r = parseAdditionalCharges([
      { name: '  Delivery ', amount: 30 },
      { name: 'Packaging', amount: '10.005' },
    ]);
    expect(r.error).toBeUndefined();
    expect(r.charges).toEqual([
      { name: 'Delivery', amount: 30 },
      { name: 'Packaging', amount: 10.01 },
    ]);
    expect(r.chargesAmount).toBe(40.01);
  });

  test('rejects bad shapes', () => {
    expect(parseAdditionalCharges('x').error).toMatch(/array/);
    expect(parseAdditionalCharges([null]).error).toBeDefined();
    expect(parseAdditionalCharges([{ name: '', amount: 1 }]).error).toMatch(/name/);
    expect(parseAdditionalCharges([{ name: 'a'.repeat(101), amount: 1 }]).error).toMatch(/100/);
    expect(parseAdditionalCharges([{ name: 'Delivery', amount: 0 }]).error).toMatch(/greater than 0/);
    expect(parseAdditionalCharges([{ name: 'Delivery', amount: -5 }]).error).toMatch(/greater than 0/);
    expect(parseAdditionalCharges([{ name: 'Delivery', amount: 'abc' }]).error).toBeDefined();
    expect(parseAdditionalCharges(Array(11).fill({ name: 'x', amount: 1 })).error).toMatch(/at most 10/);
  });
});

describe('serializeCharges / attachCharges', () => {
  test('round-trips through the stored JSON', () => {
    const charges = [{ name: 'Delivery', amount: 30 }];
    const stored = serializeCharges(charges);
    expect(typeof stored).toBe('string');
    const row = attachCharges({ additional_charges: stored, charges_amount: 30 });
    expect(row.additional_charges).toEqual(charges);
    expect(row.charges_amount).toBe(30);
  });

  test('empty list stores NULL and reads back as [] with charges_amount 0', () => {
    expect(serializeCharges([])).toBeNull();
    const row = attachCharges({ additional_charges: null, charges_amount: null });
    expect(row.additional_charges).toEqual([]);
    expect(row.charges_amount).toBe(0);
  });

  test('corrupt JSON degrades to no charges instead of throwing', () => {
    const row = attachCharges({ additional_charges: '{not json', charges_amount: 5 });
    expect(row.additional_charges).toEqual([]);
  });
});
