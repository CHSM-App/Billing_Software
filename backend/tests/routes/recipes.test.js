const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest, mockTransaction } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

jest.mock('../../src/middleware/rateLimiter', () => ({
  loginLimiter: (req, res, next) => next(),
  registerLimiter: (req, res, next) => next(),
  refreshLimiter: (req, res, next) => next(),
  deletionLimiter: (req, res, next) => next(),
}));

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const VARIANT_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const OTHER_VARIANT_ID = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const RM_ID = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

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

/// Captures every input bound inside the transaction, plus the SQL text, so a
/// test can assert what the DELETE/INSERT actually scoped to.
function captureTransaction() {
  const calls = [];
  mockTransaction.request.mockImplementation(() => {
    const inputs = {};
    return {
      inputs,
      input: jest.fn(function (name, _type, value) {
        inputs[name] = value;
        return this;
      }),
      query: jest.fn((sqlText) => {
        calls.push({ sql: sqlText, inputs });
        return Promise.resolve({ recordset: [], rowsAffected: [1] });
      }),
    };
  });
  return calls;
}

// ------------------------------------------------------------------
// Auth guards
// ------------------------------------------------------------------
describe('recipes — auth guards', () => {
  test('GET item recipe returns 401 without a token', async () => {
    const res = await request(app).get(`/api/items/${ITEM_ID}/recipe`);
    expect(res.status).toBe(401);
  });

  test('PUT item recipe returns 403 for a non-owner', async () => {
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/recipe`)
      .set(authHeader({ role: 'cashier' }))
      .send({ rows: [] });
    expect(res.status).toBe(403);
  });

  test('PUT variant recipe returns 403 for a non-owner', async () => {
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/variants/${VARIANT_ID}/recipe`)
      .set(authHeader({ role: 'cashier' }))
      .send({ rows: [] });
    expect(res.status).toBe(403);
  });

  test('PUT variant recipe returns 404 when the size is not on that item', async () => {
    mockRequest.query
      // loadOwnedItem — the item exists
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      // loadOwnedVariant — but the size belongs to a different item
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/variants/${VARIANT_ID}/recipe`)
      .set(authHeader({ role: 'owner' }))
      .send({ rows: [] });
    expect(res.status).toBe(404);
    expect(res.body.error).toMatch(/variant/i);
  });
});

// ------------------------------------------------------------------
// Write scoping — the guarantee that saving one recipe leaves others alone
// ------------------------------------------------------------------
describe('recipes — write scoping', () => {
  test('saving a size\'s recipe scopes the wipe to that size', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })   // item
      .mockResolvedValueOnce({ recordset: [{ id: VARIANT_ID }], rowsAffected: [1] }) // variant
      .mockResolvedValueOnce({ recordset: [{ id: RM_ID }], rowsAffected: [1] });     // raw material
    const calls = captureTransaction();

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/variants/${VARIANT_ID}/recipe`)
      .set(authHeader({ role: 'owner' }))
      .send({ rows: [{ raw_material_id: RM_ID, quantity: 0.15 }] });
    expect(res.status).toBe(200);

    const del = calls.find((c) => /DELETE FROM item_recipes/.test(c.sql));
    // Without the variant predicate this DELETE would wipe every OTHER size's
    // recipe (and the item-level rows) whenever one size was saved.
    expect(del.sql).toMatch(/variant_id/);
    expect(del.inputs.variant_id).toBe(VARIANT_ID);

    const ins = calls.find((c) => /INSERT INTO item_recipes/.test(c.sql));
    expect(ins.inputs.variant_id).toBe(VARIANT_ID);
    expect(ins.inputs.quantity).toBe(0.15);
  });

  test('saving an item-level recipe scopes the wipe to variant_id IS NULL', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: RM_ID }], rowsAffected: [1] });
    const calls = captureTransaction();

    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/recipe`)
      .set(authHeader({ role: 'owner' }))
      .send({ rows: [{ raw_material_id: RM_ID, quantity: 2 }] });
    expect(res.status).toBe(200);

    const del = calls.find((c) => /DELETE FROM item_recipes/.test(c.sql));
    expect(del.sql).toMatch(/variant_id IS NULL/);
    expect(del.inputs.variant_id).toBeNull();

    const ins = calls.find((c) => /INSERT INTO item_recipes/.test(c.sql));
    expect(ins.inputs.variant_id).toBeNull();
  });

  test('rejects a duplicate raw material with 400, not a unique-index 500', async () => {
    // loadOwnedItem runs first, so the item must resolve before validation.
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ id: ITEM_ID }],
      rowsAffected: [1],
    });
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/recipe`)
      .set(authHeader({ role: 'owner' }))
      .send({
        rows: [
          { raw_material_id: RM_ID, quantity: 1 },
          { raw_material_id: RM_ID, quantity: 2 },
        ],
      });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/only once/i);
  });

  test('rejects a non-positive quantity', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{ id: ITEM_ID }],
      rowsAffected: [1],
    });
    const res = await request(app)
      .put(`/api/items/${ITEM_ID}/recipe`)
      .set(authHeader({ role: 'owner' }))
      .send({ rows: [{ raw_material_id: RM_ID, quantity: 0 }] });
    expect(res.status).toBe(400);
  });
});

// ------------------------------------------------------------------
// Reads
// ------------------------------------------------------------------
describe('recipes — reads', () => {
  test('GET item recipe filters to variant_id IS NULL', async () => {
    mockRequest.recordset = [];
    const res = await request(app)
      .get(`/api/items/${ITEM_ID}/recipe`)
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.variant_id).toBeNull();
  });

  test('GET variant recipe filters to that size', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ id: ITEM_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [{ id: OTHER_VARIANT_ID }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });

    const res = await request(app)
      .get(`/api/items/${ITEM_ID}/variants/${OTHER_VARIANT_ID}/recipe`)
      .set(authHeader());
    expect(res.status).toBe(200);
    expect(mockRequest.inputs.variant_id).toBe(OTHER_VARIANT_ID);
  });
});
