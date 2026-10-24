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
