const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
// The consent flow switched ON at a test version. Its OFF state (the shipped
// default, TERMS_VERSION = null) is covered at the bottom of license.test.js
// and auth.test.js, which load the real src/legal.js.
jest.mock('../../src/legal', () => ({ TERMS_VERSION: 'test-1' }));

const { authHeader } = require('../helpers/auth');
const app = require('../../src/server');

const USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

const calls = (re) => mockRequest.query.mock.calls.filter(c => re.test(c[0]));
const TERMS_INSERT = /INSERT INTO terms_acceptances/;
const AUDIT_TERMS = /INSERT INTO audit_logs/;

/** Answer each query by its SQL text instead of by call order. */
function respond(handlers) {
  mockRequest.query.mockImplementation(function (text) {
    for (const [re, result] of handlers) {
      if (re.test(text)) return Promise.resolve(typeof result === 'function' ? result() : result);
    }
    return Promise.resolve({ recordset: [], rowsAffected: [1] });
  });
}

beforeEach(() => {
  mockRequest.reset();
  delete process.env.REQUIRE_TERMS_ACCEPT;
});

// ---------------------------------------------------------------------------
// POST /api/register — sign-up consent
// ---------------------------------------------------------------------------
describe('POST /api/register — terms', () => {
  const body = {
    business_name: 'Test Shop',
    business_type: 'retail',
    phone: '9876543210',
    owner_name: 'Test Owner',
    owner_phone: '9876543211',
    pin: '4831',
  };

  beforeEach(() => respond([
    [/SELECT TOP 1 id FROM users/, { recordset: [], rowsAffected: [0] }],
    [/INSERT INTO businesses/, { recordset: [{ id: BUSINESS_ID }], rowsAffected: [1] }],
    [/INSERT INTO users/, { recordset: [{ id: USER_ID }], rowsAffected: [1] }],
  ]));

  it('records the acceptance and its audit row inside the registration', async () => {
    const res = await request(app).post('/api/register').send({ ...body, accept_terms: true });
    expect(res.status).toBe(200);
    expect(calls(TERMS_INSERT)).toHaveLength(1);
    expect(calls(TERMS_INSERT)[0][0]).toMatch(/'register'/);
    expect(calls(AUDIT_TERMS)).toHaveLength(1);
  });

  it('records nothing for an older app that sends no accept_terms (flag off)', async () => {
    const res = await request(app).post('/api/register').send(body);
    expect(res.status).toBe(200);
    expect(calls(TERMS_INSERT)).toHaveLength(0);
  });

  it('accepts only a literal true — a truthy string is not consent', async () => {
    await request(app).post('/api/register').send({ ...body, accept_terms: 'yes' });
    expect(calls(TERMS_INSERT)).toHaveLength(0);
  });

  it('refuses registration without acceptance once REQUIRE_TERMS_ACCEPT=true', async () => {
    process.env.REQUIRE_TERMS_ACCEPT = 'true';
    const res = await request(app).post('/api/register').send(body);
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Terms of Service/);
    expect(calls(/INSERT INTO businesses/)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// GET /api/license — terms_required
// ---------------------------------------------------------------------------
describe('GET /api/license — terms_required', () => {
  const sub = (role) => ({
    status: 'active',
    expires_at: new Date(Date.now() + 90 * 86400000),
    max_offline_days: 30,
    grace_period_days: 5,
    current_role: role,
    user_ok: 1,
  });
  const license = (role, acceptedCount) => {
    respond([
      [/FROM subscriptions s/, { recordset: [sub(role)] }],
      [/FROM terms_acceptances/, { recordset: [{ n: acceptedCount }] }],
    ]);
    return request(app).get('/api/license').set(authHeader({ role }));
  };

  it('asks an owner who has not accepted the current version', async () => {
    const res = await license('owner', 0);
    expect(res.status).toBe(200);
    expect(res.body.terms_required).toBe(true);
    expect(res.body.terms_version).toBe('test-1');
  });

  it('stops asking once the owner has accepted it', async () => {
    const res = await license('owner', 1);
    expect(res.body.terms_required).toBe(false);
  });

  it('never asks staff, and does not even look', async () => {
    const res = await license('cashier', 0);
    expect(res.body.terms_required).toBe(false);
    expect(calls(/FROM terms_acceptances/)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// POST /api/account/accept-terms
// ---------------------------------------------------------------------------
describe('POST /api/account/accept-terms', () => {
  const accept = (body, role = 'owner') =>
    request(app).post('/api/account/accept-terms').set(authHeader({ role })).send(body);
  const owner = (role = 'owner', inserted = 1) => respond([
    [/SELECT name, role FROM users/, { recordset: [{ name: 'Test Owner', role }] }],
    [TERMS_INSERT, { recordset: [], rowsAffected: [inserted] }],
  ]);

  it('requires a staff session token', async () => {
    const res = await request(app).post('/api/account/accept-terms').send({ terms_version: 'test-1' });
    expect(res.status).toBe(401);
    expect(calls(TERMS_INSERT)).toHaveLength(0);
  });

  it('refuses a version that is not the server\'s current one', async () => {
    owner();
    const res = await accept({ terms_version: 'made-up' });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe('terms_version_mismatch');
    expect(res.body.terms_version).toBe('test-1');
    expect(calls(TERMS_INSERT)).toHaveLength(0);
  });

  it('refuses staff — only the owner agrees for the business', async () => {
    owner('cashier');
    const res = await accept({ terms_version: 'test-1' }, 'cashier');
    expect(res.status).toBe(403);
    expect(calls(TERMS_INSERT)).toHaveLength(0);
  });

  it('records the acceptance for the token\'s own user, ignoring any id in the body', async () => {
    owner();
    const res = await accept({ terms_version: 'test-1', user_id: 'cccccccc-cccc-cccc-cccc-cccccccccccc' });
    expect(res.status).toBe(200);
    expect(calls(TERMS_INSERT)).toHaveLength(1);
    expect(calls(TERMS_INSERT)[0][0]).toMatch(/'reaccept'/);
    expect(mockRequest.inputs.user_id).toBe(USER_ID);
    expect(mockRequest.inputs.terms_version).toBe('test-1');
    expect(calls(AUDIT_TERMS)).toHaveLength(1);
  });

  it('is a quiet success when this version was already accepted', async () => {
    owner('owner', 0);
    const res = await accept({ terms_version: 'test-1' });
    expect(res.status).toBe(200);
    expect(calls(AUDIT_TERMS)).toHaveLength(0);
  });

  it('treats a lost race on the unique index as already accepted', async () => {
    respond([
      [/SELECT name, role FROM users/, { recordset: [{ name: 'Test Owner', role: 'owner' }] }],
      [TERMS_INSERT, () => Promise.reject(Object.assign(new Error('dup'), { number: 2627 }))],
    ]);
    const res = await accept({ terms_version: 'test-1' });
    expect(res.status).toBe(200);
  });

  it('reports a database failure instead of pretending it saved', async () => {
    respond([
      [/SELECT name, role FROM users/, { recordset: [{ name: 'Test Owner', role: 'owner' }] }],
      [TERMS_INSERT, () => Promise.reject(new Error('db down'))],
    ]);
    const res = await accept({ terms_version: 'test-1' });
    expect(res.status).toBe(500);
    expect(res.body.success).toBeUndefined();
  });
});
