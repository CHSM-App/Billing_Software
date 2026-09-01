const request = require('supertest');

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

const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const VARIANT_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const RM_ID = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

const owner = () => authHeader({ role: 'owner' });

/// Most of these routes check ownership before validating, so the item lookup
/// has to resolve for the request to reach the validation at all.
function itemExists() {
  mockRequest.query.mockResolvedValueOnce({
    recordset: [{ id: ITEM_ID }],
    rowsAffected: [1],
  });
}

beforeEach(() => {
  mockRequest.query.mockReset();
  mockRequest.reset();
  mockRequest.query.mockImplementation(function () {
    return Promise.resolve({
      recordset: this.recordset,
      rowsAffected: this.rowsAffected,
    });
  });
  jest.clearAllMocks();
});

// ------------------------------------------------------------------
// Prices and stock — the money columns
// ------------------------------------------------------------------
describe('validation — item price and stock', () => {
  test('rejects a negative price', async () => {
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'Rice', price: -5 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/price/i);
  });

  test('rejects a non-numeric price', async () => {
    // parseFloat('abc') is NaN, which binds to a DECIMAL without complaint on
    // some drivers — it must be rejected here, not discovered on the invoice.
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'Rice', price: 'abc' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/price/i);
  });

  test('rejects a price past what DECIMAL(10,2) can hold', async () => {
    // Would otherwise reach SQL Server as an arithmetic overflow → 500.
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'Rice', price: 1e12 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/too large/i);
  });

  test('rejects Infinity', async () => {
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'Rice', price: '1e999' });
    expect(res.status).toBe(400);
  });

  test('rejects negative stock', async () => {
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'Rice', price: 10, stock_quantity: -1 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/stock/i);
  });

  test('rejects a tax rate above 100%', async () => {
    // Fits DECIMAL(5,2) but is nonsense as a percentage.
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'Rice', price: 10, tax_rate: 999 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/tax/i);
  });

  test('rejects an unknown unit', async () => {
    // Unit drives g<->kg conversion when a recipe quantity is stored, so an
    // unknown value would silently skip it.
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'Rice', price: 10, unit: 'furlong' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/unit/i);
  });

  test('rejects an over-length name instead of truncating it', async () => {
    const res = await request(app).post('/api/items').set(owner())
      .send({ name: 'x'.repeat(201), price: 10 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/200 characters/i);
  });
});

// ------------------------------------------------------------------
// Variants — the PUT route previously validated nothing at all
// ------------------------------------------------------------------
describe('validation — variant fields', () => {
  test('rejects a negative variant price on create', async () => {
    const res = await request(app).post(`/api/items/${ITEM_ID}/variants`).set(owner())
      .send({ label: 'Full', price: -1 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/price/i);
  });

  test('rejects a blank variant label on create', async () => {
    const res = await request(app).post(`/api/items/${ITEM_ID}/variants`).set(owner())
      .send({ label: '   ', price: 10 });
    expect(res.status).toBe(400);
  });

  test('rejects a non-numeric sort_order', async () => {
    // Would bind as NaN to sql.Int and fail at the driver as a 500.
    const res = await request(app).post(`/api/items/${ITEM_ID}/variants`).set(owner())
      .send({ label: 'Full', price: 10, sort_order: 'first' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/whole number/i);
  });

  test('rejects a negative price on UPDATE', async () => {
    // This route had no validation at all — an edit could set what a create
    // would have refused.
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/variants/${VARIANT_ID}`).set(owner())
      .send({ price: -50 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/price/i);
  });

  test('rejects blanking a variant label on UPDATE', async () => {
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/variants/${VARIANT_ID}`).set(owner())
      .send({ label: '' });
    expect(res.status).toBe(400);
  });

  test('rejects an over-length variant label', async () => {
    const res = await request(app).post(`/api/items/${ITEM_ID}/variants`).set(owner())
      .send({ label: 'x'.repeat(51), price: 10 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/50 characters/i);
  });
});

// ------------------------------------------------------------------
// Recipe quantities
// ------------------------------------------------------------------
describe('validation — recipe quantities', () => {
  test('rejects a zero quantity', async () => {
    itemExists();
    const res = await request(app).put(`/api/items/${ITEM_ID}/recipe`).set(owner())
      .send({ rows: [{ raw_material_id: RM_ID, quantity: 0 }] });
    expect(res.status).toBe(400);
  });

  test('rejects a negative quantity', async () => {
    itemExists();
    const res = await request(app).put(`/api/items/${ITEM_ID}/recipe`).set(owner())
      .send({ rows: [{ raw_material_id: RM_ID, quantity: -2 }] });
    expect(res.status).toBe(400);
  });

  test('rejects a non-numeric quantity', async () => {
    itemExists();
    const res = await request(app).put(`/api/items/${ITEM_ID}/recipe`).set(owner())
      .send({ rows: [{ raw_material_id: RM_ID, quantity: 'a lot' }] });
    expect(res.status).toBe(400);
  });

  test('rejects a quantity past what DECIMAL(12,4) can hold', async () => {
    itemExists();
    const res = await request(app).put(`/api/items/${ITEM_ID}/recipe`).set(owner())
      .send({ rows: [{ raw_material_id: RM_ID, quantity: 1e12 }] });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/too large/i);
  });

  test('accepts a small fractional quantity (a 0.005 kg pinch)', async () => {
    // Migration 020 widened the column to DECIMAL(12,4) for exactly this.
    itemExists();
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ id: RM_ID }],
      rowsAffected: [1],
    });
    const res = await request(app).put(`/api/items/${ITEM_ID}/recipe`).set(owner())
      .send({ rows: [{ raw_material_id: RM_ID, quantity: 0.005 }] });
    expect(res.status).toBe(200);
  });
});

// ------------------------------------------------------------------
// Raw materials
// ------------------------------------------------------------------
describe('validation — raw materials', () => {
  test('rejects negative stock on create', async () => {
    const res = await request(app).post('/api/raw-materials').set(owner())
      .send({ name: 'Rice', unit: 'kg', stock_quantity: -5 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/stock/i);
  });

  test('rejects an unknown unit on create', async () => {
    const res = await request(app).post('/api/raw-materials').set(owner())
      .send({ name: 'Rice', unit: 'sack' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/unit/i);
  });

  test('rejects negative stock on UPDATE', async () => {
    const res = await request(app).put(`/api/raw-materials/${RM_ID}`).set(owner())
      .send({ stock_quantity: -1 });
    expect(res.status).toBe(400);
  });

  test('rejects a non-numeric low stock alert', async () => {
    const res = await request(app).post('/api/raw-materials').set(owner())
      .send({ name: 'Rice', unit: 'kg', low_stock_threshold: 'lots' });
    expect(res.status).toBe(400);
  });
});
