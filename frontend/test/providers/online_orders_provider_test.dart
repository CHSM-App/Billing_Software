import 'package:Vittam/models/models.dart';
import 'package:Vittam/providers/online_orders_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [pendingOnlineOrderCountProvider] is what decides whether the Online Orders
/// tab exists at all and what number the shop sees on it. Counting a decided
/// order would leave a tab sitting there forever with nothing to do in it, so
/// the filter is worth pinning down.
class _FakeOnlineOrders extends OnlineOrdersNotifier {
  _FakeOnlineOrders(this._orders);
  final List<OnlineOrder> _orders;

  @override
  Future<List<OnlineOrder>> build() async => _orders;
}

OnlineOrder order(String status, {String? billStatus}) => OnlineOrder.fromJson({
      'id': 'order-$status-$billStatus',
      'order_number': 'ORD-0001',
      'customer_phone': '9876543210',
      'fulfilment': 'pickup',
      'total': 100,
      'status': status,
      'bill_status': billStatus,
      'created_at': '2026-09-02T10:00:00.000Z',
    });

void main() {
  ProviderContainer containerWith(List<OnlineOrder> orders) {
    final c = ProviderContainer(overrides: [
      onlineOrdersProvider.overrideWith(() => _FakeOnlineOrders(orders)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('counts only orders still waiting on a decision', () async {
    final c = containerWith([
      order('pending'),
      order('pending'),
      order('accepted', billStatus: 'draft'),
      order('rejected'),
    ]);
    await c.read(onlineOrdersProvider.future);
    expect(c.read(pendingOnlineOrderCountProvider), 2);
  });

  test('is zero when every order has been decided', () async {
    final c = containerWith([
      order('accepted', billStatus: 'finalized'),
      order('rejected'),
    ]);
    await c.read(onlineOrdersProvider.future);
    expect(c.read(pendingOnlineOrderCountProvider), 0);
  });

  test('is zero before the queue has loaded', () {
    // The shell reads this on its first frame; a null-safe default of 0 is what
    // keeps a tab from flashing in and out during startup.
    final c = containerWith([order('pending')]);
    expect(c.read(pendingOnlineOrderCountProvider), 0);
  });
}
