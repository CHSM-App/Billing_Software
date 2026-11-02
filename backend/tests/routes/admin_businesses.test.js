// Admin dashboard business list: a business whose owner filled the
// account-deletion form carries its pending request.
process.env.ADMIN_JWT_SECRET = 'test-admin-secret';

const request = require('supertest');
const jwt = require('jsonwebtoken');
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
const app = require('../../src/server');

const adminAuth = () => ({
  Authorization: `Bearer ${jwt.sign({ typ: 'admin' }, process.env.ADMIN_JWT_SECRET)}`,
});

const row = (over = {}) => ({
  id: 'b1', name: 'Sharma Store', business_type: 'retail', phone: '9876543210',
  is_verified: 1, created_at: '2026-01-01T00:00:00Z',
  staff_count: 0, bill_count: 0, item_count: 0,
  deletion_requested_at: null, deletion_scheduled_for: null, deletion_reason: null,
  ...over,
});

beforeEach(() => mockRequest.reset());

describe('GET /admin/api/businesses — deletion request', () => {
  test('requires an admin session', async () => {
    const res = await request(app).get('/admin/api/businesses');
    expect(res.status).toBe(401);
  });

  test('no pending request → deletion_request is null', async () => {
    mockRequest.recordset = [row()];
    const res = await request(app).get('/admin/api/businesses').set(adminAuth());
    expect(res.status).toBe(200);
    expect(res.body.businesses[0].deletion_request).toBeNull();
  });

  test('a pending request is returned with dates and reason', async () => {
    mockRequest.recordset = [row({
      deletion_requested_at: '2026-10-01T10:00:00Z',
      deletion_scheduled_for: '2026-10-31T10:00:00Z',
      deletion_reason: 'Closing the shop',
    })];
    const res = await request(app).get('/admin/api/businesses').set(adminAuth());
    expect(res.body.businesses[0].deletion_request).toEqual({
      requested_at: '2026-10-01T10:00:00Z',
      scheduled_for: '2026-10-31T10:00:00Z',
      reason: 'Closing the shop',
    });
  });

  test('a request without a reason gives reason: null', async () => {
    mockRequest.recordset = [row({
      deletion_requested_at: '2026-10-01T10:00:00Z',
      deletion_scheduled_for: '2026-10-31T10:00:00Z',
    })];
    const res = await request(app).get('/admin/api/businesses').set(adminAuth());
    expect(res.body.businesses[0].deletion_request.reason).toBeNull();
  });

  test('only PENDING requests are joined', async () => {
    mockRequest.recordset = [];
    await request(app).get('/admin/api/businesses').set(adminAuth());
    expect(mockRequest.query.mock.calls[0][0])
      .toMatch(/LEFT JOIN account_deletion_requests adr\s+ON adr\.business_id = b\.id AND adr\.status = 'pending'/);
  });
});

describe('GET /admin/api/businesses — users with app version', () => {
  test('each business lists its own users, version null when never reported', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [row(), row({ id: 'b2', name: 'Other' })] })
      .mockResolvedValueOnce({ recordset: [
        { business_id: 'b1', name: 'Owner', phone: '9000000001', role: 'owner', is_active: 1, app_version: '1.1.15+28' },
        { business_id: 'b1', name: 'Cash', phone: '9000000002', role: 'cashier', is_active: 0, app_version: null },
      ] });
    const res = await request(app).get('/admin/api/businesses').set(adminAuth());
    expect(res.status).toBe(200);
    expect(res.body.businesses[0].users).toEqual([
      { name: 'Owner', phone: '9000000001', role: 'owner', is_active: true, app_version: '1.1.15+28' },
      { name: 'Cash', phone: '9000000002', role: 'cashier', is_active: false, app_version: null },
    ]);
    expect(res.body.businesses[1].users).toEqual([]);
  });
});

describe('admin — AI bill scanning per business', () => {
  const subRow = (over = {}) => row({
    sub_status: 'active', sub_expires_at: '2027-01-01T00:00:00Z', max_staff: 5,
    allow_purchase_scan: null, purchase_scan_limit: null,
    scans_month: 0, scans_failed_month: 0, ...over,
  });

  afterEach(() => { delete process.env.PURCHASE_SCAN_MONTHLY_LIMIT; });

  test('list shows this month\'s scans and treats NULL as blocked + default limit', async () => {
    process.env.PURCHASE_SCAN_MONTHLY_LIMIT = '100';
    mockRequest.recordset = [subRow({ scans_month: 23, scans_failed_month: 2 })];
    const res = await request(app).get('/admin/api/businesses').set(adminAuth());
    const b = res.body.businesses[0];
    expect(b.scans_month).toBe(23);
    expect(b.scans_failed_month).toBe(2);
    expect(b.default_scan_limit).toBe(100);
    expect(b.subscription).toMatchObject({
      allow_purchase_scan: false, purchase_scan_limit: 100, purchase_scan_limit_is_default: true,
    });
  });

  test('list reports a business-specific allowance', async () => {
    mockRequest.recordset = [subRow({ allow_purchase_scan: 1, purchase_scan_limit: 40 })];
    const res = await request(app).get('/admin/api/businesses').set(adminAuth());
    expect(res.body.businesses[0].subscription).toMatchObject({
      allow_purchase_scan: true, purchase_scan_limit: 40, purchase_scan_limit_is_default: false,
    });
    // Only successful scans are counted as usage.
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/ps\.status = 'ok'[\s\S]*AS scans_month/);
  });

  const put = (body) => request(app).put('/admin/api/businesses/b1').set(adminAuth()).send(body);
  const merge = () => mockRequest.query.mock.calls.find(([q]) => /MERGE subscriptions/.test(q));

  test('enables scanning and sets the free scans per month', async () => {
    mockRequest.recordset = [{ id: 'b1' }];
    const res = await put({ allow_purchase_scan: true, purchase_scan_limit: 50 });
    expect(res.status).toBe(200);
    expect(merge()[0]).toMatch(/allow_purchase_scan = @allow_purchase_scan/);
    expect(mockRequest.inputs.allow_purchase_scan).toBe(1);
    expect(mockRequest.inputs.purchase_scan_limit).toBe(50);
  });

  test('null resets the allowance to the default', async () => {
    mockRequest.recordset = [{ id: 'b1', purchase_scan_limit: 50, allow_purchase_scan: 1 }];
    const res = await put({ purchase_scan_limit: null });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.purchase_scan_limit).toBeNull();
    // Untouched switch keeps its current value.
    expect(mockRequest.inputs.allow_purchase_scan).toBe(1);
  });

  test('rejects a negative or fractional allowance', async () => {
    expect((await put({ purchase_scan_limit: -1 })).status).toBe(400);
    expect((await put({ purchase_scan_limit: 2.5 })).status).toBe(400);
    expect((await put({ purchase_scan_limit: '10' })).status).toBe(400);
  });

  test('blocking keeps the allowance as it was', async () => {
    mockRequest.recordset = [{ id: 'b1', purchase_scan_limit: 30, allow_purchase_scan: 1 }];
    await put({ allow_purchase_scan: false });
    expect(mockRequest.inputs.allow_purchase_scan).toBe(0);
    expect(mockRequest.inputs.purchase_scan_limit).toBe(30);
  });
});
