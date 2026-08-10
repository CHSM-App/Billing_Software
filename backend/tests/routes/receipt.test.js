const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

const app = require('../../src/server');

const RECEIPT_TOKEN = 'abcdef1234567890';

const sampleBillRow = {
  bill_number: 'INV-0001',
  customer_name: 'Alice',
  customer_phone: '9876543210',
  subtotal: 100.00,
  total: 100.00,
  payment_mode: 'cash',
  created_at: new Date('2024-01-15T10:00:00Z'),
  shop_name: 'My Shop',
  address: '123 Main St',
  shop_phone: '9876500000',
  shop_email: 'shop@example.com',
  city: 'Vengurla',
  state: 'Goa',
  pincode: '416516',
  gst_number: 'GSTIN123',
  logo_url: null,
  bill_footer_note: 'Thank you!',
};

const sampleItems = [
  { item_name: 'Rice', quantity: 2, unit_price: 50, line_total: 100 },
];

beforeEach(() => {
  mockRequest.reset();
});

// ------------------------------------------------------------------
// GET /receipt/:token — public route, no auth needed
// ------------------------------------------------------------------
describe('GET /receipt/:token', () => {
  test('returns 200 with HTML for valid token', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text).toContain('My Shop');
    expect(res.text).toContain('INV-0001');
  });

  test('returns 404 for unknown token', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    const res = await request(app).get('/receipt/unknowntoken');
    expect(res.status).toBe(404);
    expect(res.text).toContain('not found');
  });

  test('HTML includes customer name when present', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).toContain('Alice');
  });

  test('HTML includes item details', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).toContain('Rice');
    expect(res.text).toContain('100.00');
  });

  test('HTML includes shop address', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).toContain('Vengurla');
    expect(res.text).toContain('GSTIN123');
  });

  test('HTML works without customer info', async () => {
    const billWithoutCustomer = { ...sampleBillRow, customer_name: null, customer_phone: null };
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [billWithoutCustomer], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.status).toBe(200);
    expect(res.text).not.toContain('Billed To');
  });

  test('HTML does not contain emojis', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    // Common emojis that should not appear in a professional receipt
    expect(res.text).not.toMatch(/[\u{1F600}-\u{1F64F}]/u);
    expect(res.text).not.toMatch(/[\u{1F300}-\u{1F5FF}]/u);
  });

  test('HTML is mobile-responsive (has viewport meta)', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).toContain('viewport');
    expect(res.text).toContain('width=device-width');
  });

  test('sets Cache-Control header', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.headers['cache-control']).toMatch(/public/);
  });

  test('escapes HTML in shop name to prevent XSS', async () => {
    const xssBill = { ...sampleBillRow, shop_name: '<script>alert(1)</script>' };
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [xssBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).not.toContain('<script>');
    expect(res.text).toContain('&lt;script&gt;');
  });

  test('GST off (default): no CGST/SGST or GST Summary, renders as before', async () => {
    // A taxed bill but gst_enabled is falsy → single behaviour, no split.
    const taxedBill = { ...sampleBillRow, tax_amount: 5, total: 105 };
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [taxedBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.status).toBe(200);
    expect(res.text).toContain('>Tax<');
    expect(res.text).not.toContain('>CGST<');
    expect(res.text).not.toContain('GST Summary');
  });

  test('GST on: shows CGST/SGST split and a GST Summary', async () => {
    const gstBill = {
      ...sampleBillRow,
      tax_amount: 5, total: 105,
      gst_enabled: true, default_sac_code: '9963',
    };
    const gstItems = [
      { item_name: 'Thali', quantity: 2, unit_price: 50, tax_rate: 5, hsn_code: '9963', line_total: 105 },
    ];
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [gstBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: gstItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.status).toBe(200);
    expect(res.text).toContain('>CGST<');
    expect(res.text).toContain('>SGST<');
    expect(res.text).toContain('GST Summary');
    expect(res.text).toContain('GSTIN123');
    expect(res.text).toContain('9963');
    expect(res.text).not.toContain('>Tax<'); // combined Tax row replaced by the split
  });

  test('handles items with decimal quantities', async () => {
    const decimalItems = [{ item_name: 'Sugar', quantity: 1.5, unit_price: 40, line_total: 60 }];
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: decimalItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.status).toBe(200);
    expect(res.text).toContain('1.50');
  });
});
