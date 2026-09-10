const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

// Rate limiters off, as in auth.test.js — this suite posts the form a dozen
// times to cover the validation branches and would otherwise trip demoLimiter's
// 10-per-hour cap partway through.
jest.mock('../../src/middleware/rateLimiter', () => ({
  healthLimiter: (req, res, next) => next(),
  whatsappLimiter: (req, res, next) => next(),
  globalLimiter: (req, res, next) => next(),
  loginLimiter: (req, res, next) => next(),
  registerLimiter: (req, res, next) => next(),
  refreshLimiter: (req, res, next) => next(),
  deletionLimiter: (req, res, next) => next(),
  demoLimiter: (req, res, next) => next(),
}));

// The route's whole job is to hand a validated payload to this template send.
const mockSendDemoRequest = jest.fn(() => Promise.resolve({ sent: true }));
jest.mock('../../src/whatsapp', () => ({
  sendOtp: jest.fn(),
  verifyOtp: jest.fn(),
  normalisePhone: (p) => String(p).replace(/\D/g, '').slice(-10),
  sendBillLink: jest.fn(),
  sendOnboardingAlert: jest.fn(),
  sendDemoRequest: (...args) => mockSendDemoRequest(...args),
}));

const app = require('../../src/server');

const VALID = {
  name: 'Ramesh Patil',
  mobile: '9876543210',
  businessType: 'Grocery / Kirana',
  date: '2026-09-15',
  time: '10:00 AM – 11:00 AM',
  usingSoftware: 'No',
};

const post = (over = {}) =>
  request(app).post('/api/demo/request').send({ ...VALID, ...over });

beforeEach(() => mockSendDemoRequest.mockClear());

describe('POST /api/demo/request', () => {
  it('accepts a valid booking and forwards every template variable', async () => {
    const res = await post();
    expect(res.status).toBe(201);
    expect(mockSendDemoRequest).toHaveBeenCalledWith({
      name: 'Ramesh Patil',
      mobile: '9876543210',
      businessType: 'Grocery / Kirana',
      date: '2026-09-15',
      time: '10:00 AM – 11:00 AM',
      currentSoftware: 'No',
    });
  });

  it('rejects a mobile number that is not a 10-digit Indian one', async () => {
    for (const mobile of ['12345', '1234567890', '98765432101', '']) {
      const res = await post({ mobile });
      expect(res.status).toBe(400);
    }
    expect(mockSendDemoRequest).not.toHaveBeenCalled();
  });

  it('rejects a missing name or missing slot', async () => {
    expect((await post({ name: '   ' })).status).toBe(400);
    expect((await post({ businessType: '' })).status).toBe(400);
    expect((await post({ date: '' })).status).toBe(400);
    expect((await post({ time: '' })).status).toBe(400);
    expect(mockSendDemoRequest).not.toHaveBeenCalled();
  });

  it('caps absurdly long fields instead of passing them to the template', async () => {
    const res = await post({ name: 'x'.repeat(500) });
    expect(res.status).toBe(400);
    expect(mockSendDemoRequest).not.toHaveBeenCalled();
  });

  it('fills in the optional software answer when it is left blank', async () => {
    const res = await post({ usingSoftware: '' });
    expect(res.status).toBe(201);
    expect(mockSendDemoRequest).toHaveBeenCalledWith(
      expect.objectContaining({ currentSoftware: 'Not specified' }));
  });

  it('still tells the visitor it worked when the provider is down', async () => {
    mockSendDemoRequest.mockResolvedValueOnce({ sent: false, error: 'provider 503' });
    const res = await post();
    // The form was filled in correctly; a provider outage is our problem, and
    // the failure is in the logs for a human to chase.
    expect(res.status).toBe(201);
  });
});
