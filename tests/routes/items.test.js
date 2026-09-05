const request = require('supertest');

// ------------------------------------------------------------------
// Mock DB before requiring the app
// ------------------------------------------------------------------
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

jest.mock('../../src/middleware/rateLimiter', () => ({
  healthLimiter: (req, res, next) => next(),
  whatsappLimiter: (req, res, next) => next(),
  globalLimiter: (req, res, next) => next(),
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

/// Creating an item (and renaming one) now runs a duplicate-name pre-check
/// first. Queue an empty result for it so a test can exercise whatever it is
/// actually about; without this the shared `recordset` answers the check too and
/// every save looks like a collision.
const nameIsFree = () =>
  mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

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
  // A create always checks the name first, so every test in this block needs
  // the name to come back free. The duplicate case has its own block below.
  beforeEach(nameIsFree);

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

  test('always returns a variants key so a new item is never variant-less', async () => {
    // Every other item-returning endpoint attaches variants. POST used to be the
    // odd one out, and a missing `variants` key is exactly what made a sized item
    // look plain on the billing screen and charge its base price.
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('variants');
    expect(Array.isArray(res.body.variants)).toBe(true);
  });

  test('persists major_category alongside category', async () => {
    mockRequest.recordset = [
      { ...sampleItem, major_category: 'Chinese', category: 'Chinese Starters' },
    ];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({
        name: 'Chilli Paneer',
        price: 180,
        major_category: 'Chinese',
        category: 'Chinese Starters',
      });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.major_category).toBe('Chinese');
    expect(mockRequest.inputs.category).toBe('Chinese Starters');
    expect(res.body.major_category).toBe('Chinese');
  });

  test('binds major_category as null when omitted (unchanged behaviour)', async () => {
    // The whole feature is additive: an item created the old way, with only a
    // category, must still insert cleanly and carry no major.
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50, category: 'Grains' });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.major_category).toBeNull();
    expect(mockRequest.inputs.category).toBe('Grains');
  });

  test('honours a supplied low_stock_threshold', async () => {
    // Regression: this was hardcoded to 50 in the INSERT, so a shop selling 5 kg
    // of rice alerted at the same level as one selling 500 packets.
    mockRequest.recordset = [{ ...sampleItem, low_stock_threshold: 5 }];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50, low_stock_threshold: 5 });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.low_stock_threshold).toBe(5);
  });

  test('defaults low_stock_threshold to 50 when omitted', async () => {
    mockRequest.recordset = [sampleItem];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.low_stock_threshold).toBe(50);
  });

  test('rejects a negative low_stock_threshold', async () => {
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50, low_stock_threshold: -1 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/low stock/i);
  });

  test('returns 409 (not 500) when the barcode is already taken', async () => {
    // SQL Server raises 2627/2601 on the unique barcode index. It used to fall
    // into the generic catch and surface as an unhelpful "Failed to create item".
    const dup = Object.assign(new Error('Violation of UNIQUE KEY constraint'), { number: 2627 });
    mockRequest.query.mockRejectedValueOnce(dup);
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50, barcode: '123456789012' });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/barcode/i);
  });

  test('allows a null price when the item has variants', async () => {
    // A sized item owns no price — each size carries one. has_variants is the
    // only signal at INSERT time, since the variants are POSTed straight after.
    mockRequest.recordset = [{ ...sampleItem, price: null }];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Chicken 65', has_variants: true });
    expect(res.status).toBe(201);
    expect(mockRequest.inputs.price).toBeNull();
    // Barcode and stock belong to the sizes too — never to the parent.
    expect(mockRequest.inputs.barcode).toBeNull();
    expect(mockRequest.inputs.stock_quantity).toBeNull();
  });

  test('rejects a missing price on a plain item', async () => {
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/price is required/i);
  });

  test('nulls a sized item\'s barcode and stock even when they are sent', async () => {
    mockRequest.recordset = [{ ...sampleItem, price: null }];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({
        name: 'Chicken 65',
        has_variants: true,
        price: 230,
        barcode: '123456789012',
        stock_quantity: 10,
      });
    expect(res.status).toBe(201);
    // The 230 base price is exactly what used to get billed when no size was
    // picked — a price that isn't on the menu.
    expect(mockRequest.inputs.price).toBeNull();
    expect(mockRequest.inputs.barcode).toBeNull();
    expect(mockRequest.inputs.stock_quantity).toBeNull();
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
    // Calls: 1) ownership check, 2) duplicate-name check, 3) update,
    // 4) attachVariants
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
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

  test('updates major_category on its own', async () => {
    // Grouping an existing item under a major is the common edit, and it must
    // satisfy the "at least one field" guard by itself.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [{ ...sampleItem, major_category: 'Chinese' }],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ major_category: 'Chinese' });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.major_category).toBe('Chinese');
    expect(res.body.major_category).toBe('Chinese');
  });

  test('leaves major_category alone when the field is omitted', async () => {
    // ownership check, duplicate-name check (a name IS sent), update, variants
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Basmati Rice' });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.major_category).toBeUndefined();
  });

  test('returns 404 when item does not belong to business', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice' });
    expect(res.status).toBe(404);
  });

  test('refuses to clear the price of an item that has no variants', async () => {
    // Billing falls back to the item price when a size has none, so a null here
    // on a plain item would surface as NaN on the invoice.
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ ...sampleItem, variant_count: 0 }],
      rowsAffected: [1],
    });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ price: null });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/variants/i);
  });

  test('allows clearing the price of an item that has variants', async () => {
    mockRequest.query
      .mockResolvedValueOnce({
        recordset: [{ ...sampleItem, variant_count: 2 }],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({
        recordset: [{ ...sampleItem, price: null }],
        rowsAffected: [1],
      })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ price: null });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.price).toBeNull();
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

// ------------------------------------------------------------------
// POST /api/items/:id/variants — duplicate barcode
// ------------------------------------------------------------------
describe('POST /api/items/:id/variants', () => {
  test('returns 409 (not 500) when the barcode is already used by another size', async () => {
    // The inline "add variants while creating an item" flow surfaces this error
    // straight to the cashier, so it has to be actionable — a bare 500 saying
    // "Failed to create variant" tells them nothing about what to fix.
    const dup = Object.assign(new Error('Violation of UNIQUE KEY constraint'), { number: 2601 });
    mockRequest.query
      // loadOwnedItem — the parent item exists and belongs to this business.
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      // The variant INSERT trips the unique barcode index.
      .mockRejectedValueOnce(dup);

    const res = await request(app)
      .post(`/api/items/${ITEM_ID}/variants`)
      .set(authHeader({ role: 'owner' }))
      .send({ label: 'Full', price: 280, barcode: '123456789012' });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/barcode/i);
  });
});

// ------------------------------------------------------------------
// Duplicate item names
//
// Two items with the same name are indistinguishable on the billing list, on a
// bill line and in a report, so the catalog refuses the second one. Deliberately
// NOT inside the POST describe above: these tests need the name check to find a
// match, so they must not get its nameIsFree() priming.
// ------------------------------------------------------------------
describe('duplicate item names', () => {
  test('POST rejects a name that already exists', async () => {
    // The shared recordset answers the name-check query with an existing row.
    mockRequest.recordset = [{ id: 'other-item-id' }];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/already exists/i);
  });

  test('POST compares trimmed and case-folded', async () => {
    // Otherwise "rice", "Rice " and "RICE" would each slip past the check.
    mockRequest.recordset = [{ id: 'other-item-id' }];
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: '  RiCe  ', price: 50 });
    expect(res.status).toBe(409);
    // The value handed to SQL is trimmed; the query lowercases both sides.
    expect(mockRequest.inputs.name).toBe('RiCe');
  });

  test('POST creates normally when the name is free', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(201);
  });

  test('PUT rejects renaming onto another item', async () => {
    mockRequest.query
      // ownership check
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      // duplicate-name check finds a DIFFERENT item already called that
      .mockResolvedValueOnce({
        recordset: [{ id: 'other-item-id' }],
        rowsAffected: [1],
      });
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Dal' });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/already exists/i);
  });

  test('PUT excludes the item itself, so re-saving its own name is fine', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      // The check excludes this id, so it finds nothing.
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice' });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.exclude_id).toBe(ITEM_ID);
  });

  test('PUT without a name skips the check entirely', async () => {
    // Only ownership, update and variants — no name means no collision to look
    // for, and an extra query here would desync every caller's expectations.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}`)
      .set(authHeader({ role: 'owner' }))
      .send({ price: 99 });
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.exclude_id).toBeUndefined();
  });

  test('a soft-deleted item does not reserve its name', async () => {
    // The check filters on is_active = 1, so a deleted "Rice" frees the name.
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] })
      .mockResolvedValueOnce({ recordset: [sampleItem], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app)
      .post('/api/items')
      .set(authHeader({ role: 'owner' }))
      .send({ name: 'Rice', price: 50 });
    expect(res.status).toBe(201);
  });
});
