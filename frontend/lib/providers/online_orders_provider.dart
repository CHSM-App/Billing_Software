import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

/// Orders placed from the public online store — everything still waiting on a
/// decision, plus whatever was decided in the last day so the shop can see what
/// it just did.
///
/// Deliberately has NO offline cache, unlike [OpenDraftsNotifier]: an online
/// order can only be accepted or rejected against the server (accepting writes
/// a bill), so showing a stale queue offline would only invite taps that cannot
/// land. Offline, the tab simply carries whatever was last loaded.
class OnlineOrdersNotifier extends AsyncNotifier<List<OnlineOrder>> {
  @override
  Future<List<OnlineOrder>> build() async {
    final data = await api.getOnlineOrders();
    return data
        .map((j) => OnlineOrder.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  /// Re-fetch without flipping to a loading spinner — used when the WebSocket
  /// reports a new order or another device decided one, so the list updates
  /// under the user rather than blanking out.
  Future<void> refreshSilently() async {
    try {
      final data = await api.getOnlineOrders();
      state = AsyncData(data
          .map((j) => OnlineOrder.fromJson(j as Map<String, dynamic>))
          .toList());
    } catch (_) {
      // Keep whatever is on screen; the next event or pull-to-refresh corrects
      // it. Never replace a usable list with an error because one poll failed.
    }
  }

  /// Accept an order, creating its draft bill. Returns the new bill number.
  Future<String?> accept(String id, {bool paymentVerified = false}) async {
    final res = await api.acceptOnlineOrder(id, paymentVerified: paymentVerified);
    await refreshSilently();
    return res['bill_number'] as String?;
  }

  Future<void> reject(String id, String reason) async {
    await api.rejectOnlineOrder(id, reason);
    await refreshSilently();
  }
}

final onlineOrdersProvider =
    AsyncNotifierProvider<OnlineOrdersNotifier, List<OnlineOrder>>(
        OnlineOrdersNotifier.new);

/// How many orders are still waiting on a decision. Drives the count shown on
/// the Online sub-tab. Defaults to 0 until the list loads.
final pendingOnlineOrderCountProvider = Provider<int>((ref) =>
    (ref.watch(onlineOrdersProvider).valueOrNull ?? const <OnlineOrder>[])
        .where((o) => o.isPending)
        .length);

/// Set when something outside the Orders screen wants its Online sub-tab
/// opened — today, tapping an online-order notification.
///
/// A one-shot request rather than a stored selection: OrdersScreen clears it as
/// soon as it acts, so a flag left over from an old tap can never hijack a tab
/// change the user made themselves.
final openOnlineOrdersRequestProvider = StateProvider<bool>((ref) => false);

// No hasOpenOnlineOrders provider: the Online tab now follows the store toggle,
// not the queue's contents, so nothing needs to ask "are any still open?".
// OnlineOrder.isOpen still drives the Waiting / Accepted / Decided grouping
// inside the screen.
