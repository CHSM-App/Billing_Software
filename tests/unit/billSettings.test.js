const { parse, normalize, defaults, shopPhones, noteText } = require('../../src/billSettings');

test('the shop note prints only when switched on', () => {
  expect(noteText(parse(null))).toBe('');
  expect(noteText(parse(normalize({ note: ' Free delivery ' }).value))).toBe('');
  expect(noteText(parse(normalize({ show_note: true, note: ' Free delivery ' }).value))).toBe('Free delivery');
});

describe('billSettings', () => {
  test('NULL / bad JSON → defaults (today\'s bill: everything on, bank off)', () => {
    for (const t of [null, '', 'not json', '[]', '42']) {
      expect(parse(t)).toEqual(defaults());
    }
    expect(parse(null).show_cashier).toBe(true);
    expect(parse(null).show_bank).toBe(false);
  });

  test('parse keeps saved values, ignores wrong types', () => {
    const s = parse(JSON.stringify({ show_cashier: false, show_gstin: 'no', bank: { ifsc: 'SBIN0001234', note: 5 } }));
    expect(s.show_cashier).toBe(false);
    expect(s.show_gstin).toBe(true);
    expect(s.bank.ifsc).toBe('SBIN0001234');
    expect(s.bank.note).toBe('');
  });

  test('normalize round-trips and cleans bank fields', () => {
    const r = normalize({ show_bank: true, extra: 1, bank: { account_no: '1234 5678 90', ifsc: 'sbin0001234', bank_name: ' SBI ' } });
    expect(r.error).toBeUndefined();
    const s = parse(r.value);
    expect(s.show_bank).toBe(true);
    expect(s.bank).toMatchObject({ account_no: '1234567890', ifsc: 'SBIN0001234', bank_name: 'SBI' });
    expect(JSON.parse(r.value).extra).toBeUndefined();
  });

  test('normalize rejects bad input', () => {
    expect(normalize(null).error).toBeTruthy();
    expect(normalize([]).error).toBeTruthy();
    expect(normalize({ show_bank: 'yes' }).error).toBeTruthy();
    expect(normalize({ bank: { ifsc: 'SBIN1234' } }).error).toMatch(/IFSC/);
    expect(normalize({ bank: { account_no: '12AB' } }).error).toMatch(/Account/);
    expect(normalize({ bank: { note: 'x'.repeat(201) } }).error).toBeTruthy();
    expect(normalize({ alt_phone: 'call me' }).error).toMatch(/alternate/);
    expect(normalize({ note: 'x'.repeat(301) }).error).toMatch(/Note/);
  });

  test('warranty details print by default, and the toggle round-trips', () => {
    expect(parse(null).show_warranty_details).toBe(true);
    const r = normalize({ show_warranty_details: false });
    expect(r.error).toBeUndefined();
    expect(parse(r.value).show_warranty_details).toBe(false);
  });

  test('alternate number is saved and printed after the main one', () => {
    const s = parse(normalize({ alt_phone: ' 02366-262626 ' }).value);
    expect(s.alt_phone).toBe('02366-262626');
    expect(shopPhones('9876500000', s)).toBe('9876500000, 02366-262626');
    expect(shopPhones(null, s)).toBe('02366-262626');
    expect(shopPhones('9876500000', parse(null))).toBe('9876500000');
  });
});
