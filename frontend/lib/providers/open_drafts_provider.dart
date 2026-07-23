import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

/// Table-less draft bills — the "Open Orders" queue. A server saves these from
/// the billing page; a cashier/owner opens one to finalize it. The Open Orders
/// tab is only shown while this list is non-empty (see [hasOpenDraftsProvider]).
class OpenDraftsNotifier extends AsyncNotifier<List<Bill>> {
  @override
  Future<List<Bill>> build() async {
    final data = await api.getDraftBills();
    return data.map((j) => Bill.fromJson(j)).toList();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  /// Re-fetch without flipping to a loading spinner — used to reconcile after a
  /// draft is saved or finalized elsewhere.
  Future<void> refreshSilently() async {
    try {
      final data = await api.getDraftBills();
      state = AsyncData(data.map((j) => Bill.fromJson(j)).toList());
    } catch (_) {
      // Keep the current list on failure; a later refresh corrects it.
    }
  }
}

final openDraftsProvider =
    AsyncNotifierProvider<OpenDraftsNotifier, List<Bill>>(
        OpenDraftsNotifier.new);

/// Whether any table-less drafts currently exist. Drives whether the Open
/// Orders tab appears in the shell. Defaults to false until the list loads.
final hasOpenDraftsProvider = Provider<bool>((ref) =>
    (ref.watch(openDraftsProvider).valueOrNull ?? const []).isNotEmpty);
