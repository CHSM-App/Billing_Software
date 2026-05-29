import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../api.dart' as api;
import '../models/models.dart';
import '../services/offline_service.dart';
import '../storage.dart';

// ---------------------------------------------------------------------------
// ItemCacheInfo — metadata about the current item cache.
// Exposed via [itemCacheInfoProvider] so the UI can show staleness banners
// without coupling to the item list itself.
// ---------------------------------------------------------------------------

class ItemCacheInfo {
  /// Freshness status of the currently displayed items.
  final CacheStatus status;

  /// Human-readable age string, e.g. "3h 12m ago". Null when cache is empty.
  final String? ageLabel;

  const ItemCacheInfo({required this.status, this.ageLabel});

  bool get isStale =>
      status == CacheStatus.stale || status == CacheStatus.veryStale;
  bool get isEmpty => status == CacheStatus.empty;
}

final itemCacheInfoProvider = StateProvider<ItemCacheInfo>(
  (_) => const ItemCacheInfo(status: CacheStatus.fresh),
);

// ---------------------------------------------------------------------------
// ItemsNotifier
// ---------------------------------------------------------------------------

class ItemsNotifier extends AsyncNotifier<List<Item>> {
  @override
  Future<List<Item>> build() async {
    return _fetch();
  }

  Future<List<Item>> _fetch() async {
    final businessId = await getBusinessId();

    List<dynamic>? rawItems;
    List<String> topIds = [];

    try {
      rawItems = await api.getItems();
    } on SocketException {
      // network down — fall through to cache
    } on http.ClientException {
      // network down — fall through to cache
    } catch (_) {
      // other error — fall through to cache
    }

    if (rawItems != null) {
      // Online path — fetch top-sold ranking (non-critical).
      try {
        topIds = await api.getTopSoldItemIds();
      } catch (_) {}

      final items = rawItems.map((j) => Item.fromJson(j)).toList();
      final sorted = _sorted(items, topIds);

      // Write fresh data to cache — fire and forget.
      if (businessId != null) {
        unawaited(OfflineService.instance.replaceItemCache(sorted, businessId));
      }

      // Cache is now fresh — clear any stale banner.
      ref.read(itemCacheInfoProvider.notifier).state =
          const ItemCacheInfo(status: CacheStatus.fresh);

      return sorted;
    }

    // ── Offline path ─────────────────────────────────────────────────────────
    return _loadFromCache(businessId);
  }

  Future<List<Item>> _loadFromCache(String? businessId) async {
    if (businessId == null) {
      ref.read(itemCacheInfoProvider.notifier).state =
          const ItemCacheInfo(status: CacheStatus.empty);
      return [];
    }

    final result =
        await OfflineService.instance.getCachedItemsWithStatus(businessId);
    final ageLabel =
        await OfflineService.instance.getCacheAgeLabel(businessId);

    ref.read(itemCacheInfoProvider.notifier).state = ItemCacheInfo(
      status: result.status,
      ageLabel: ageLabel,
    );

    return result.items;
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

// ---------------------------------------------------------------------------
// CategoriesNotifier (unchanged)
// ---------------------------------------------------------------------------

class CategoriesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
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
