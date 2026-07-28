import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart' as api;
import '../models/models.dart';

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
    final data = await api.getBills(
      from: fmt.format(filter.from),
      to: fmt.format(filter.to),
      search: filter.search,
    );
    return data.map((j) => Bill.fromJson(j)).toList();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
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
