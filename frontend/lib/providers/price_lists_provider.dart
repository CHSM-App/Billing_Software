import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart' as api;
import '../models/models.dart';
import '../storage.dart';

/// The shop's price lists (Party, Wholesale, ...). Fetched from the server and
/// cached per business, so billing can still price from them offline.
class PriceListsNotifier extends AsyncNotifier<List<PriceList>> {
  @override
  Future<List<PriceList>> build() async {
    final businessId = await getBusinessId() ?? '';
    try {
      final raw = await api.getPriceLists();
      if (businessId.isNotEmpty) {
        await saveCachedPriceLists(businessId, jsonEncode(raw));
      }
      return _parse(raw);
    } catch (e) {
      // Offline (or the server is older than price lists): use the cache.
      debugPrint('Price lists: using cache ($e)');
      final cached =
          businessId.isEmpty ? null : await getCachedPriceLists(businessId);
      if (cached == null) return const [];
      try {
        return _parse(jsonDecode(cached) as List);
      } catch (_) {
        return const [];
      }
    }
  }

  static List<PriceList> _parse(List raw) => [
        for (final j in raw.whereType<Map>())
          PriceList.fromJson(Map<String, dynamic>.from(j)),
      ];

  Future<void> reload() async {
    state = await AsyncValue.guard(build);
  }
}

final priceListsProvider =
    AsyncNotifierProvider<PriceListsNotifier, List<PriceList>>(
        PriceListsNotifier.new);

/// The list the current bill is priced with; null = default prices. Set only
/// through [CartNotifier.applyPriceList], which re-prices the cart to match.
class SelectedPriceListNotifier extends Notifier<PriceList?> {
  @override
  PriceList? build() => null;

  void set(PriceList? list) => state = list;
}

final selectedPriceListProvider =
    NotifierProvider<SelectedPriceListNotifier, PriceList?>(
        SelectedPriceListNotifier.new);
