// db.js must recover from a failed connect without a process restart: the old
// single `pool.connect()` promise stayed rejected forever after one timeout.

const mockConnect = jest.fn();

jest.mock('mssql', () => {
  class ConnectionPool {
    constructor() { this.connected = false; }
    on() {}
    connect() {
      return mockConnect().then(() => { this.connected = true; return this; });
    }
  }
  return { ConnectionPool };
});

const timeout = () => Object.assign(new Error('Failed to connect in 15000ms'), { code: 'ETIMEOUT' });

describe('db reconnect', () => {
  it('retries after a failed connect, sharing one attempt across callers', async () => {
    mockConnect
      .mockImplementationOnce(() => Promise.reject(timeout())) // eager startup attempt
      .mockImplementation(() => Promise.resolve());

    const { pool, poolConnect } = require('../../src/db');

    // Joins the failing startup attempt.
    await expect((async () => { await poolConnect; })()).rejects.toThrow('15000ms');
    expect(mockConnect).toHaveBeenCalledTimes(1);

    // DB is back: concurrent callers trigger exactly one new attempt.
    const results = await Promise.all(
      Array.from({ length: 20 }, async () => { await poolConnect; return pool.connected; }),
    );
    expect(results.every(Boolean)).toBe(true);
    expect(mockConnect).toHaveBeenCalledTimes(2);

    // Once connected, awaiting does not reconnect.
    await poolConnect;
    expect(mockConnect).toHaveBeenCalledTimes(2);
  });
});
