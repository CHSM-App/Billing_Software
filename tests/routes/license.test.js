const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const { authHeader } = require('../helpers/auth');
const app = require('../../src/server');

// A healthy subscription, joined with the business's own store toggle.
const baseRow = {
  status: 'active',
  expires_at: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000),
  max_offline_days: 30,
  grace_period_days: 5,
  allow_mobile: true,
  allow_desktop: true,
  allow_online_store: true,
  is_trial: false,
  updated_at: new Date(),
  store_enabled: true,
};

const row = (over = {}) => ({ ...baseRow, ...over });

const getLicense = () =>
  request(app).get('/api/license').set(authHeader({ role: 'owner' }));

beforeEach(() => mockRequest.reset());

describe('GET /api/license — effective store_enabled', () => {
  it('is true only when the owner toggle and the admin entitlement agree', async () => {
    mockRequest.recordset = [row()];
    const res = await getLicense();
    expect(res.status).toBe(200);
    expect(res.body.store_enabled).toBe(true);
    expect(res.body.allow_online_store).toBe(true);
  });

  it('is false when the owner turned the store off', async () => {
    mockRequest.recordset = [row({ store_enabled: false })];
    const res = await getLicense();
    expect(res.body.store_enabled).toBe(false);
    // The entitlement is still granted — Settings keeps the entry point so the
    // owner can switch the store back on.
    expect(res.body.allow_online_store).toBe(true);
  });

  it('is false when the admin revoked the entitlement, even with the toggle on', async () => {
    mockRequest.recordset = [row({ allow_online_store: false })];
    const res = await getLicense();
    expect(res.body.store_enabled).toBe(false);
    expect(res.body.allow_online_store).toBe(false);
  });

  it('treats a NULL entitlement (pre-migration-039 row) as granted', async () => {
    mockRequest.recordset = [row({ allow_online_store: null })];
    const res = await getLicense();
    expect(res.body.store_enabled).toBe(true);
    expect(res.body.allow_online_store).toBe(true);
  });
});
