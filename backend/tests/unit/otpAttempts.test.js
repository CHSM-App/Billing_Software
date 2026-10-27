// verifyOtp attempt cap (#9).
const crypto = require('crypto');
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
jest.mock('../../src/db', () => mockPool);

const { verifyOtp } = require('../../src/whatsapp');

const hash = (s) => crypto.createHash('sha256').update(s).digest('hex');
const LIVE = { id: '11111111-1111-1111-1111-111111111111', otp_hash: hash('482913') };

beforeEach(() => mockRequest.reset());

describe('verifyOtp (#9)', () => {
  test('no live code → false', async () => {
    mockRequest.query.mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    expect(await verifyOtp('9876543210', '482913', 'forgot_pin')).toBe(false);
  });

  test('a wrong guess is counted against the code, and retires it at the cap', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [LIVE], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });
    expect(await verifyOtp('9876543210', '000000', 'forgot_pin')).toBe(false);
    const sql = mockRequest.query.mock.calls[1][0];
    expect(sql).toMatch(/attempts = ISNULL\(attempts, 0\) \+ 1/);
    expect(sql).toMatch(/THEN 1 ELSE used END/);
  });

  test('the right code is consumed only while under the cap', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [LIVE], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [1] });
    expect(await verifyOtp('9876543210', '482913', 'forgot_pin')).toBe(true);
    expect(mockRequest.query.mock.calls[1][0]).toMatch(/ISNULL\(attempts, 0\) < @max/);
  });

  test('the right code after the cap was reached → false', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [LIVE], rowsAffected: [1] })
      .mockResolvedValueOnce({ recordset: [], rowsAffected: [0] });
    expect(await verifyOtp('9876543210', '482913', 'forgot_pin')).toBe(false);
  });
});
