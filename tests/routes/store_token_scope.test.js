const request = require('supertest');
const jwt = require('jsonwebtoken');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));

const app = require('../../src/server');

const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

// Exactly what POST /store/:token/verify-otp hands a customer once they have
// entered the OTP sent to their own phone (signStoreToken in public_store.js).
// Any member of the public can obtain one of these for any live storefront.
const customerStoreToken = () => jwt.sign(
  { typ: 'store', phone: '919876543210', business_id: BUSINESS_ID },
  process.env.JWT_ACCESS_SECRET,
  { expiresIn: '4h' },
);

// The table-QR equivalent (signOrderToken in public_order.js).
const customerOrderToken = () => jwt.sign(
  { typ: 'order', phone: '919876543210', table_id: 'tttttttt-tttt-tttt-tttt-tttttttttttt' },
  process.env.JWT_ACCESS_SECRET,
  { expiresIn: '4h' },
);

beforeEach(() => mockRequest.reset());

// ---------------------------------------------------------------------------
// A customer-facing token must NEVER authenticate a staff API. Both are signed
// with JWT_ACCESS_SECRET, so the only thing separating them is whatever
// requireAuth checks beyond the signature.
// ---------------------------------------------------------------------------
describe('customer store/order tokens are rejected by the staff API', () => {
  const STAFF_ENDPOINTS = [
    ['get', '/api/items'],
    ['get', '/api/bills'],
    ['get', '/api/credit/customers'],
    ['get', '/api/online-orders'],
    ['get', '/api/bills/customers/search?q=a'],
  ];

  it.each(STAFF_ENDPOINTS)('%s %s rejects a store token', async (method, path) => {
    const res = await request(app)[method](path)
      .set('Authorization', `Bearer ${customerStoreToken()}`);
    expect(res.status).toBe(401);
  });

  it.each(STAFF_ENDPOINTS)('%s %s rejects an order token', async (method, path) => {
    const res = await request(app)[method](path)
      .set('Authorization', `Bearer ${customerOrderToken()}`);
    expect(res.status).toBe(401);
  });
});
