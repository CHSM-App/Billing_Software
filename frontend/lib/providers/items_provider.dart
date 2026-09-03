import 'dart:async';
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
    } on http.ClientException {
      // network down — fall through to cache
    } catch (_) {
      // SocketException on native, or other error — fall through to cache
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

  /// Re-fetch items in the background WITHOUT showing a loading spinner — the
  /// current (possibly stale) list stays visible until fresh data arrives.
  /// Called on app open so prices refresh silently instead of warning the user.
  /// Network failures are swallowed; the cached list simply remains.
  Future<void> refreshInBackground() async {
    try {
      final fresh = await _fetch();
      state = AsyncData(fresh);
    } catch (_) {
      // Offline or transient error — keep whatever is currently shown.
    }
  }

  /// Creates the item and returns it, so the caller can use the new id — the
  /// inline "add variants while creating" flow needs it to POST each variant
  /// against the item that was just created.
  Future<Item> addItem(Map<String, dynamic> data) async {
    final result = await api.createItem(data);
    final newItem = Item.fromJson(result);
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, newItem]);
    return newItem;
  }

  Future<Item> updateItem(String id, Map<String, dynamic> data) async {
    final result = await api.updateItem(id, data);
    var updated = Item.fromJson(result);
    final current = state.valueOrNull ?? [];
    // Defensive: if the response carries no `variants` key at all, Item.fromJson
    // yields an empty list — which would make a sized item look like a plain one
    // and bill at its base price. Keep the sizes we already had rather than
    // silently dropping them. (The server attaches them; this guards a partial
    // or older response.)
    if (!result.containsKey('variants')) {
      final existing = current.where((i) => i.id == id).firstOrNull;
      if (existing != null && existing.hasVariants) {
        updated = updated.copyWithVariants(existing.variants);
      }
    }
    state = AsyncData(
      current.map((i) => i.id == id ? updated : i).toList(),
    );
    return updated;
  }

  Future<void> removeItem(String id) async {
    await api.deleteItem(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((i) => i.id != id).toList());
  }

  /// Replace the variant list of a single item in place — no network refetch,
  /// no loading spinner. Used by the size manager so add/delete feel instant.
  /// Also refreshes the offline cache in the background.
  void setItemVariants(String itemId, List<ItemVariant> variants) {
    final current = state.valueOrNull ?? [];
    // copyWithVariants copies EVERY field. The previous hand-rolled Item(...)
    // silently omitted hsnCode and imageUrl, so patching an item's sizes wiped
    // its HSN code (and photo) from local state until the next server refetch.
    final updated =
        current.map((i) => i.id == itemId ? i.copyWithVariants(variants) : i).toList();
    state = AsyncData(updated);

    // Keep the offline cache consistent — fire and forget.
    getBusinessId().then((businessId) {
      if (businessId != null) {
        unawaited(OfflineService.instance.replaceItemCache(updated, businessId));
      }
    });
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

// ---------------------------------------------------------------------------
// CategoryTreeNotifier — the same derivation one level up
// ---------------------------------------------------------------------------

/// Major category → the subcategories filed under it, both sorted.
///
/// Derived from the loaded items exactly the way [categoriesProvider] is:
/// neither level is a stored entity, so a major exists precisely as long as
/// some item carries that string. `''` is the unset bucket at both levels —
/// items with no major land under `''`, which the billing strip labels "Other"
/// and the item form treats as "no major typed".
///
/// A business that has never filled the field in yields a single `''` key,
/// which is what the billing screen tests to hide the major strip entirely.
class CategoryTreeNotifier extends AsyncNotifier<Map<String, List<String>>> {
  @override
  Future<Map<String, List<String>>> build() async {
    return _tree(await ref.watch(itemsProvider.future));
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(
        () async => _tree(await ref.read(itemsProvider.future)));
  }

  static Map<String, List<String>> _tree(List<Item> items) {
    final byMajor = <String, Set<String>>{};
    for (final i in items) {
      final major = i.majorCategory?.trim() ?? '';
      final sub = i.category?.trim() ?? '';
      (byMajor[major] ??= <String>{}).add(sub);
    }
    return {
      for (final major in byMajor.keys.toList()..sort())
        major: byMajor[major]!.toList()..sort(),
    };
  }
}

final categoryTreeProvider =
    AsyncNotifierProvider<CategoryTreeNotifier, Map<String, List<String>>>(
        CategoryTreeNotifier.new);
