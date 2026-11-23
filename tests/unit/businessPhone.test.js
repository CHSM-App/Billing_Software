const { isBusinessPhone, isIndianMobile } = require('../../src/validate');

test('business phone takes a mobile or an STD landline; other phones stay mobile-only', () => {
  for (const ok of ['9876500000', '02366262626', '02366-262626', '022 2345 6789', ' 02366-262626 ']) {
    expect(isBusinessPhone(ok)).toBe(true);
  }
  for (const bad of ['', null, '5123456789', '2366262626', '0236626262', '00366262626', '02366-26262a']) {
    expect(isBusinessPhone(bad)).toBe(false);
  }
  expect(isIndianMobile('02366262626')).toBe(false);
});
