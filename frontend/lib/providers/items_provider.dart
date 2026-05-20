import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../api.dart' as api;
import '../models/models.dart';
import '../services/offline_service.dart';
import '../storage.dart';

class ItemsNotifier extends AsyncNotifier<List<Item>> {
  @override
  Future<List<Item>> build() async {
    return _fetch();
  }

  Future<List<Item>> _fetch() async {
    final businessId = await getBusinessId();

    try {
      final (rawItems, topIds) = await (
        api.getItems(),
        api.getTopSoldItemIds(),
      ).wait;
      final items = rawItems.map((j) => Item.fromJson(j)).toList();
      final sorted = _sorted(items, topIds);
      // Cache for offline use — fire and forget
      if (businessId != null) {
        unawaited(
            OfflineService.instance.replaceItemCache(sorted, businessId));
      }
      return sorted;
    } on SocketException {
      return _loadFromCache(businessId);
    } on http.ClientException {
      return _loadFromCache(businessId);
    }
  }

  Future<List<Item>> _loadFromCache(String? businessId) async {
    if (businessId == null) {
      throw Exception('No internet connection and no session found.');
    }
    final cached = await OfflineService.instance.getCachedItems(businessId);
    if (cached.isEmpty) {
      throw Exception(
          'No internet connection and no cached items available.\nPlease connect to the network first.');
    }
    return cached;
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
    // Derive categories from itemsProvider — works offline too
    final items = await ref.watch(itemsProvider.future);
    return items
        .map((i) => i.category)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() async {
      final items = await ref.read(itemsProvider.future);
      return items
          .map((i) => i.category)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
    });
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<String>>(
        CategoriesNotifier.new);
