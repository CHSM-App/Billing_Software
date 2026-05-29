/**
 * Creates a minimal mock of the mssql pool used in routes.
 *
 * Usage:
 *   const { mockPool, mockRequest } = makeDbMock();
 *   jest.mock('../../../src/db', () => mockPool);
 *
 * Set mockRequest.recordset / mockRequest.rowsAffected before each test
 * to control what the "DB" returns.
 */
function makeDbMock() {
  // Shared request stub — tests mutate .recordset / .rowsAffected as needed.
  const mockRequest = {
    inputs: {},
    recordset: [],
    rowsAffected: [1],
    // Accumulate .input() calls and return `this` for chaining
    input(name, _type, value) {
      this.inputs[name] = value;
      return this;
    },
    // Return a resolved promise with { recordset, rowsAffected }
    query: jest.fn(function () {
      return Promise.resolve({
        recordset: this.recordset,
        rowsAffected: this.rowsAffected,
      });
    }),
    reset() {
      this.inputs = {};
      this.recordset = [];
      this.rowsAffected = [1];
      this.query.mockClear();
    },
  };

  // Transaction stub
  const mockTransaction = {
    begin: jest.fn(() => Promise.resolve()),
    commit: jest.fn(() => Promise.resolve()),
    rollback: jest.fn(() => Promise.resolve()),
    request: jest.fn(() => ({ ...mockRequest })),
  };

  const mockPool = {
    pool: {
      request: jest.fn(() => mockRequest),
      transaction: jest.fn(() => mockTransaction),
    },
    poolConnect: Promise.resolve(),
    sql: {
      NVarChar: jest.fn(),
      UniqueIdentifier: jest.fn(),
      Bit: jest.fn(),
      Int: jest.fn(),
      Decimal: jest.fn(),
      DateTime2: jest.fn(),
    },
  };

  return { mockPool, mockRequest, mockTransaction };
}

module.exports = { makeDbMock };
