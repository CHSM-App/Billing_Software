const { globalKey } = require('../../src/middleware/rateLimiter');
const { signAccessToken } = require('../../src/auth');

// The whole point of globalKey: several tills in one shop share a public IP,
// so they must NOT share a rate-limit budget.
describe('globalKey', () => {
  const req = (token, ip = '203.0.113.5') => ({
    ip,
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });

  const tokenFor = (user_id) =>
    signAccessToken({ user_id, business_id: 'b1', role: 'owner' });

  test('two staff on the SAME shop IP get separate buckets', () => {
    const a = globalKey(req(tokenFor('user-a')));
    const b = globalKey(req(tokenFor('user-b')));
    expect(a).not.toBe(b);
  });

  test('the same user from two devices shares one bucket', () => {
    expect(globalKey(req(tokenFor('user-a'), '203.0.113.5')))
      .toBe(globalKey(req(tokenFor('user-a'), '198.51.100.9')));
  });

  test('anonymous requests fall back to the IP bucket', () => {
    expect(globalKey(req(null))).toBe(globalKey(req(null)));
    expect(globalKey(req(null, '203.0.113.5')))
      .not.toBe(globalKey(req(null, '198.51.100.9')));
  });

  test('a forged or expired token does not crash, falls back to IP', () => {
    expect(globalKey(req('not-a-jwt'))).toBe(globalKey(req(null)));
  });

  test('IPv6 clients are bucketed by subnet, not by address', () => {
    const one = globalKey(req(null, '2001:db8:abcd:0012::1'));
    const two = globalKey(req(null, '2001:db8:abcd:0012::99'));
    expect(one).toBe(two);
  });
});
