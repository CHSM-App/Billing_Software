// Low-stock push was a no-op before 3e7fffc4 and is live now; online-order
// pushes gained a per-user opt-out (migration 067). Pin who receives what.
process.env.FIREBASE_SERVICE_ACCOUNT = '{}';

const mockSend = jest.fn(() => Promise.resolve({ responses: [] }));
jest.mock('firebase-admin', () => ({
  apps: [],
  initializeApp: jest.fn(),
  credential: { cert: jest.fn() },
  messaging: () => ({ sendEachForMulticast: mockSend }),
}));

const { makeDbMock } = require('../helpers/db');
const { mockPool, mockRequest } = makeDbMock();
const { pool, sql } = mockPool;
const { sendLowStockNotification, sendOnlineOrderNotification } = require('../../src/fcm');

beforeEach(() => {
  mockRequest.reset();
  mockSend.mockClear();
});

describe('sendLowStockNotification', () => {
  test('targets only owners who kept low-stock alerts on', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ token: 't1' }] })
      .mockResolvedValueOnce({ recordset: [{ low_count: 5 }] });
    await sendLowStockNotification(pool, sql, 'b-1', [{ name: 'Sugar', remaining: 2 }]);

    const tokenSql = mockRequest.query.mock.calls[0][0];
    expect(tokenSql).toMatch(/u\.role = 'owner'/);
    expect(tokenSql).toMatch(/u\.notify_low_stock = 1/);
    const msg = mockSend.mock.calls[0][0];
    expect(msg.tokens).toEqual(['t1']);
    expect(msg.notification.title).toBe('Low stock — 5 items');
    // Replaces the previous one instead of stacking.
    expect(msg.android.notification.tag).toBe('low_stock');
  });

  test('nothing crossed, or nobody opted in → no push', async () => {
    await sendLowStockNotification(pool, sql, 'b-1', []);
    mockRequest.query.mockResolvedValueOnce({ recordset: [] });
    await sendLowStockNotification(pool, sql, 'b-1', [{ name: 'Sugar', remaining: 2 }]);
    expect(mockSend).not.toHaveBeenCalled();
  });

  test('a failed total count still sends, using this bill\'s count', async () => {
    mockRequest.query
      .mockResolvedValueOnce({ recordset: [{ token: 't1' }] })
      .mockRejectedValueOnce(new Error('timeout'));
    await sendLowStockNotification(pool, sql, 'b-1', [{ name: 'Sugar', remaining: 2 }]);
    expect(mockSend.mock.calls[0][0].notification.title).toBe('Low stock');
  });
});

test('online-order push still reaches owners AND cashiers, minus those who opted out', async () => {
  mockRequest.query.mockResolvedValueOnce({ recordset: [{ token: 'o1' }, { token: 'c1' }] });
  await sendOnlineOrderNotification(pool, sql, 'b-1', { orderNumber: 'ON-1', total: 100, itemCount: 1 });
  const tokenSql = mockRequest.query.mock.calls[0][0];
  expect(tokenSql).toMatch(/u\.role IN \('owner', 'cashier'\)/);
  expect(tokenSql).toMatch(/u\.notify_online_orders = 1/);
  expect(mockSend.mock.calls[0][0].tokens).toEqual(['o1', 'c1']);
});
