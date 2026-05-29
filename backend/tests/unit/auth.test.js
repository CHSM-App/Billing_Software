const jwt = require('jsonwebtoken');

const {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
  requireAuth,
} = require('../../src/auth');

const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET;
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET;

const payload = {
  user_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  business_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  role: 'owner',
};

// ------------------------------------------------------------------
// signAccessToken / verifyAccessToken
// ------------------------------------------------------------------
describe('signAccessToken', () => {
  test('produces a JWT signed with the access secret', () => {
    const token = signAccessToken(payload);
    const decoded = jwt.verify(token, ACCESS_SECRET);
    expect(decoded.user_id).toBe(payload.user_id);
    expect(decoded.role).toBe('owner');
  });

  test('expires in 15 minutes', () => {
    const token = signAccessToken(payload);
    const decoded = jwt.decode(token);
    const diffSec = decoded.exp - decoded.iat;
    expect(diffSec).toBe(15 * 60);
  });
});

describe('verifyAccessToken', () => {
  test('returns decoded payload for a valid token', () => {
    const token = signAccessToken(payload);
    const decoded = verifyAccessToken(token);
    expect(decoded.user_id).toBe(payload.user_id);
  });

  test('throws for a tampered token', () => {
    expect(() => verifyAccessToken('invalid.token.here')).toThrow();
  });

  test('throws for a token signed with the wrong secret', () => {
    const token = jwt.sign(payload, 'completely-wrong-secret-value-32ch');
    expect(() => verifyAccessToken(token)).toThrow();
  });
});

// ------------------------------------------------------------------
// signRefreshToken / verifyRefreshToken
// ------------------------------------------------------------------
describe('signRefreshToken', () => {
  test('produces a JWT signed with the refresh secret', () => {
    const token = signRefreshToken(payload);
    const decoded = jwt.verify(token, REFRESH_SECRET);
    expect(decoded.business_id).toBe(payload.business_id);
  });

  test('expires in 30 days', () => {
    const token = signRefreshToken(payload);
    const decoded = jwt.decode(token);
    const diffDays = (decoded.exp - decoded.iat) / (60 * 60 * 24);
    expect(diffDays).toBe(30);
  });
});

describe('verifyRefreshToken', () => {
  test('returns decoded payload for a valid token', () => {
    const token = signRefreshToken(payload);
    const decoded = verifyRefreshToken(token);
    expect(decoded.role).toBe('owner');
  });

  test('throws for an expired token', () => {
    const expired = jwt.sign(payload, REFRESH_SECRET, { expiresIn: -1 });
    expect(() => verifyRefreshToken(expired)).toThrow();
  });
});

// ------------------------------------------------------------------
// requireAuth middleware
// ------------------------------------------------------------------
describe('requireAuth middleware', () => {
  function mockRes() {
    const res = {};
    res.status = jest.fn().mockReturnValue(res);
    res.json = jest.fn().mockReturnValue(res);
    return res;
  }

  test('calls next() and sets req.user for a valid Bearer token', () => {
    const token = signAccessToken(payload);
    const req = { headers: { authorization: `Bearer ${token}` } };
    const res = mockRes();
    const next = jest.fn();

    requireAuth(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.user.user_id).toBe(payload.user_id);
  });

  test('returns 401 when Authorization header is missing', () => {
    const req = { headers: {} };
    const res = mockRes();
    const next = jest.fn();

    requireAuth(req, res, next);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  test('returns 401 when token is invalid', () => {
    const req = { headers: { authorization: 'Bearer bad.token' } };
    const res = mockRes();
    const next = jest.fn();

    requireAuth(req, res, next);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  test('returns 401 when header does not start with Bearer', () => {
    const req = { headers: { authorization: 'Basic abc123' } };
    const res = mockRes();
    const next = jest.fn();

    requireAuth(req, res, next);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });
});
