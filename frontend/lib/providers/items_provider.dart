import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

class ItemsNotifier extends AsyncNotifier<List<Item>> {
  @override
  Future<List<Item>> build() async {
    return _fetch();
  }

  Future<List<Item>> _fetch() async {
    final (rawItems, topIds) = await (
      api.getItems(),
      api.getTopSoldItemIds(),
    ).wait;
    final items = rawItems.map((j) => Item.fromJson(j)).toList();
    return _sorted(items, topIds);
  }

  List<Item> _sorted(List<Item> items, List<String> topIds) {
    final rank = <String, int>{};
    for (int i = 0; i < topIds.length; i++) {
      rank[topIds[i]] = i;
    }
    return [...items]..sort((a, b) {
        final ra = rank[a.id] ?? topIds.length;
        final rb = rank[b.id] ?? topIds.length;
        if (ra != rb) return ra.compareTo(rb);
        return a.name.compareTo(b.name);
      });
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> addItem(Map<String, dynamic> data) async {
    final result = await api.createItem(data);
    final newItem = Item.fromJson(result);
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, newItem]);
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    final result = await api.updateItem(id, data);
    final updated = Item.fromJson(result);
    final current = state.valueOrNull ?? [];
    state = AsyncData(
      current.map((i) => i.id == id ? updated : i).toList(),
    );
  }

  Future<void> removeItem(String id) async {
    await api.deleteItem(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((i) => i.id != id).toList());
  }
}

final itemsProvider =
    AsyncNotifierProvider<ItemsNotifier, List<Item>>(ItemsNotifier.new);

class CategoriesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    return api.getCategories();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(api.getCategories);
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<String>>(
        CategoriesNotifier.new);
