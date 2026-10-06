const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);
jest.mock('../../src/customers', () => ({
  ...jest.requireActual('../../src/customers'),
  upsertCustomer: jest.fn(() => Promise.resolve()),
  syncCustomers: jest.fn(() => Promise.resolve()),
  customersAllowed: jest.fn(async () => true),
}));
jest.mock('../../src/whatsapp', () => ({
  ...jest.requireActual('../../src/whatsapp'),
  sendCampaignMessage: jest.fn(async () => ({ sent: true, campaignId: 'c-1' })),
  sendBillLink: jest.fn(),
}));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');
const { sendCampaignMessage } = require('../../src/whatsapp');

const C1 = '11111111-1111-1111-1111-111111111111';
const C2 = '22222222-2222-2222-2222-222222222222';
const C3 = '33333333-3333-3333-3333-333333333333';
const owner = () => authHeader({ role: 'owner' });
const flush = () => new Promise((r) => setImmediate(r));

beforeEach(() => {
  mockRequest.reset();
  sendCampaignMessage.mockClear();
});

describe('access', () => {
  test.each(['cashier', 'server', 'kitchen'])('%s gets 403', async (role) => {
    const res = await request(app).get('/api/customers').set(authHeader({ role }));
    expect(res.status).toBe(403);
  });

  // Vittam admin switched the feature off for this business (migration 048).
  test.each([
    ['get', '/api/customers'],
    ['get', '/api/customers/ids'],
    ['get', `/api/customers/${C1}/bills`],
    ['put', `/api/customers/${C1}/opt-out`],
    ['post', '/api/customers/message'],
  ])('feature disabled by admin → 403 on %s %s, nothing queried or sent', async (method, path) => {
    const { customersAllowed } = require('../../src/customers');
    customersAllowed.mockResolvedValueOnce(false);
    const res = await request(app)[method](path).set(owner())
      .send({ opted_out: true, customer_ids: [C1], message: 'Hi' });
    expect(res.status).toBe(403);
    expect(res.body.error).toBe('customers_disabled');
    expect(mockRequest.query).not.toHaveBeenCalled();
    expect(sendCampaignMessage).not.toHaveBeenCalled();
  });
});

describe('GET /api/customers (paged, one round trip)', () => {
  const sqlOf = (i) => mockRequest.query.mock.calls[i][0];
  const reply = (counts, page) => ({ recordsets: [[counts], page], recordset: [counts] });

  test('counts and the page come back from a single query', async () => {
    mockRequest.query.mockResolvedValueOnce(reply(
      { total_all: 40, total: 12, total_eligible: 11 },
      [{ id: C1, name: 'Asha', phone: '9876543210', opted_out: 0,
        bill_count: 3, total_spend: 450, last_visit: '2026-10-01T10:00:00Z' }],
    ));
    const res = await request(app).get('/api/customers?limit=30&offset=0').set(owner());
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ total_all: 40, total: 12, total_eligible: 11, offset: 0, limit: 30 });
    expect(res.body.items[0]).toMatchObject({ id: C1, bill_count: 3, opted_out: false });
    expect(mockRequest.query).toHaveBeenCalledTimes(1);
    expect(sqlOf(0)).toMatch(/INTO #agg/);
    expect(sqlOf(0)).toMatch(/OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY/);
  });

  test('the catch-up sync does not hold the response', async () => {
    const { syncCustomers } = require('../../src/customers');
    let release;
    syncCustomers.mockImplementationOnce(() => new Promise((r) => { release = r; }));
    mockRequest.query.mockResolvedValueOnce(reply({ total_all: 0, total: 0, total_eligible: 0 }, []));
    const res = await request(app).get('/api/customers').set(owner());
    expect(res.status).toBe(200); // answered while the sync is still pending
    release();
  });

  test('filters, search and sort become bound SQL, not request text', async () => {
    mockRequest.query.mockResolvedValueOnce(reply({ total_all: 5, total: 5, total_eligible: 5 }, []));
    await request(app)
      .get('/api/customers?q=919876543210&min_visits=5&max_spend=2000&recency=inactive30'
        + '&offers=allowed&sort=visits&dir=asc')
      .set(owner());
    const q = sqlOf(0);
    expect(q).toContain('bill_count >= @min_visits');
    expect(q).toContain('total_spend <= @max_spend');
    expect(q).toContain('last_visit < DATEADD(day, -@recency_days, GETUTCDATE())');
    expect(q).toContain('opted_out = 0');
    expect(q).toMatch(/ORDER BY bill_count ASC, id/);
    expect(mockRequest.inputs).toMatchObject({
      min_visits: 5, max_spend: 2000, recency_days: 30, q_phone: '%9876543210%',
    });
  });

  test('a hostile sort or malformed number is ignored, never injected', async () => {
    mockRequest.query.mockResolvedValueOnce(reply({ total_all: 1, total: 1, total_eligible: 1 }, []));
    const res = await request(app)
      .get('/api/customers?sort=name;DROP TABLE bills&min_visits=1 OR 1=1')
      .set(owner());
    expect(res.status).toBe(200);
    expect(sqlOf(0)).toMatch(/ORDER BY total_spend DESC, id/);
    expect(sqlOf(0)).not.toContain('DROP TABLE bills');
    expect(sqlOf(0)).not.toContain('@min_visits');
  });

  test('limit=0 returns only the counts (no page statement)', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordsets: [[{ total_all: 9, total: 3, total_eligible: 3 }]] });
    const res = await request(app).get('/api/customers?limit=0&min_visits=2').set(owner());
    expect(res.body).toMatchObject({ items: [], total: 3 });
    expect(sqlOf(0)).not.toContain('FETCH NEXT');
  });

  test('ids returns every matching, messageable customer for "Select all"', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [{ id: C1 }, { id: C2 }] });
    const res = await request(app).get('/api/customers/ids?min_visits=5').set(owner());
    expect(res.body).toEqual({ ids: [C1, C2] });
    expect(sqlOf(0)).toContain('opted_out = 0');
  });
});

describe('GET /api/customers/:id/bills (paged, one round trip)', () => {
  test('lookup, page, total and items come from a single query', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordsets: [
      [{ phone: '9876543210' }],
      [{ total: 45 }],
      [{ id: 'b1', additional_charges: null }],
      [{ id: 'i1', bill_id: 'b1', item_name: 'Tea' }],
    ] });
    const res = await request(app).get(`/api/customers/${C1}/bills?limit=20&offset=20`).set(owner());
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ total: 45, offset: 20, limit: 20 });
    expect(res.body.items[0].items).toEqual([{ id: 'i1', bill_id: 'b1', item_name: 'Tea' }]);
    expect(mockRequest.query).toHaveBeenCalledTimes(1);
    expect(mockRequest.inputs).toMatchObject({ offset: 20, limit: 20 });
  });

  test('another business’s customer is not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordsets: [[{ phone: null }], [{ total: 0 }], [], []] });
    const res = await request(app).get(`/api/customers/${C1}/bills`).set(owner());
    expect(res.status).toBe(404);
  });
});

describe('PUT /api/customers/:id/opt-out', () => {
  test('rejects a non-boolean', async () => {
    const res = await request(app).put(`/api/customers/${C1}/opt-out`).set(owner()).send({ opted_out: 'yes' });
    expect(res.status).toBe(400);
  });

  test('another business’s customer is not found', async () => {
    mockRequest.rowsAffected = [0];
    const res = await request(app).put(`/api/customers/${C1}/opt-out`).set(owner()).send({ opted_out: true });
    expect(res.status).toBe(404);
  });

  test('opts a customer out', async () => {
    const res = await request(app).put(`/api/customers/${C1}/opt-out`).set(owner()).send({ opted_out: true });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.opted_out).toBe(1);
  });
});

describe('POST /api/customers/message', () => {
  const send = (body) => request(app).post('/api/customers/message').set(owner()).send(body);

  test('rejects an empty or over-long message', async () => {
    expect((await send({ customer_ids: [C1], message: '   ' })).status).toBe(400);
    expect((await send({ customer_ids: [C1], message: 'x'.repeat(501) })).status).toBe(400);
  });

  test('rejects missing or malformed ids', async () => {
    expect((await send({ customer_ids: [], message: 'Hi' })).status).toBe(400);
    expect((await send({ customer_ids: ['nope'], message: 'Hi' })).status).toBe(400);
  });

  test('queues only this shop’s reachable customers, once per real number', async () => {
    mockRequest.query
      // Recipients: C3 (opted out / other shop) is simply not returned; C2 is
      // the same person as C1 in another format.
      .mockResolvedValueOnce({ recordset: [
        { id: C1, phone: '9876543210', shop_name: 'Cafe' },
        { id: C2, phone: '919876543210', shop_name: 'Cafe' },
      ] })
      .mockResolvedValueOnce({ recordset: [{ used: 0 }] })                         // daily cap
      .mockResolvedValueOnce({ recordset: [{ id: 'm1', phone: '9876543210' }] })   // INSERT … OUTPUT
      .mockResolvedValue({ recordset: [], rowsAffected: [1] });                    // status updates

    const res = await send({ customer_ids: [C1, C2, C3], message: 'Diwali offer, 20% off' });
    expect(res.status).toBe(202);
    expect(res.body).toMatchObject({ queued: 1, skipped: 2 });

    await flush(); await flush();
    expect(sendCampaignMessage).toHaveBeenCalledTimes(1);
    expect(sendCampaignMessage).toHaveBeenCalledWith(
      { phone: '9876543210', shopName: 'Cafe', message: 'Diwali offer, 20% off' });
  });

  test('nobody reachable → 400, nothing sent', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [] });
    const res = await send({ customer_ids: [C3], message: 'Hi' });
    expect(res.status).toBe(400);
    expect(sendCampaignMessage).not.toHaveBeenCalled();
  });

  test('over the daily cap → 429, nothing queued', async () => {
    process.env.CAMPAIGN_DAILY_LIMIT = '5';
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [
        { id: C1, phone: '9876543210', shop_name: 'Cafe' },
        { id: C2, phone: '9123456780', shop_name: 'Cafe' },
      ] })
      .mockResolvedValueOnce({ recordset: [{ used: 4 }] });
    const res = await send({ customer_ids: [C1, C2], message: 'Hi' });
    delete process.env.CAMPAIGN_DAILY_LIMIT;
    expect(res.status).toBe(429);
    expect(res.body.remaining).toBe(1);
    expect(mockRequest.query).toHaveBeenCalledTimes(2);
  });
});

describe('GET /api/bills/customers/search (billing autocomplete)', () => {
  test('keeps the exact response fields installed apps read', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ customer_name: 'Asha', customer_phone: '9876543210', visits: 4, last_bill_at: '2026-10-01T10:00:00Z' }],
    });
    const res = await request(app).get('/api/bills/customers/search?q=as').set(authHeader({ role: 'cashier' }));
    expect(res.status).toBe(200);
    expect(Object.keys(res.body[0]).sort())
      .toEqual(['customer_name', 'customer_phone', 'last_bill_at', 'visits']);
  });

  test('a full 91-prefixed number finds the 10-digit customer', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [] });
    await request(app).get('/api/bills/customers/search?q=919876543210').set(authHeader({ role: 'cashier' }));
    expect(mockRequest.inputs.phone_like).toBe('%9876543210%');
  });
});

describe('campaignText (WhatsApp template variable)', () => {
  const { campaignText } = jest.requireActual('../../src/whatsapp');
  test('commas cannot split the variable, newlines are flattened', () => {
    const out = campaignText('Buy 1, get 1\nfree');
    expect(out).not.toMatch(/[,\n]/);
    expect(out).toBe('Buy 1‚ get 1 · free');
  });
});
