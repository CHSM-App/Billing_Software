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
    // The customer sees the number without the business's bill prefix.
    expect(res.text).toContain('0001');
    expect(res.text).not.toContain('INV-');
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

  test('HTML shows "Cashier" with the full name', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...sampleBillRow, billed_by: ' Ramesh  Patil ' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).toContain('Cashier');
    expect(res.text).toContain('Ramesh Patil');
  });

  test('HTML omits "Cashier" when the biller is unknown', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).not.toContain('Cashier');
  });

  // unit_price is stored discounted; the receipt shows the rate before the
  // line discount and notes the discount on the name (2 × 180 less 50).
  test('a discounted line shows its pre-discount rate and "(Disc ₹x)"', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [{ item_name: 'Chilli Paneer', quantity: 2, unit_price: 155, line_total: 310, discount_amount: 50 }],
        rowsAffected: [1],
      });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).toContain('Chilli Paneer (Disc &#8377;50.00)');
    expect(res.text).toMatch(/col-rate">&#8377;180\.00/);
    expect(res.text).not.toMatch(/col-rate">&#8377;155\.00/);
    expect(res.text).toMatch(/col-amt">&#8377;310\.00/);
  });

  test.each([0, null, undefined])('discount_amount %p prints no "(Disc" note', async (disc) => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [{ item_name: 'Rice', quantity: 2, unit_price: 50, line_total: 100, discount_amount: disc }],
        rowsAffected: [1],
      });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).not.toContain('(Disc');
    expect(res.text).toMatch(/col-rate">&#8377;50\.00/);
  });

  test('a zero-quantity line falls back to unit_price for the rate', async () => {
    mockRequest.query
      // round_off set: the shared row lacks it, which prints its own NaN.
      .mockResolvedValueOnce({ recordset: [{ ...sampleBillRow, round_off: 0 }], rowsAffected: [1] })
      .mockResolvedValueOnce({
        recordset: [{ item_name: 'Rice', quantity: 0, unit_price: 50, line_total: 0, discount_amount: 5 }],
        rowsAffected: [1],
      });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.status).toBe(200);
    expect(res.text).not.toContain('NaN');
    expect(res.text).not.toContain('Infinity');
    expect(res.text).toMatch(/col-rate">&#8377;50\.00/);
  });

  test('the biller name is HTML-escaped', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...sampleBillRow, billed_by: '<b>Eve</b> X' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).not.toContain('<b>Eve</b>');
    expect(res.text).toContain('&lt;b&gt;Eve&lt;/b&gt;');
  });

  test('a blank biller name omits "Cashier"', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...sampleBillRow, billed_by: '   ' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).not.toContain('Cashier');
  });

  test('the bill query falls back from settler to creator', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });
    await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(mockRequest.query.mock.calls[0][0]).toMatch(/COALESCE\(fu\.name, cu\.name\) AS billed_by/);
    expect(mockRequest.query.mock.calls[1][0]).toMatch(/bi\.discount_amount/);
    // Lines print grouped by menu category, not by name.
    expect(mockRequest.query.mock.calls[1][0]).toMatch(/LEFT JOIN items it ON it\.id = bi\.item_id/);
    expect(mockRequest.query.mock.calls[1][0]).toMatch(/ORDER BY[\s\S]*it\.major_category[\s\S]*it\.category[\s\S]*bi\.item_name/);
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

  test('GST off: tax ignored entirely — no tax rows, grand total excludes tax', async () => {
    // A bill carrying a leftover tax_amount from when GST was on, but the
    // business toggle is now off. Tax is ignored ENTIRELY: no Tax/CGST/SGST row
    // and the grand total drops the tax, so the shared receipt link matches the
    // net payable shown on the order card and the printed receipt.
    const taxedBill = { ...sampleBillRow, tax_amount: 5, total: 105 };
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [taxedBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });

    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.status).toBe(200);
    expect(res.text).not.toContain('>Tax<');
    expect(res.text).not.toContain('>CGST<');
    expect(res.text).not.toContain('GST Summary');
    // total 105 − tax 5 = 100 payable (no discount/round-off on this bill).
    expect(res.text).toContain('&#8377;100.00');
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

// A link shared from a device printing A4/A5 (?p=a4|a5) opens the same
// invoice layout the app prints, not the thermal-style card.
describe('GET /receipt/:token?p=a4|a5', () => {
  const gstBill = { ...sampleBillRow, subtotal: 347.46, tax_amount: 62.54, total: 410, gst_enabled: true, billed_by: 'Sagar D' };
  const gstItems = [
    { item_name: 'Bira 91 White (Pint 330 ml)', quantity: 1, unit_price: 161.02, line_total: 190, tax_rate: 18 },
    { item_name: 'Bira 91 White (Can 500 ml)', quantity: 1, unit_price: 186.44, line_total: 220, tax_rate: 18 },
  ];

  test.each(['a4', 'a5'])('%s renders the tax invoice', async (p) => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [gstBill], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: gstItems, rowsAffected: [1] });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}?p=${p}`);
    expect(res.status).toBe(200);
    expect(res.text).toContain('Tax Invoice');
    expect(res.text).toContain('Four Hundred Ten Rupees only');
    expect(res.text).toContain('Rs.31.27'); // CGST / SGST halves
    expect(res.text).toContain('Rs.410.00');
    expect(res.text).toContain(`size:${p.toUpperCase()}`);
    expect(res.text).not.toContain('top-bar');
  });

  test('an unknown p falls back to the card receipt', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [sampleBillRow], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}?p=mm80`);
    expect(res.text).toContain('top-bar');
  });
});

describe('amountToWords', () => {
  const { amountToWords } = require('../../src/invoiceHtml');
  test.each([
    [0, 'Zero Rupees only'],
    [24072, 'Twenty Four Thousand Seventy Two Rupees only'],
    [100000, 'One Lakh Rupees only'],
    [1234.5, 'One Thousand Two Hundred Thirty Four Rupees and Fifty Paise only'],
    [12345678, 'One Crore Twenty Three Lakh Forty Five Thousand Six Hundred Seventy Eight Rupees only'],
  ])('%p → %s', (n, words) => expect(amountToWords(n)).toBe(words));
});

describe('GET /receipt/:token/pdf', () => {
  // The token ends up in a spawned browser's URL — anything off-alphabet must
  // be refused before a process starts.
  it('rejects a malformed token without launching a browser', async () => {
    const res = await request(app).get('/receipt/' + encodeURIComponent('a&b c<x>') + '/pdf');
    expect(res.status).toBe(404);
    const res2 = await request(app).get('/receipt/s/' + 'x'.repeat(17) + '/pdf');
    expect(res2.status).toBe(404);
  });
});

// Billing Setup (businesses.bill_settings, migration 061).
describe('GET /receipt/:token honours Billing Setup', () => {
  const custom = JSON.stringify({
    show_cashier: false, show_gstin: false, show_address: false, show_terms: false,
    show_bank: true, alt_phone: '02366-262626',
    show_note: true, note: 'Free home delivery',
    bank: { account_name: 'My Shop', account_no: '1234567890', bank_name: 'SBI', branch: 'Vengurla', ifsc: 'SBIN0001234' },
  });
  const row = {
    ...sampleBillRow, billed_by: 'Ramesh', gst_enabled: true,
    customer_address: 'Plot 5, Sawantwadi', customer_gstin: '27ABCDE1234F1Z5',
  };

  test.each([null, 'a4'])('NULL settings (p=%s): bill as before, no bank block', async (p) => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...sampleBillRow, billed_by: 'Ramesh', gst_enabled: true }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}${p ? `?p=${p}` : ''}`);
    expect(res.text).toContain('Cashier');
    expect(res.text).toContain('GSTIN123');
    expect(res.text).toContain('123 Main St');
    expect(res.text).toContain('Thank you!');
    expect(res.text).not.toContain('A/c No');
  });

  test.each([null, 'a4'])('saved settings (p=%s) hide/show the chosen parts', async (p) => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row, bill_settings: custom }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}${p ? `?p=${p}` : ''}`);
    expect(res.text).not.toContain('Cashier');
    expect(res.text).not.toContain('GSTIN123');
    expect(res.text).not.toContain('123 Main St');
    expect(res.text).not.toContain('Thank you!');
    expect(res.text).toContain('A/c No: 1234567890');
    expect(res.text).toContain('Bank Details');
    expect(res.text).toContain('Free home delivery');
    expect(res.text).toContain('Address: Plot 5, Sawantwadi');
    expect(res.text).toContain('9876500000, 02366-262626');
    expect(res.text).toContain('IFSC: SBIN0001234');
    expect(res.text).toContain('Plot 5, Sawantwadi');
    expect(res.text).toContain('27ABCDE1234F1Z5');
  });

  test('show_customer off hides the whole customer block', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ ...row, bill_settings: '{"show_customer":false}' }], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: sampleItems, rowsAffected: [1] });
    const res = await request(app).get(`/receipt/${RECEIPT_TOKEN}`);
    expect(res.text).not.toContain('Alice');
    expect(res.text).not.toContain('27ABCDE1234F1Z5');
  });
});
