import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

/// Loads and manages the business's raw materials (restaurant ingredient
/// inventory). Owner-managed; not offline-cached — the raw-materials tab is an
/// online management screen, unlike the billing catalog.
class RawMaterialsNotifier extends AsyncNotifier<List<RawMaterial>> {
  @override
  Future<List<RawMaterial>> build() => _fetch();

  Future<List<RawMaterial>> _fetch() async {
    final raw = await api.getRawMaterials();
    return raw.map((j) => RawMaterial.fromJson(j)).toList();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> add(Map<String, dynamic> data) async {
    final created = RawMaterial.fromJson(await api.createRawMaterial(data));
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, created]..sort((a, b) => a.name.compareTo(b.name)));
  }

  Future<void> edit(String id, Map<String, dynamic> data) async {
    final updated = RawMaterial.fromJson(await api.updateRawMaterial(id, data));
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((r) => r.id == id ? updated : r).toList());
  }

  Future<void> remove(String id) async {
    await api.deleteRawMaterial(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((r) => r.id != id).toList());
  }
}

final rawMaterialsProvider =
    AsyncNotifierProvider<RawMaterialsNotifier, List<RawMaterial>>(
        RawMaterialsNotifier.new);
