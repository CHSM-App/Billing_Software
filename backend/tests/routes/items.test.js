const request = require('supertest');

// ------------------------------------------------------------------
// Mock DB before requiring the app
// ------------------------------------------------------------------
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

jest.mock('../../src/middleware/rateLimiter', () => ({
  loginLimiter: (req, res, next) => next(),
  registerLimiter: (req, res, next) => next(),
  refreshLimiter: (req, res, next) => next(),
  deletionLimiter: (req, res, next) => next(),
}));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const BUSINESS_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

const sampleItem = {
  id: ITEM_ID,
  business_id: BUSINESS_ID,
  name: 'Rice',
  barcode: '123456',
  category: 'Grains',
  price: 50.00,
  tax_rate: 5.00,
  stock_quantity: 100,
  is_active: 1,
  created_at: new Date().toISOString(),
};

beforeEach(() => {
  mockRequest.reset();
});

// ------------------------------------------------------------------
// Auth guard
// ------------------------------------------------------------------
describe('GET /api/items — auth guard', () => {
  test('returns 401 without a token', async () => {
    const res = await request(app).get('/api/items');
    expect(res.status).toBe(401);
  });

  test('returns 401 with a tampered token', async () => {
    const res = await request(app)
      .get('/api/items')
      .set('Authorization', 'Bearer bad.token.here');
    expect(res.status).toBe(401);
  });
});

// ------------------------------------------------------------------
// GET /api/items
// ------------------------------------------------------------------
describe('GET /api/items', () => {
  test('returns list of items', async () => {
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .get('/api/items')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0].name).toBe('Rice');
  });

  test('returns empty array when no items', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/items')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  test('filters by category query param', async () => {
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .get('/api/items?category=Grains')
      .set(authHeader());
    expect(res.status).toBe(200);
  });

  test('returns single item for barcode lookup', async () => {
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .get('/api/items?barcode=123456')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(ITEM_ID);
  });

  test('returns 404 when barcode not found', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get('/api/items?barcode=NOTFOUND')
      .set(authHeader());
    expect(res.status).toBe(404);
  });

  test('resolves a size (variant) barcode to its parent item', async () => {
    const VARIANT_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
    // Query order: (1) item lookup misses, (2) variant lookup hits,
    // (3) attachVariants for the parent item.
    mockRequest.query
      .mockImplementationOnce(() =>
        Promise.resolve({ recordset: [], rowsAffected: [0] }))
      .mockImplementationOnce(() =>
        Promise.resolve({
          recordset: [{ ...sampleItem, matched_variant_id: VARIANT_ID }],
          rowsAffected: [1],
        }))
      .mockImplementationOnce(() =>
        Promise.resolve({
          recordset: [
            { id: VARIANT_ID, item_id: ITEM_ID, label: 'Large', price: 80 },
          ],
          rowsAffected: [1],
        }));

    const res = await request(app)
      .get('/api/items?barcode=VARIANTCODE')
      .set(authHeader());

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(ITEM_ID);
    expect(res.body.matched_variant_id).toBe(VARIANT_ID);
    expect(res.body.variants).toHaveLength(1);
  });
});

// ------------------------------------------------------------------
// GET /api/items/categories
// ------------------------------------------------------------------
describe('GET /api/items/categories', () => {
  test('returns list of categories', async () => {
    mockRequest.recordset = [{ category: 'Grains' }, { category: 'Dairy' }];
    const res = await request(app)
      .get('/api/items/categories')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual(['Grains', 'Dairy']);
  });
});

// ------------------------------------------------------------------
// GET /api/items/top-sold
// ------------------------------------------------------------------
describe('GET /api/items/top-sold', () => {
  test('returns ordered item_ids', async () => {
    mockRequest.recordset = [{ item_id: ITEM_ID, total_qty: 50 }];
    const res = await request(app)
      .get('/api/items/top-sold')
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([ITEM_ID]);
  });
});

// ------------------------------------------------------------------
// GET /api/items/:id
// ------------------------------------------------------------------
describe('GET /api/items/:id', () => {
  test('returns item by id', async () => {
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .get(`/api/items/${ITEM_ID}`)
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(ITEM_ID);
  });

  test('returns 404 when item not found', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get(`/api/items/${ITEM_ID}`)
      .set(authHeader());
    expect(res.status).toBe(404);
  });
});

// ------------------------------------------------------------------
// POST /api/items — owner only
// ------------------------------------------------------------------
describe('POST /api/items', () => {
  test('creates item and returns 201', async () => {
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Rice');
  });

  test('persists hsn_code when provided', async () => {
    mockRequest.recordset = [{ ...sampleItem, hsn_code: '9963' }];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Thali', price: 120, tax_rate: 5, hsn_code: '9963' });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.hsn_code).toBe('9963');
    expect(res.body.hsn_code).toBe('9963');
  });

  test('binds hsn_code as null when omitted (unchanged behaviour)', async () => {
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.hsn_code).toBeNull();
  });

  test('returns 403 for non-owner role', async () => {
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'staff' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(403);
  });

  test('returns 400 when name is missing', async () => {
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ price: 50 });
    expect(res.status).toBe(400);
  });

  test('returns 400 when price is missing', async () => {
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice' });
    expect(res.status).toBe(400);
  });

  test('returns 400 for negative price', async () => {
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: -5 });
    expect(res.status).toBe(400);
  });
});

// ------------------------------------------------------------------
// PUT /api/items/:id
// ------------------------------------------------------------------
describe('PUT /api/items/:id', () => {
  test('updates item and returns updated record', async () => {
    // Calls: 1) ownership check, 2) update, 3) attachVariants
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ ...sampleItem, name: 'Basmati Rice' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Basmati Rice' });
    expect(res.status).toBe(200);
    expect(res.body.name).toBe('Basmati Rice');
    // Always present (empty for a plain item) so the client never has to guess.
    expect(res.body.variants).toEqual([]);
  });

  test('returns the item variants so a sized item stays sized', async () => {
    // Regression: this endpoint used to return the OUTPUT row with no `variants`
    // key. The client's Item.fromJson defaults that to [], so an edited sized
    // item dropped its sizes in the billing list and the next tap billed the
    // base price (Chicken 65 at 230 instead of half 180 / Full 280) until a
    // manual refresh restored it.
    const variantRows = [
      { id: 'v1', item_id: ITEM_ID, label: 'half', price: 180, barcode: null, sort_order: 0, is_active: true },
      { id: 'v2', item_id: ITEM_ID, label: 'Full', price: 280, barcode: null, sort_order: 1, is_active: true },
    ];
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ ...sampleItem, name: 'Chicken 65', price: 230 }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: variantRows, rowsAffected: [2] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ price: 230 });
    expect(res.status).toBe(200);
    expect(res.body.variants).toHaveLength(2);
    expect(res.body.variants.map((v) => v.label)).toEqual(['half', 'Full']);
  });

  test('returns 404 when item does not belong to business', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice' });
    expect(res.status).toBe(404);
  });

  test('returns 400 when no fields are provided', async () => {
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({});
    expect(res.status).toBe(400);
  });

  test('returns 403 for non-owner role', async () => {
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'staff' }))
      .send({ name: 'Rice' });
    expect(res.status).toBe(403);
  });
});

// ------------------------------------------------------------------
// DELETE /api/items/:id
// ------------------------------------------------------------------
describe('DELETE /api/items/:id', () => {
  test('soft-deletes item and returns success', async () => {
    // Call 1: snapshot SELECT before delete returns the item
    // Call 2: UPDATE soft-delete
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });

    const res = await request(app)
      .delete(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('returns 404 when item not found', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .delete(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }));
    expect(res.status).toBe(404);
  });

  test('returns 403 for non-owner role', async () => {
    const res = await request(app)
      .delete(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'staff' }));
    expect(res.status).toBe(403);
  });
});
