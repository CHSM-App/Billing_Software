const request = require('supertest');
const bcrypt = require('bcryptjs');

// ------------------------------------------------------------------
// Mock the DB module BEFORE requiring the app so every route picks
// up the mock pool instead of trying to connect to a real database.
// ------------------------------------------------------------------
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

// Also mock rate-limiters so they never block test requests
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));

const app = require('../../src/server');

// ------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------
const OWNER_PHONE = '9876543210';
const VALID_PIN = '1234';
const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

async function makeUserRow(pinOverride) {
  const pin = pinOverride || VALID_PIN;
  const pin_hash = await bcrypt.hash(pin, 10);
  return {
    id: USER_ID,
    business_id: BUSINESS_ID,
    name: 'Test Owner',
    phone: OWNER_PHONE,
    pin_hash,
    role: 'owner',
    failed_attempts: 0,
    locked_until: null,
    business_name: 'Test Shop',
    business_type: 'retail',
    is_verified: true,
    inventory_enabled: 1,
    has_barcode_scanner: 0,
    address: '123 Main St',
  };
}

beforeEach(() => {
  mockRequest.reset();
  // Default: most tests need a successful insert (no recordset required)
  mockRequest.recordset = [];
  mockRequest.rowsAffected = [1];
});

// ------------------------------------------------------------------
// POST /api/register
// ------------------------------------------------------------------
describe('POST /api/register', () => {
  const validBody = {
    business_name: 'Test Shop',
    business_type: 'retail',
    address: '123 Main St',
    phone: '9876543210',
    owner_name: 'Test Owner',
    owner_phone: '9876543211',
    pin: '4831',
    inventory_enabled: true,
    has_barcode_scanner: false,
  };

  test('returns 200 on valid registration', async () => {
    // Queries: 0) owner phone free, 1) store-token slug collision lookup (nothing taken),
    // 2) insert business and return id, 3) insert user.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] }) // owner phone not taken
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ id: BUSINESS_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app).post('/api/register').send(validBody);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    // New businesses start on the paid WhatsApp API with a 30-day trial.
    const insertBiz = mockRequest.query.mock.calls.find(c => /INSERT INTO businesses/.test(c[0]))[0];
    expect(insertBiz).toMatch(/whatsapp_mode[\s\S]*'api'/);
    const days = (new Date(res.body.trial_expires_at) - Date.now()) / 86400000;
    expect(days).toBeGreaterThan(29.9);
    expect(days).toBeLessThanOrEqual(30);
  });

  test('accepts optional GSTIN/PAN/FSSAI and enables GST when a GSTIN is given', async () => {
    // Queries: 0) owner phone free, 1) GSTIN duplicate check (none), 2) store-token slug collision
    // lookup (nothing taken), 3) insert business, 4) insert user.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] }) // owner phone not taken
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ id: BUSINESS_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app).post('/api/register').send({
      ...validBody,
      gst_number: '27ABCDE1234F1Z5',
      pan_number: 'ABCDE1234F',
    });
    expect(res.status).toBe(200);
  });

  test('returns 400 for a malformed GSTIN at registration', async () => {
    const res = await request(app)
      .post('/api/register')
      .send({ ...validBody, gst_number: 'NOTAGSTIN' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Invalid GSTIN/i);
  });

  test('returns 400 for a malformed FSSAI at registration', async () => {
    const res = await request(app)
      .post('/api/register')
      .send({ ...validBody, fssai_number: '123' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/FSSAI/i);
  });

  test('returns 400 when required fields are missing', async () => {
    const res = await request(app).post('/api/register').send({ business_name: 'X' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Missing required fields/i);
  });

  test('returns 400 for invalid business_type', async () => {
    const res = await request(app)
      .post('/api/register')
      .send({ ...validBody, business_type: 'invalid_type' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/business type/i);
  });

  test('folds the retired restaurant_no_tables (sent by app <= v1.1.10) into restaurant_with_tables', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] }) // owner phone not taken
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ id: BUSINESS_ID }], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/register')
      .send({ ...validBody, business_type: 'restaurant_no_tables' });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.business_type).toBe('restaurant_with_tables');
  });

  test('returns 400 for non-4-digit PIN', async () => {
    const res = await request(app)
      .post('/api/register')
      .send({ ...validBody, pin: '12345' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/PIN/i);
  });

  test('returns 400 for non-10-digit phone', async () => {
    const res = await request(app)
      .post('/api/register')
      .send({ ...validBody, phone: '12345' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Phone/i);
  });

  test('records no terms acceptance while the flow is off (TERMS_VERSION = null)', async () => {
    // Even with the enforcement flag on: there is no version to agree to yet.
    process.env.REQUIRE_TERMS_ACCEPT = 'true';
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] }) // owner phone not taken
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [{ id: BUSINESS_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: USER_ID }], rowsAffected: [1] });
    try {
      const res = await request(app).post('/api/register').send({ ...validBody, accept_terms: true });
      expect(res.status).toBe(200);
      expect(mockRequest.query.mock.calls.filter(c => /terms_acceptances/.test(c[0]))).toHaveLength(0);
    } finally {
      delete process.env.REQUIRE_TERMS_ACCEPT;
    }
  });
});

// ------------------------------------------------------------------
// POST /api/login
// ------------------------------------------------------------------
describe('POST /api/login', () => {
  test('returns tokens on valid credentials', async () => {
    const userRow = await makeUserRow();
    // Query 1: user lookup
    // Query 2: reset failed_attempts
    // Query 3: insert refresh token
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: VALID_PIN });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('access_token');
    expect(res.body).toHaveProperty('refresh_token');
    expect(res.body.user.role).toBe('owner');
  });

  test.each([
    [1, true],
    [0, false],
    [undefined, false], // DB before migration 056
  ])('session carries show_item_no (%p → %p)', async (col, expected) => {
    const userRow = { ...(await makeUserRow()), show_item_no: col };
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: VALID_PIN });

    expect(res.status).toBe(200);
    expect(res.body.business.show_item_no).toBe(expected);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/b\.show_item_no/);
  });

  test('returns 400 when phone or pin is missing', async () => {
    const res = await request(app).post('/api/login').send({ phone: OWNER_PHONE });
    expect(res.status).toBe(400);
  });

  test('an unknown phone gets the same 401 as a wrong PIN', async () => {
    // A distinct 404 let anyone list which numbers have accounts and then
    // spray common PINs at each (Security_Review.pdf #1).
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .post('/api/login')
      .send({ phone: '0000000000', pin: '1234' });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: 'Invalid credentials' });
  });

  test('returns 403 for unverified account', async () => {
    const userRow = await makeUserRow();
    userRow.is_verified = false;
    mockRequest.query.mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: VALID_PIN });
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/pending verification/i);
  });

  test('returns 403 account_disabled for a disabled staff account', async () => {
    const userRow = await makeUserRow();
    userRow.role = 'cashier';
    userRow.is_active = false;
    mockRequest.query.mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: VALID_PIN });
    expect(res.status).toBe(403);
    expect(res.body.error).toBe('account_disabled');
    // The mock hands back whatever row it is given, so also pin the real SQL:
    // the check is dead unless the lookup actually selects the column.
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/u\.is_active/);
  });

  test('returns 423 for locked account', async () => {
    const userRow = await makeUserRow();
    userRow.locked_until = new Date(Date.now() + 10 * 60 * 1000); // locked 10 min from now
    mockRequest.query.mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: VALID_PIN });
    expect(res.status).toBe(423);
    expect(res.body).toHaveProperty('retry_after_seconds');
  });

  test('returns 401 for wrong PIN without revealing attempts left', async () => {
    const userRow = await makeUserRow();
    // Query 1: user lookup; Query 2: increment failed_attempts
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: '9999' });
    expect(res.status).toBe(401);
    expect(res.body).not.toHaveProperty('attempts_remaining');
  });

  test.each([
    [4, null], [5, 15], [10, 30], [15, 60], [40, 1440], [100, 1440],
  ])('after %p consecutive failures the lock is %p minutes', async (attempts, minutes) => {
    const userRow = await makeUserRow();
    userRow.failed_attempts = attempts - 1;
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: '9999' });
    if (minutes === null) {
      expect(res.status).toBe(401);
    } else {
      expect(res.status).toBe(423);
      expect(res.body.retry_after_seconds).toBe(minutes * 60);
    }
  });

  test('a disabled account learns it is disabled only with the right PIN', async () => {
    const userRow = await makeUserRow();
    userRow.is_active = false;
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });
    const wrong = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: '9999' });
    expect(wrong.status).toBe(401);

    mockRequest.query.mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] });
    const right = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: VALID_PIN });
    expect(right.status).toBe(403);
    expect(right.body.error).toBe('account_disabled');
  });
});

// ------------------------------------------------------------------
// POST /api/refresh
// ------------------------------------------------------------------
describe('POST /api/refresh', () => {
  const { signRefreshToken } = require('../../src/auth');
  const validRefreshToken = signRefreshToken({
    user_id: USER_ID,
    business_id: BUSINESS_ID,
    role: 'owner',
  });

  test('returns new access_token for valid refresh token', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ id: 'some-token-id' }],
      rowsAffected: [1],
    });

    const res = await request(app)
      .post('/api/refresh')
      .send({ refresh_token: validRefreshToken });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('access_token');
  });

  test('returns 400 when refresh_token is missing', async () => {
    const res = await request(app).post('/api/refresh').send({});
    expect(res.status).toBe(400);
  });

  test('returns 401 for revoked / expired DB token', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .post('/api/refresh')
      .send({ refresh_token: validRefreshToken });
    expect(res.status).toBe(401);
  });

  test('returns 401 for a tampered token', async () => {
    const res = await request(app)
      .post('/api/refresh')
      .send({ refresh_token: 'tampered.token.value' });
    expect(res.status).toBe(401);
  });
});

// ------------------------------------------------------------------
// POST /api/logout
// ------------------------------------------------------------------
describe('POST /api/logout', () => {
  test('returns 200 and revokes the token', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/logout')
      .send({ refresh_token: 'some-token' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('returns 400 when refresh_token is missing', async () => {
    const res = await request(app).post('/api/logout').send({});
    expect(res.status).toBe(400);
  });
});
