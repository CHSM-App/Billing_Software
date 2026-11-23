const request = require('supertest');
const { makeDbMock } = require('../helpers/db');
const { mockPool } = makeDbMock();
jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
const app = require('../../src/server');

// ~200kb of rows — over the 100kb global JSON limit.
const big = { rows: Array.from({ length: 1500 }, (_, i) => ({ row: i + 2, name: 'Item number ' + i, price: 10, category: 'Some category text' })) };

test('item import accepts a body past the global 100kb limit', async () => {
  const res = await request(app).post('/admin/api/businesses/x/items/import').send(big);
  expect(res.status).toBe(401); // reached requireAdmin, not 413
});

test('other routes keep the 100kb limit', async () => {
  const res = await request(app).post('/api/auth/login').send(big);
  expect(res.status).toBe(413);
});
