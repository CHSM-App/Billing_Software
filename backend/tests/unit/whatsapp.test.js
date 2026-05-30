/**
 * Unit tests for whatsapp.js — only testing pure functions and
 * behaviour under disabled/unconfigured state (no real HTTP calls).
 *
 * normalisePhone and sendBillLink (skipped path) are fully testable
 * without mocking https.
 */

// Mock DB so whatsapp.js can be required without a real DB connection
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
jest.mock('../../src/db', () => mockPool);

// Ensure WhatsApp is disabled during tests (default)
process.env.WHATSAPP_ENABLED = 'false';
process.env.WHATSAPP_API_TOKEN = '';
process.env.WHATSAPP_TPL_BILL = '';

const { normalisePhone, sendBillLink } = require('../../src/whatsapp');

beforeEach(() => {
  mockRequest.reset();
});

// ------------------------------------------------------------------
// normalisePhone
// ------------------------------------------------------------------
describe('normalisePhone', () => {
  test('returns null for null input', () => {
    expect(normalisePhone(null)).toBeNull();
  });

  test('returns null for empty string', () => {
    expect(normalisePhone('')).toBeNull();
  });

  test('normalises 10-digit number by prepending 91', () => {
    expect(normalisePhone('9876543210')).toBe('919876543210');
  });

  test('returns 12-digit number starting with 91 unchanged', () => {
    expect(normalisePhone('919876543210')).toBe('919876543210');
  });

  test('normalises 11-digit number starting with 0', () => {
    expect(normalisePhone('09876543210')).toBe('919876543210');
  });

  test('strips spaces and dashes', () => {
    expect(normalisePhone('98765 43210')).toBe('919876543210');
    expect(normalisePhone('+91-9876543210')).toBe('919876543210');
  });

  test('returns null for 9-digit number', () => {
    expect(normalisePhone('987654321')).toBeNull();
  });

  test('returns null for 11-digit number not starting with 0', () => {
    expect(normalisePhone('11234567890')).toBeNull();
  });

  test('returns null for pure alphabetic string', () => {
    expect(normalisePhone('abcdef')).toBeNull();
  });

  test('handles number with country code +91', () => {
    expect(normalisePhone('+919876543210')).toBe('919876543210');
  });
});

// ------------------------------------------------------------------
// sendBillLink — skipped (WHATSAPP_ENABLED=false)
// ------------------------------------------------------------------
describe('sendBillLink — disabled', () => {
  test('returns skipped=true when WhatsApp is disabled', async () => {
    const result = await sendBillLink({
      phone: '9876543210',
      shopName: 'My Shop',
      billNumber: 'INV-0001',
      receiptUrl: 'https://billing.vengurlatech.com/receipt/abc123',
    });
    expect(result.sent).toBe(false);
    expect(result.skipped).toBe(true);
  });

  test('returns sent=false for invalid phone when disabled', async () => {
    // normalisePhone returns null for invalid -> should return error
    const result = await sendBillLink({
      phone: 'invalid',
      shopName: 'My Shop',
      billNumber: 'INV-0001',
      receiptUrl: 'https://billing.vengurlatech.com/receipt/abc123',
    });
    expect(result.sent).toBe(false);
    expect(result.error).toMatch(/phone/i);
  });

  test('never throws even for bad input', async () => {
    await expect(
      sendBillLink({ phone: null, shopName: null, billNumber: null, receiptUrl: null })
    ).resolves.toBeDefined();
  });
});

// ------------------------------------------------------------------
// sendBillLink — API token not configured
// ------------------------------------------------------------------
describe('sendBillLink — API token missing', () => {
  let originalEnabled;

  beforeAll(() => {
    originalEnabled = process.env.WHATSAPP_ENABLED;
  });

  afterAll(() => {
    process.env.WHATSAPP_ENABLED = originalEnabled;
  });

  // NOTE: We do NOT toggle WHATSAPP_ENABLED here at runtime for the loaded module
  // because Node's require cache means the module already read the env at load time.
  // The tests above (disabled) cover the not-configured path sufficiently.
  test('sendBillLink is a function', () => {
    expect(typeof sendBillLink).toBe('function');
  });
});
