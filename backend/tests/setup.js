// Set test environment before any modules load
process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-32-chars-long!!';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-32-chars-lon!';
process.env.DB_HOST = 'localhost';
process.env.DB_PORT = '1433';
process.env.DB_USER = 'test';
process.env.DB_PASSWORD = 'test';
process.env.DB_NAME = 'test';
process.env.PORT = '0';
process.env.CORS_ORIGINS = 'http://localhost:3000';
// Never send real WhatsApp messages from a test run. dotenv does not override a
// variable that is already set, so this beats WHATSAPP_ENABLED=true in a dev
// machine's backend/.env (which carries a live SMSala token).
process.env.WHATSAPP_ENABLED = 'false';
process.env.WHATSAPP_API_TOKEN = '';
// Same for push notifications: without this, a dev machine's real service
// account made route suites call Firebase. Suites that test fcm.js set their
// own value and mock firebase-admin.
process.env.FIREBASE_SERVICE_ACCOUNT = '';

// requireAuth consults authState (is the user still active, still paid up?).
// Route suites queue their DB results in order, so a real lookup would shift
// every queued result by one. Here it answers "state unknown" — the token alone
// decides, as before. tests/unit/authState.test.js exercises the real module.
jest.mock('../src/authState', () => ({
  cached: () => null,
  load: () => Promise.resolve(null),
  forgetUser: () => {},
  forgetBusiness: () => {},
}));
