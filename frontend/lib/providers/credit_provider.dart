import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

/// Debtor list for the Credit tab — customers who owe money on credit bills.
class CreditCustomersNotifier extends AsyncNotifier<List<CreditCustomer>> {
  @override
  Future<List<CreditCustomer>> build() async {
    final data = await api.getCreditCustomers();
    return data.map((j) => CreditCustomer.fromJson(j)).toList();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  /// Re-fetch without a loading spinner — used to reconcile after a settlement
  /// on this or another device.
  Future<void> refreshSilently() async {
    try {
      final data = await api.getCreditCustomers();
      state = AsyncData(data.map((j) => CreditCustomer.fromJson(j)).toList());
    } catch (_) {
      // Keep the current list on failure; a later refresh corrects it.
    }
  }
}

final creditCustomersProvider =
    AsyncNotifierProvider<CreditCustomersNotifier, List<CreditCustomer>>(
        CreditCustomersNotifier.new);
