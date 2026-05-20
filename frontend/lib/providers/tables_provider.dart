import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

class TablesNotifier extends AsyncNotifier<List<TableModel>> {
  @override
  Future<List<TableModel>> build() async {
    final data = await api.getTables();
    return data.map((j) => TableModel.fromJson(j)).toList();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final data = await api.getTables();
      return data.map((j) => TableModel.fromJson(j)).toList();
    });
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
