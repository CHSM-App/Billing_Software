const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');
const { authHeader } = require('../helpers/auth');

const ITEM_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const WARRANTY_ID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

const owner = () => authHeader({ role: 'owner' });
const cashier = () => authHeader({ role: 'cashier' });
const server = () => authHeader({ role: 'server' });

beforeEach(() => mockRequest.reset());

describe('GET /api/warranties', () => {
  test('returns a page of records, mapping extra_data from JSON', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordsets: [
        [{ total: 1 }],
        [{
          id: WARRANTY_ID,
          customer_name: 'Ramesh',
          customer_phone: '9876543210',
          item_id: ITEM_ID,
          item_name: 'MRF Tyre 155/65 R13',
          category: 'Tyres',
          bill_id: null,
          bill_item_id: null,
          serial_number: null,
          purchase_date: '2026-01-01',
          warranty_months: 60,
          expiry_date: '2031-01-01',
          extra_data: JSON.stringify([{ label: 'KM Reading', value: '12500' }]),
          notes: null,
          created_by_user_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          created_at: '2026-01-01T00:00:00.000Z',
        }],
      ],
    });

    const res = await request(app).get('/api/warranties').set(owner());
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(1);
    expect(res.body.items[0].extra_data).toEqual([{ label: 'KM Reading', value: '12500' }]);
  });

  test('search (?q) matches extra_data too, e.g. a vehicle number typed into a custom field', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordsets: [[{ total: 0 }], []] });
    await request(app).get('/api/warranties?q=MH12AB1234').set(owner());
    expect(mockRequest.inputs.q).toBe('%MH12AB1234%');
    const sql = mockRequest.query.mock.calls[0][0];
    expect(sql).toMatch(/extra_data LIKE @q/);
  });

  test('a server (no billing role) is refused — only cashier/owner manage warranties',
    async () => {
      const res = await request(app).get('/api/warranties').set(server());
      expect(res.status).toBe(403);
    });
});

describe('POST /api/warranties', () => {
  const create = (body, auth = cashier()) =>
    request(app).post('/api/warranties').set(auth).send(body);

  test('creates a manual record and computes expiry_date from months', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{
        id: WARRANTY_ID,
        customer_name: 'Ramesh',
        customer_phone: '9876543210',
        item_id: null,
        item_name: 'Exide Battery 35Ah',
        category: null,
        bill_id: null,
        bill_item_id: null,
        serial_number: 'SN-123',
        purchase_date: '2026-01-01',
        warranty_months: 24,
        expiry_date: '2028-01-01',
        extra_data: null,
        notes: null,
        created_by_user_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        created_at: '2026-01-01T00:00:00.000Z',
      }],
    });

    const res = await create({
      customer_name: 'Ramesh',
      customer_phone: '9876543210',
      item_name: 'Exide Battery 35Ah',
      serial_number: 'SN-123',
      purchase_date: '2026-01-01',
      warranty_months: 24,
    });

    expect(res.status).toBe(201);
    expect(res.body.item_name).toBe('Exide Battery 35Ah');
    expect(res.body.extra_data).toEqual([]);
  });

  test('a month-end purchase expires at the end of the target month', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [{ id: WARRANTY_ID }] });
    await create({
      customer_phone: '9876543210', item_name: 'Exide Battery 35Ah',
      purchase_date: '2026-01-31', warranty_months: 1,
    });
    // Not 3 March (setUTCMonth overflow).
    expect(mockRequest.inputs.expiry_date.toISOString().slice(0, 10)).toBe('2026-02-28');
  });

  test('rejects a missing customer phone', async () => {
    const res = await create({
      item_name: 'Exide Battery 35Ah',
      purchase_date: '2026-01-01',
      warranty_months: 24,
    });
    expect(res.status).toBe(400);
  });

  test('rejects a warranty period of zero', async () => {
    const res = await create({
      customer_phone: '9876543210',
      item_name: 'Exide Battery 35Ah',
      purchase_date: '2026-01-01',
      warranty_months: 0,
    });
    expect(res.status).toBe(400);
  });

  test('a server (no billing role) cannot create one', async () => {
    const res = await create({
      customer_phone: '9876543210',
      item_name: 'x',
      purchase_date: '2026-01-01',
      warranty_months: 12,
    }, server());
    expect(res.status).toBe(403);
  });
});

describe('DELETE /api/warranties/:id', () => {
  test('owner can delete', async () => {
    mockRequest.rowsAffected = [1];
    const res = await request(app).delete(`/api/warranties/${WARRANTY_ID}`).set(owner());
    expect(res.status).toBe(200);
  });

  test('cashier cannot delete — not a financial record, but still owner-gated', async () => {
    const res = await request(app).delete(`/api/warranties/${WARRANTY_ID}`).set(cashier());
    expect(res.status).toBe(403);
  });

  test('404 when nothing matched', async () => {
    mockRequest.rowsAffected = [0];
    const res = await request(app).delete(`/api/warranties/${WARRANTY_ID}`).set(owner());
    expect(res.status).toBe(404);
  });
});

describe('/api/warranty-field-templates', () => {
  test('GET lists templates for the business, parsing fields JSON', async () => {
    mockRequest.query.mockResolvedValueOnce({
      recordset: [{
        category: 'Tyres',
        fields: JSON.stringify([{ key: 'km_reading', label: 'KM Reading', type: 'number' }]),
      }],
    });
    const res = await request(app).get('/api/warranty-field-templates').set(owner());
    expect(res.status).toBe(200);
    expect(res.body).toEqual([
      { category: 'Tyres', fields: [{ key: 'km_reading', label: 'KM Reading', type: 'number' }] },
    ]);
  });

  test('PUT upserts a category template', async () => {
    const res = await request(app)
      .put('/api/warranty-field-templates/Tyres')
      .set(owner())
      .send({ fields: [{ key: 'km_reading', label: 'KM Reading', type: 'number' }] });
    expect(res.status).toBe(200);
  });

  test('PUT rejects an unsafe field key', async () => {
    const res = await request(app)
      .put('/api/warranty-field-templates/Tyres')
      .set(owner())
      .send({ fields: [{ key: 'KM Reading!', label: 'KM Reading', type: 'number' }] });
    expect(res.status).toBe(400);
  });

  test('PUT rejects an unknown field type', async () => {
    const res = await request(app)
      .put('/api/warranty-field-templates/Tyres')
      .set(owner())
      .send({ fields: [{ key: 'km_reading', label: 'KM Reading', type: 'bogus' }] });
    expect(res.status).toBe(400);
  });

  test('a cashier cannot manage templates — owner only', async () => {
    const res = await request(app)
      .put('/api/warranty-field-templates/Tyres')
      .set(cashier())
      .send({ fields: [] });
    expect(res.status).toBe(403);
  });

  test('DELETE removes a template', async () => {
    mockRequest.rowsAffected = [1];
    const res = await request(app)
      .delete('/api/warranty-field-templates/Tyres')
      .set(owner());
    expect(res.status).toBe(200);
  });
});
