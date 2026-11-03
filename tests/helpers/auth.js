const jwt = require('jsonwebtoken');

const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET;

/**
 * Generate a signed access token for use in test requests.
 * @param {object} overrides - Fields to override on the default payload.
 */
function makeToken(overrides = {}) {
  const payload = {
    user_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    business_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    role: 'owner',
    ...overrides,
  };
  return jwt.sign(payload, ACCESS_SECRET, { expiresIn: '15m' });
}

/**
 * Return an Authorization header object with a Bearer token.
 */
function authHeader(overrides = {}) {
  return { Authorization: `Bearer ${makeToken(overrides)}` };
}

module.exports = { makeToken, authHeader };
