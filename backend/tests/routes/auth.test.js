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
jest.mock('../../src/middleware/rateLimiter', () => ({
  globalLimiter: (req, res, next) => next(),
  loginLimiter: (req, res, next) => next(),
  registerLimiter: (req, res, next) => next(),
  refreshLimiter: (req, res, next) => next(),
  deletionLimiter: (req, res, next) => next(),
}));

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
    pin: '1234',
    inventory_enabled: true,
    has_barcode_scanner: false,
  };

  test('returns 200 on valid registration', async () => {
    // First query inserts business and returns id; second inserts user
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: BUSINESS_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app).post('/api/register').send(validBody);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('accepts optional GSTIN/PAN/FSSAI and enables GST when a GSTIN is given', async () => {
    // Queries: 1) GSTIN duplicate check (none), 2) insert business, 3) insert user.
    mockRequest.query
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
    expect(res.body.error).toMatch(/business_type/i);
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

  test('returns 400 when phone or pin is missing', async () => {
    const res = await request(app).post('/api/login').send({ phone: OWNER_PHONE });
    expect(res.status).toBe(400);
  });

  test('returns 404 phone_not_found for an unknown phone', async () => {
    // Distinct from a wrong PIN (401) so the login screen can offer to register
    // this number instead of showing a generic "invalid credentials" error.
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .post('/api/login')
      .send({ phone: '0000000000', pin: '1234' });
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('phone_not_found');
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

  test('returns 401 and attempts_remaining for wrong PIN', async () => {
    const userRow = await makeUserRow();
    // Query 1: user lookup; Query 2: increment failed_attempts
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [userRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .post('/api/login')
      .send({ phone: OWNER_PHONE, pin: '9999' });
    expect(res.status).toBe(401);
    expect(res.body).toHaveProperty('attempts_remaining');
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
