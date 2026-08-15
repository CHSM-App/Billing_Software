import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart' as api;
import '../models/models.dart';
import '../services/offline_service.dart';
import '../storage.dart';

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------

/// Quick date-range presets for the bill history filter.
enum BillDatePreset { today, yesterday, thisMonth, lastMonth, all, custom }

class BillFilterState {
  final DateTime from;
  final DateTime to;
  final String? search;
  final BillDatePreset preset;

  const BillFilterState({
    required this.from,
    required this.to,
    this.search,
    this.preset = BillDatePreset.today,
  });

  BillFilterState copyWith({
    DateTime? from,
    DateTime? to,
    String? search,
    BillDatePreset? preset,
  }) =>
      BillFilterState(
        from: from ?? this.from,
        to: to ?? this.to,
        search: search,
        preset: preset ?? this.preset,
      );
}

class BillFilterNotifier extends Notifier<BillFilterState> {
  @override
  BillFilterState build() {
    // Use start-of-day in local time so the date sent to the backend
    // matches what the user sees on their device clock.
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return BillFilterState(
        from: startOfToday, to: startOfToday, preset: BillDatePreset.today);
  }

  /// Apply a named preset, computing its date range.
  void setPreset(BillDatePreset preset) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case BillDatePreset.today:
        state = state.copyWith(
            from: startOfToday, to: startOfToday, preset: preset);
      case BillDatePreset.yesterday:
        final y = startOfToday.subtract(const Duration(days: 1));
        state = state.copyWith(from: y, to: y, preset: preset);
      case BillDatePreset.thisMonth:
        state = state.copyWith(
            from: DateTime(now.year, now.month, 1),
            to: startOfToday,
            preset: preset);
      case BillDatePreset.lastMonth:
        final firstOfLast = DateTime(now.year, now.month - 1, 1);
        final lastOfLast = DateTime(now.year, now.month, 0); // day 0 = prev month
        state = state.copyWith(
            from: firstOfLast, to: lastOfLast, preset: preset);
      case BillDatePreset.all:
        // From well before any possible bill up to today.
        state = state.copyWith(
            from: DateTime(2020, 1, 1), to: startOfToday, preset: preset);
      case BillDatePreset.custom:
        state = state.copyWith(preset: preset);
    }
  }

  void setDateRange(DateTime from, DateTime to) => state = state.copyWith(
        from: from,
        to: to,
        preset: BillDatePreset.custom,
      );

  void setSearch(String? query) =>
      state = state.copyWith(
        from: state.from,
        to: state.to,
        preset: state.preset,
        search: (query == null || query.isEmpty) ? null : query,
      );
}

final billFilterProvider =
    NotifierProvider<BillFilterNotifier, BillFilterState>(BillFilterNotifier.new);

// ---------------------------------------------------------------------------
// Bills list — auto-refetches when filter changes
// ---------------------------------------------------------------------------

class BillsNotifier extends AsyncNotifier<List<Bill>> {
  @override
  Future<List<Bill>> build() async {
    final filter = ref.watch(billFilterProvider);
    final fmt = DateFormat('yyyy-MM-dd');

    // Offline bills queued on this device (INV-<tag>-####), not yet synced. They must
    // show in history immediately — both while offline and after reconnect,
    // until the server copy replaces them (the row is deleted on successful
    // sync). Filtered to the same date window + search as the server query.
    final offline = await _offlineBillsInRange(filter);

    try {
      final data = await api.getBills(
        from: fmt.format(filter.from),
        to: fmt.format(filter.to),
        search: filter.search,
      );
      final server = data.map((j) => Bill.fromJson(j)).toList();
      // Mirror server bills locally so history still works after the network
      // drops — a bill created while ONLINE lived only on the server and used
      // to disappear from history the moment connectivity was lost.
      await _cacheServerBills(data);
      // Unsynced offline bills first (most recent, still local), then server
      // bills. De-dupe by id so a just-synced bill doesn't appear twice.
      final serverIds = server.map((b) => b.id).toSet();
      final merged = [
        ...offline.where((b) => !serverIds.contains(b.id)),
        ...server,
      ];
      return merged;
    } catch (e) {
      // Show the locally-queued offline bills (instead of an error screen) when
      // we can't reach a working server — either a genuine network outage, or
      // the server is up but broken (5xx, e.g. its DB is down). A 4xx (auth, bad
      // request) still rethrows so it surfaces normally.
      // Merge the last-known server bills in too, so history offline shows the
      // full picture — not just the sales this device happened to queue.
      if (api.isNetworkError(e) ||
          (e is api.ApiException && e.statusCode >= 500)) {
        final cached = await _cachedServerBillsInRange(filter);
        final offlineIds = offline.map((b) => b.id).toSet();
        return [
          ...offline,
          ...cached.where((b) => !offlineIds.contains(b.id)),
        ];
      }
      rethrow;
    }
  }

  /// Persist raw server bill JSON so history survives going offline.
  Future<void> _cacheServerBills(List<dynamic> data) async {
    final businessId = await getBusinessId();
    if (businessId == null || businessId.isEmpty) return;
    await OfflineService.instance
        .cacheServerBills(businessId, 'bill', data.cast<Map<String, dynamic>>());
  }

  /// Cached server bills narrowed to the filter's date window and search term,
  /// mirroring what the server query would have returned.
  Future<List<Bill>> _cachedServerBillsInRange(BillFilterState filter) async {
    final businessId = await getBusinessId();
    if (businessId == null || businessId.isEmpty) return const [];
    final rows =
        await OfflineService.instance.getCachedServerBills(businessId, 'bill');
    final start = DateTime(filter.from.year, filter.from.month, filter.from.day);
    final end = DateTime(filter.to.year, filter.to.month, filter.to.day)
        .add(const Duration(days: 1));
    final q = filter.search?.trim().toLowerCase();
    return rows.map((j) => Bill.fromJson(j)).where((b) {
      if (b.createdAt.isBefore(start) || !b.createdAt.isBefore(end)) return false;
      if (q != null && q.isNotEmpty) {
        final hay = '${b.billNumber} ${b.customerName ?? ''} '
                '${b.customerPhone ?? ''}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  /// Finalized offline bills for this business within the filter's date range,
  /// matching the search term (bill number / customer). Newest first.
  Future<List<Bill>> _offlineBillsInRange(BillFilterState filter) async {
    final businessId = await getBusinessId();
    if (businessId == null || businessId.isEmpty) return const [];
    final all = await OfflineService.instance.getAllBills(businessId);
    // Inclusive day range: [from 00:00, to+1day 00:00).
    final start = DateTime(filter.from.year, filter.from.month, filter.from.day);
    final end = DateTime(filter.to.year, filter.to.month, filter.to.day)
        .add(const Duration(days: 1));
    final q = filter.search?.trim().toLowerCase();
    return all.where((b) {
      if (b.createdAt.isBefore(start) || !b.createdAt.isBefore(end)) return false;
      if (q != null && q.isNotEmpty) {
        final hay = '${b.billNumber} ${b.customerName ?? ''} '
                '${b.customerPhone ?? ''}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  /// Re-fetch without flipping to a loading spinner — used after a sale so the
  /// new bill appears in history without a manual pull-to-refresh. Failures are
  /// swallowed: the merge in [build] already falls back to local offline bills,
  /// so a network error just leaves the current list in place.
  Future<void> refreshSilently() async {
    try {
      final fresh = await build();
      state = AsyncData(fresh);
    } catch (_) {
      // Keep what's on screen; a later refresh or reconnect corrects it.
    }
  }

  Future<void> voidBill(String id) async {
    await api.voidBill(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(
      current.map((b) => b.id == id ? _withStatus(b, 'voided') : b).toList(),
    );
  }

  Bill _withStatus(Bill b, String status) => Bill(
        id: b.id,
        businessId: b.businessId,
        billNumber: b.billNumber,
        tableId: b.tableId,
        customerName: b.customerName,
        customerPhone: b.customerPhone,
        subtotal: b.subtotal,
        taxAmount: b.taxAmount,
        total: b.total,
        paymentMode: b.paymentMode,
        status: status,
        createdByUserId: b.createdByUserId,
        createdAt: b.createdAt,
        items: b.items,
      );
}

final billsProvider =
    AsyncNotifierProvider<BillsNotifier, List<Bill>>(BillsNotifier.new);
