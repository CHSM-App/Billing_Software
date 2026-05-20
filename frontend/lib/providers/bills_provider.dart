import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart' as api;
import '../models/models.dart';

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------

class BillFilterState {
  final DateTime from;
  final DateTime to;
  final String? search;

  const BillFilterState({required this.from, required this.to, this.search});

  BillFilterState copyWith({DateTime? from, DateTime? to, String? search}) =>
      BillFilterState(
        from: from ?? this.from,
        to: to ?? this.to,
        search: search,
      );
}

class BillFilterNotifier extends Notifier<BillFilterState> {
  @override
  BillFilterState build() => BillFilterState(
        from: DateTime.now(),
        to: DateTime.now(),
      );

  void setDateRange(DateTime from, DateTime to) =>
      state = state.copyWith(from: from, to: to);

  void setSearch(String? query) =>
      state = state.copyWith(
        from: state.from,
        to: state.to,
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
