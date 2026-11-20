// Regression tests for the fixes from Security_Review.pdf. Each block names the
// finding it locks in, so a failure points at the hole that reopened.
const request = require('supertest');
const fs = require('fs');
const jwt = require('jsonwebtoken');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
jest.mock('../../src/db', () => mockPool);

// The PDF route spawns a browser; record the calls instead.
jest.mock('child_process', () => ({
  ...jest.requireActual('child_process'),
  execFile: jest.fn(),
}));

const { execFile } = require('child_process');
const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const { publicTokenSecret } = require('../../src/auth');

const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const BILL_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

beforeEach(() => {
  mockRequest.reset();
  mockPool.pool.request.mockClear();
  execFile.mockReset();
});

// ── #4 quantity validation ──────────────────────────────────────────────────
describe('#4 bill line quantity must be a sane positive number', () => {
  const routes = [
    ['post', '/api/bills', { payment_mode: 'cash' }],
    ['put', `/api/bills/${BILL_ID}/add-items`, {}],
    ['put', `/api/bills/${BILL_ID}/update-items`, {}],
  ];
  const badQuantities = [-1, 0, 'abc', null, 100000, Infinity];

  for (const [method, url, extra] of routes) {
    test.each(badQuantities)(`${method.toUpperCase()} ${url} rejects quantity %p before any DB work`, async (quantity) => {
      const res = await request(app)[method](url)
        .set(authHeader())
        .send({ ...extra, items: [{ item_id: ITEM_ID, quantity }] });
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/quantity/);
      expect(mockPool.pool.request).not.toHaveBeenCalled();
    });
  }
});

// ── #7 receipt PDF ──────────────────────────────────────────────────────────
describe('#7 receipt PDF does not start a browser for nothing', () => {
  test('unknown token → 404 without launching a browser', async () => {
    mockRequest.recordset = [];
    const res = await request(app).get('/receipt/abcdefgh12345678/pdf');
    expect(res.status).toBe(404);
    expect(execFile).not.toHaveBeenCalled();
  });

  test('a third concurrent render is refused with 503 + Retry-After', async () => {
    mockRequest.recordset = [{ ok: 1 }];
    const pending = [];
    // Each "browser" writes its PDF but only exits when released.
    execFile.mockImplementation((bin, args, opts, cb) => {
      const out = args.find((a) => a.startsWith('--print-to-pdf=')).slice('--print-to-pdf='.length);
      fs.writeFileSync(out, '%PDF-1.4 test');
      pending.push(cb);
    });

    const a = request(app).get('/receipt/abcdefgh12345678/pdf').then((r) => r);
    const b = request(app).get('/receipt/abcdefgh12345678/pdf').then((r) => r);
    // Wait until both browsers are "running".
    for (let i = 0; i < 50 && pending.length < 2; i++) await new Promise((r) => setTimeout(r, 10));
    expect(pending.length).toBe(2);

    const c = await request(app).get('/receipt/abcdefgh12345678/pdf');
    expect(c.status).toBe(503);
    expect(c.headers['retry-after']).toBe('5');

    pending.forEach((cb) => cb(null));
    const [ra, rb] = await Promise.all([a, b]);
    expect(ra.status).toBe(200);
    expect(rb.status).toBe(200);
    expect(ra.headers['content-type']).toMatch(/application\/pdf/);
  });
});

// ── #8 admin surface ────────────────────────────────────────────────────────
describe('#8 admin surface', () => {
  test('the static-secret activate endpoint is gone', async () => {
    const res = await request(app).post('/api/license/admin/activate')
      .set('x-admin-secret', 'anything').send({});
    expect(res.status).toBe(404);
  });

  test('SheetJS is served from our own origin', async () => {
    const res = await request(app).get('/admin/static/xlsx.full.min.js');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/javascript/);
  });

  test('admin login is locked after 5 failures from one IP', async () => {
    let last;
    for (let i = 0; i < 6; i++) {
      last = await request(app).post('/admin/api/login').send({ username: 'x', password: 'wrong' });
    }
    expect(last.status).toBe(429);
  });
});

// ── #11 headers ─────────────────────────────────────────────────────────────
describe('#11 security headers', () => {
  test('baseline headers are set and X-Powered-By is gone', async () => {
    const res = await request(app).get('/api/does-not-exist');
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-frame-options']).toBe('SAMEORIGIN');
    expect(res.headers['referrer-policy']).toBe('strict-origin-when-cross-origin');
    expect(res.headers['x-powered-by']).toBeUndefined();
  });
});

// ── #13 OTP verification token ──────────────────────────────────────────────
describe('#13 the OTP verified_token is its own kind of token', () => {
  test('a token signed with the staff key is refused by reset-pin', async () => {
    const forged = jwt.sign({ verified_phone: '9876543210', purpose: 'forgot_pin' },
      process.env.JWT_ACCESS_SECRET, { expiresIn: '15m' });
    const res = await request(app).post('/api/reset-pin')
      .send({ verified_token: forged, new_pin: '4831' });
    expect(res.status).toBe(401);
  });

  test('a genuine OTP token is not accepted as a staff access token', async () => {
    const otpToken = jwt.sign({ typ: 'otp', verified_phone: '9876543210', purpose: 'forgot_pin' },
      publicTokenSecret('otp'), { expiresIn: '15m' });
    const res = await request(app).get('/api/bills').set('Authorization', `Bearer ${otpToken}`);
    expect(res.status).toBe(401);
  });

  test('verify-otp only serves its own two purposes', async () => {
    const res = await request(app).post('/api/verify-otp')
      .send({ phone: '9876543210', otp: '123456', purpose: 'delete_account' });
    expect(res.status).toBe(400);
  });
});

// ── #5 sessions end when they should ───────────────────────────────────────
describe('#5 sessions', () => {
  const authState = require('../../src/authState'); // the stub from tests/setup.js
  const realLoad = authState.load;
  afterEach(() => { authState.load = realLoad; });
  const { signRefreshToken } = require('../../src/auth');
  const USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const refresh = signRefreshToken({ user_id: USER_ID, business_id: BUSINESS_ID, role: 'owner' });

  test('PIN reset revokes refresh tokens and cuts off live access tokens', async () => {
    const token = jwt.sign({ typ: 'otp', verified_phone: '9876543210', purpose: 'forgot_pin' },
      publicTokenSecret('otp'), { expiresIn: '15m' });
    mockRequest.recordset = [{ id: USER_ID }];
    const res = await request(app).post('/api/reset-pin').send({ verified_token: token, new_pin: '4831' });
    expect(res.status).toBe(200);
    const sql = mockRequest.query.mock.calls[0][0];
    expect(sql).toMatch(/sessions_valid_after = @now/);
    expect(sql).toMatch(/SET revoked = 1/);
  });

  test('refresh refuses a disabled user', async () => {
    authState.load = () => Promise.resolve({ active: false });
    mockRequest.recordset = [{ id: 'token-row' }];
    const res = await request(app).post('/api/refresh').send({ refresh_token: refresh });
    expect(res.status).toBe(401);
  });

  test('refresh signs the CURRENT role', async () => {
    authState.load = () => Promise.resolve({ active: true, role: 'cashier', validAfterS: 0, paidUntil: Infinity });
    mockRequest.recordset = [{ id: 'token-row' }];
    const res = await request(app).post('/api/refresh').send({ refresh_token: refresh });
    expect(res.status).toBe(200);
    expect(jwt.decode(res.body.access_token).role).toBe('cashier');
  });

  test('log out everywhere also cuts off access tokens', async () => {
    const res = await request(app).post('/api/logout-all').set(authHeader());
    expect(res.status).toBe(200);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/sessions_valid_after = @now/);
  });
});

// ── #2 / #6 registration ────────────────────────────────────────────────────
describe('#2 #6 registration', () => {
  const body = {
    business_name: 'Shop', business_type: 'retail', phone: '9876543210',
    owner_name: 'Owner', owner_phone: '9876543211', pin: '4831',
  };
  afterEach(() => { delete process.env.REQUIRE_REGISTER_OTP; });

  test('#6 an owner phone already used anywhere is refused', async () => {
    mockRequest.recordset = [{ id: 'someone-else' }];
    const res = await request(app).post('/api/register').send(body);
    expect(res.status).toBe(409);
  });

  test('#2 with REQUIRE_REGISTER_OTP, sign-up needs the OTP proof for owner_phone', async () => {
    process.env.REQUIRE_REGISTER_OTP = 'true';
    const none = await request(app).post('/api/register').send(body);
    expect(none.status).toBe(401);

    const otherPhone = jwt.sign({ typ: 'otp', verified_phone: '9999999999', purpose: 'register' },
      publicTokenSecret('otp'), { expiresIn: '15m' });
    const wrong = await request(app).post('/api/register').send({ ...body, verified_token: otherPhone });
    expect(wrong.status).toBe(401);
  });
});

describe('#6 staff phone is unique across businesses', () => {
  test('the duplicate check is not scoped to the business', async () => {
    mockRequest.recordset = [{ id: 'other-business-user' }];
    const res = await request(app).post('/api/staff').set(authHeader())
      .send({ name: 'Bob', phone: '9876543210', pin: '4831' });
    expect(res.status).toBe(409);
    const sql = mockRequest.query.mock.calls[0][0];
    expect(sql).toMatch(/WHERE phone = @phone/);
    expect(sql).not.toMatch(/business_id/);
  });
});

// ── #10 void policy ─────────────────────────────────────────────────────────
describe('#10 voiding settled bills', () => {
  const yesterday = new Date(Date.now() - 36 * 60 * 60 * 1000);
  const bill = (over = {}) => ({
    id: BILL_ID, status: 'finalized', table_id: null, bill_number: 'INV-0042', total: 520,
    credit_collected: 0, inventory_enabled: false, settled_at: yesterday, ...over,
  });

  test('a cashier cannot void a settled bill from an earlier day', async () => {
    mockRequest.recordset = [bill()];
    const res = await request(app).delete(`/api/bills/${BILL_ID}`).set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(403);
  });

  test('a cashier can void today\'s bill', async () => {
    mockRequest.recordset = [bill({ settled_at: new Date() })];
    const res = await request(app).delete(`/api/bills/${BILL_ID}`).set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(200);
  });

  test('a cashier can cancel an old open order (draft)', async () => {
    mockRequest.recordset = [bill({ status: 'draft' })];
    const res = await request(app).delete(`/api/bills/${BILL_ID}`).set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(200);
  });

  test('the owner can void an old bill', async () => {
    mockRequest.recordset = [bill()];
    const res = await request(app).delete(`/api/bills/${BILL_ID}`).set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
  });
});

// ── #14 dev_otp ─────────────────────────────────────────────────────────────
describe('#14 dev_otp only in explicit development', () => {
  const whatsapp = require('../../src/whatsapp');
  const saved = process.env.NODE_ENV;
  afterEach(() => { process.env.NODE_ENV = saved; });

  test.each([
    ['test', false], ['production', false], ['', false], ['development', true],
  ])('NODE_ENV=%p → dev_otp exposed: %p', async (env, exposed) => {
    process.env.NODE_ENV = env;
    const result = await whatsapp.sendOtp('9876543210', 'forgot_pin');
    expect(result.dev_otp !== undefined).toBe(exposed);
  });
});

// ── #17 credit ledger ───────────────────────────────────────────────────────
describe('#17 credit ledger is for whoever collects money', () => {
  test.each(['server', 'kitchen'])('%s cannot list the credit ledger', async (role) => {
    const res = await request(app).get('/api/credit/customers').set(authHeader({ role }));
    expect(res.status).toBe(403);
  });
});
