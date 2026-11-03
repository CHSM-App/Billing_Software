// upsertCustomer runs after a bill commits and is never awaited — it must
// never reject, or an unhandled rejection could take the server down.
const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
jest.mock('../../src/db', () => mockPool);

const {
  upsertCustomer, syncCustomers, canonicalPhone, billPhoneMatch,
  customersAllowed, forgetCustomersAccess,
} = require('../../src/customers');

describe('customersAllowed (admin entitlement, migration 048)', () => {
  test('no subscription row → allowed (enabled by default)', async () => {
    mockRequest.recordset = [];
    expect(await customersAllowed('AAAA-1')).toBe(true);
  });

  test('switched off → refused, and cached across id casing', async () => {
    mockRequest.recordset = [{ allow_customers: false }];
    expect(await customersAllowed('BBBB-2')).toBe(false);
    mockRequest.recordset = [{ allow_customers: true }];
    expect(await customersAllowed('bbbb-2')).toBe(false); // still cached
    expect(mockRequest.query).toHaveBeenCalledTimes(1);
  });

  test('an admin change clears the cache so it applies at once', async () => {
    mockRequest.recordset = [{ allow_customers: true }];
    expect(await customersAllowed('CCCC-3')).toBe(true);
    forgetCustomersAccess('cccc-3');
    mockRequest.recordset = [{ allow_customers: false }];
    expect(await customersAllowed('CCCC-3')).toBe(false);
  });
});

// The billing app saves 9876543210; the online store / QR orders save
// 919876543210. One person, one customer. (SQL dbo.canonical_phone, migration
// 047, must give the same answers.)
test.each([
  ['9876543210', '9876543210'],
  ['919876543210', '9876543210'],
  ['+919876543210', '9876543210'],
  ['+91 98765 43210', '9876543210'],
  ['09876543210', '9876543210'],
  ['  98765-43210 ', '9876543210'],
  ['447700900123', '447700900123'], // not Indian — left as digits
])('canonicalPhone(%s) → %s', (raw, want) => {
  expect(canonicalPhone(raw)).toBe(want);
});

test('billPhoneMatch finds a bill saved in any of the stored formats', () => {
  const sql = billPhoneMatch('c.phone');
  for (const f of ["c.phone", "'91' + c.phone", "'+91' + c.phone", "'0' + c.phone", "'+91 ' + c.phone"]) {
    expect(sql).toContain(f);
  }
  expect(sql.startsWith('b.customer_phone IN (')).toBe(true);
});

test('upsert stores the canonical number, so store and billing customers merge', async () => {
  await upsertCustomer('b-1', '919876543210', 'Asha');
  expect(mockRequest.inputs.phone).toBe('9876543210');
});

beforeEach(() => mockRequest.reset());

test('a DB error is swallowed, never thrown', async () => {
  mockRequest.query.mockRejectedValueOnce(new Error('deadlock'));
  await expect(upsertCustomer('b-1', '9876543210', 'Asha')).resolves.toBeUndefined();
});

test('a blank phone does nothing', async () => {
  await upsertCustomer('b-1', '   ', 'Asha');
  expect(mockRequest.query).not.toHaveBeenCalled();
});

test('trims the phone and stores a blank name as null', async () => {
  await upsertCustomer('b-1', ' 9876543210 ', '  ');
  expect(mockRequest.inputs.phone).toBe('9876543210');
  expect(mockRequest.inputs.name).toBeNull();
});

test('sync is throttled per business, and a failed sync retries next time', async () => {
  mockRequest.query.mockRejectedValueOnce(new Error('timeout'));
  await expect(syncCustomers('b-2')).rejects.toThrow('timeout');
  await syncCustomers('b-2');                       // retried, succeeds
  await syncCustomers('b-2');                       // throttled
  expect(mockRequest.query).toHaveBeenCalledTimes(2);
});
