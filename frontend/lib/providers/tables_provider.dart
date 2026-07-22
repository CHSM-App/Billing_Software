import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

class TablesNotifier extends AsyncNotifier<List<TableModel>> {
  // Cache of active draft bills keyed by bill id — populated on every fetch.
  final Map<String, Bill> _billCache = {};

  /// Returns the cached draft bill for a given bill id, or null if not loaded.
  Bill? cachedBill(String? billId) =>
      billId == null ? null : _billCache[billId];

  @override
  Future<List<TableModel>> build() => _fetch();

  Future<List<TableModel>> _fetch() async {
    final data = await api.getTables();
    final tables = data.map((j) => TableModel.fromJson(j)).toList();

    // Fetch all active draft bills in parallel — zero extra sequential latency.
    final activeIds = tables
        .map((t) => t.activeBillId)
        .whereType<String>()
        .toList();

    if (activeIds.isNotEmpty) {
      final results = await Future.wait(
        activeIds.map((id) => api
            .getBill(id)
            .then<Bill?>((d) => Bill.fromJson(d))
            .catchError((_) => null)),
      );
      _billCache.clear();
      for (int i = 0; i < activeIds.length; i++) {
        final bill = results[i];
        if (bill != null) _billCache[activeIds[i]] = bill;
      }
    } else {
      _billCache.clear();
    }

    return tables;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Re-fetch tables in the background WITHOUT flipping to a loading spinner.
  /// The current list stays on screen and is swapped for fresh data when it
  /// arrives — used to reconcile after an optimistic update.
  Future<void> refreshSilently() async {
    try {
      final tables = await _fetch();
      state = AsyncData(tables);
    } catch (_) {
      // Keep the existing (optimistic) state on failure — a later refresh
      // or reconnect will correct it.
    }
  }

  /// Optimistically reflect a just-saved draft on a table: mark it occupied,
  /// point it at the new bill and cache the bill so reopening is instant. Call
  /// this the moment the save is issued so the UI updates without waiting for a
  /// full tables refetch. Pass [bill] when the server response is available so
  /// the cache is populated; the [billId] alone is enough to flip the status.
  void applyDraftSaved(String tableId, {String? billId, Bill? bill}) {
    final effectiveBillId = bill?.id ?? billId;
    if (bill != null) _billCache[bill.id] = bill;
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((t) {
      if (t.id != tableId) return t;
      return TableModel(
        id: t.id,
        businessId: t.businessId,
        tableNumber: t.tableNumber,
        floorX: t.floorX,
        floorY: t.floorY,
        status: 'occupied',
        activeBillId: effectiveBillId ?? t.activeBillId,
      );
    }).toList());
  }

  Future<void> addTable(Map<String, dynamic> data) async {
    final result = await api.createTable(data);
    final newTable = TableModel.fromJson(result);
    state = AsyncData([...state.valueOrNull ?? [], newTable]);
  }

  Future<void> removeTable(String id) async {
    await api.deleteTable(id);
    state = AsyncData(
      (state.valueOrNull ?? []).where((t) => t.id != id).toList(),
    );
  }

  Future<void> updateStatus(String id, String status) async {
    await api.updateTable(id, {'status': status});
    _patchTable(id, status: status);
  }

  Future<void> updatePosition(String id, double x, double y) async {
    await api.updateTable(id, {'floor_x': x, 'floor_y': y});
    _patchTable(id, floorX: x, floorY: y);
  }

  void _patchTable(String id, {String? status, double? floorX, double? floorY}) {
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((t) {
      if (t.id != id) return t;
      return TableModel(
        id: t.id,
        businessId: t.businessId,
        tableNumber: t.tableNumber,
        floorX: floorX ?? t.floorX,
        floorY: floorY ?? t.floorY,
        status: status ?? t.status,
        activeBillId: t.activeBillId,
      );
    }).toList());
  }
}

final tablesProvider =
    AsyncNotifierProvider<TablesNotifier, List<TableModel>>(TablesNotifier.new);
