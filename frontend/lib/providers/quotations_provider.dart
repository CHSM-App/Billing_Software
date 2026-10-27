import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart' as api;
import '../models/models.dart';

/// The shop's open quotations, newest first — the Orders page's Quotations
/// tab. Converted ones drop off the server's list.
class QuotationsNotifier extends AsyncNotifier<List<Quotation>> {
  @override
  Future<List<Quotation>> build() async => [
        for (final j in (await api.getQuotations()).whereType<Map>())
          Quotation.fromJson(Map<String, dynamic>.from(j)),
      ];

  Future<void> reload() async {
    state = await AsyncValue.guard(build);
  }
}

final quotationsProvider =
    AsyncNotifierProvider<QuotationsNotifier, List<Quotation>>(
        QuotationsNotifier.new);
