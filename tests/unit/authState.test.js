// requireAuth + the real authState cache (tests/setup.js stubs it for every
// other suite). Security_Review.pdf #3 (subscription) and #5 (sessions).
jest.unmock('../../src/authState');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
jest.mock('../../src/db', () => mockPool);

const authState = require('../../src/authState');
const { requireAuth, signAccessToken } = require('../../src/auth');

const USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const DAY = 24 * 60 * 60 * 1000;

const row = (over = {}) => ({
  is_active: true, role: 'owner', sessions_valid_after: null,
  status: 'active', expires_at: new Date(Date.now() + 10 * DAY), grace_period_days: 0,
  ...over,
});

function call({ method = 'GET', url = '/api/bills', body, token } = {}) {
  const tok = token || signAccessToken({ user_id: USER_ID, business_id: BUSINESS_ID, role: 'owner' });
  const req = { method, originalUrl: url, body, headers: { authorization: `Bearer ${tok}` } };
  const res = { status: jest.fn().mockReturnThis(), json: jest.fn().mockReturnThis() };
  const next = jest.fn();
  return Promise.resolve(requireAuth(req, res, next)).then(() => ({ req, res, next }));
}

beforeEach(() => {
  mockRequest.reset();
  authState.forgetUser(USER_ID);
});

describe('session state (#5)', () => {
  test('a cache hit makes no database query', async () => {
    mockRequest.recordset = [row()];
    await call();
    await call();
    await call();
    expect(mockRequest.query).toHaveBeenCalledTimes(1);
  });

  test('the hit path is synchronous — no promise on the billing hot path', async () => {
    mockRequest.recordset = [row()];
    await call(); // warm
    const req = { method: 'GET', originalUrl: '/api/bills', headers: { authorization: `Bearer ${signAccessToken({ user_id: USER_ID, business_id: BUSINESS_ID, role: 'owner' })}` } };
    const next = jest.fn();
    requireAuth(req, { status: jest.fn().mockReturnThis(), json: jest.fn() }, next);
    expect(next).toHaveBeenCalledTimes(1);
  });

  test('a disabled user is refused', async () => {
    mockRequest.recordset = [row({ is_active: false })];
    const { res, next } = await call();
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  test('a deleted user (no row) is refused', async () => {
    mockRequest.recordset = [];
    const { res } = await call();
    expect(res.status).toHaveBeenCalledWith(401);
  });

  test('the role comes from the database, not the token', async () => {
    mockRequest.recordset = [row({ role: 'server' })];
    const { req, next } = await call();
    expect(next).toHaveBeenCalled();
    expect(req.user.role).toBe('server');
  });

  test('a token issued before sessions_valid_after is refused', async () => {
    mockRequest.recordset = [row({ sessions_valid_after: new Date(Date.now() + 5000) })];
    const { res } = await call();
    expect(res.status).toHaveBeenCalledWith(401);
  });

  test('forgetUser makes the next request re-read the database', async () => {
    mockRequest.recordset = [row()];
    await call();
    authState.forgetUser(USER_ID);
    mockRequest.recordset = [row({ is_active: false })];
    const { res } = await call();
    expect(res.status).toHaveBeenCalledWith(401);
  });

  test('forgetBusiness drops every user of that business', async () => {
    mockRequest.recordset = [row()];
    await call();
    authState.forgetBusiness(BUSINESS_ID);
    expect(authState.cached(USER_ID)).toBeUndefined();
  });

  test('a database error with no history lets the token decide (fail-open)', async () => {
    mockRequest.query.mockRejectedValueOnce(new Error('db down'));
    const { next } = await call();
    expect(next).toHaveBeenCalled();
  });
});

describe('subscription enforcement (#3)', () => {
  const expired = { status: 'expired', expires_at: new Date(Date.now() - 3 * DAY), grace_period_days: 1 };

  test('an expired business can still read', async () => {
    mockRequest.recordset = [row(expired)];
    const { next } = await call({ method: 'GET' });
    expect(next).toHaveBeenCalled();
  });

  test('an expired business cannot write — 402, which the app sync retries', async () => {
    mockRequest.recordset = [row(expired)];
    const { res, next } = await call({ method: 'POST', url: '/api/items' });
    expect(res.status).toHaveBeenCalledWith(402);
    expect(res.json.mock.calls[0][0].code).toBe('subscription_inactive');
    expect(next).not.toHaveBeenCalled();
  });

  test('an offline sale made while paid still syncs', async () => {
    mockRequest.recordset = [row(expired)];
    const soldWhilePaid = new Date(Date.now() - 2.5 * DAY).toISOString(); // inside grace
    const { next } = await call({ method: 'POST', url: '/api/bills', body: { finalized_at: soldWhilePaid } });
    expect(next).toHaveBeenCalled();
  });

  test('an offline sale dated after the paid time is refused', async () => {
    mockRequest.recordset = [row(expired)];
    const { res } = await call({ method: 'POST', url: '/api/bills', body: { finalized_at: new Date().toISOString() } });
    expect(res.status).toHaveBeenCalledWith(402);
  });

  test('grace period counts as paid', async () => {
    mockRequest.recordset = [row({ status: 'expired', expires_at: new Date(Date.now() - DAY), grace_period_days: 3 })];
    const { next } = await call({ method: 'POST', url: '/api/items' });
    expect(next).toHaveBeenCalled();
  });

  test('suspended blocks writes even with time left', async () => {
    mockRequest.recordset = [row({ status: 'suspended' })];
    const { res } = await call({ method: 'PUT', url: '/api/items/x' });
    expect(res.status).toHaveBeenCalledWith(402);
  });

  test('no subscription row blocks writes', async () => {
    mockRequest.recordset = [row({ status: null, expires_at: null })];
    const { res } = await call({ method: 'POST', url: '/api/items' });
    expect(res.status).toHaveBeenCalledWith(402);
  });

  test.each(['/api/logout-all', '/api/fcm/token', '/api/fcm/token/remove'])(
    '%s still works when lapsed', async (url) => {
      mockRequest.recordset = [row(expired)];
      const { next } = await call({ method: 'POST', url });
      expect(next).toHaveBeenCalled();
    });
});
