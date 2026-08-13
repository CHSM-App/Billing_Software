import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';
import '../services/offline_service.dart';

/// Table-less draft bills — the "Open Orders" queue. A server saves these from
/// the billing page; a cashier/owner opens one to finalize it. The Open Orders
/// tab is only shown while this list is non-empty (see [hasOpenDraftsProvider]).
///
/// Drafts saved while offline live in the local [OfflineService] queue and are
/// merged in here so they appear immediately and survive an app restart — until
/// [SyncService] pushes them to the server, at which point the local rows are
/// deleted and the server copies take their place.
class OpenDraftsNotifier extends AsyncNotifier<List<Bill>> {
  @override
  Future<List<Bill>> build() async {
    // Local queued drafts first, so they show even when the server is
    // unreachable. Never let a server error hide them.
    final local = await _localDrafts();
    try {
      final data = await api.getDraftBills();
      final server = data.map((j) => Bill.fromJson(j)).toList();
      return _merge(server, local);
    } catch (_) {
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  /// Re-fetch without flipping to a loading spinner — used to reconcile after a
  /// draft is saved or finalized elsewhere. Keeps local queued drafts merged in.
  Future<void> refreshSilently() async {
    final local = await _localDrafts();
    try {
      final data = await api.getDraftBills();
      final server = data.map((j) => Bill.fromJson(j)).toList();
      state = AsyncData(_merge(server, local));
    } catch (_) {
      // Keep the current list (with local drafts) on failure; a later refresh
      // corrects it. If we have nothing yet, at least show local drafts.
      if (!state.hasValue) state = AsyncData(local);
    }
  }

  /// Optimistically add a just-queued offline draft to the visible list so it
  /// appears in Open Orders instantly, without a round-trip.
  void addLocalDraft(Bill draft) {
    final current = state.valueOrNull ?? const <Bill>[];
    if (current.any((b) => b.id == draft.id)) return;
    state = AsyncData([...current, draft]);
  }

  /// Optimistically drop a draft from the visible list — used when an offline
  /// draft is finalized into a bill while still offline, so it disappears from
  /// Open Orders immediately instead of lingering as "still saving".
  void removeLocalDraft(String draftId) {
    final current = state.valueOrNull ?? const <Bill>[];
    state = AsyncData(current.where((b) => b.id != draftId).toList());
  }

  /// Reads queued offline drafts (table-less only) and rebuilds them as [Bill]s.
  Future<List<Bill>> _localDrafts() async {
    final rows = await OfflineService.instance.getAllDrafts();
    return rows
        .where((r) => r['table_id'] == null) // table drafts live on Tables
        .map(_rowToBill)
        .toList();
  }

  /// Merge server drafts with local queued drafts, de-duplicating by id (a
  /// synced local draft is removed from the queue, so overlap is only during a
  /// brief in-flight window — prefer the server copy when ids collide).
  List<Bill> _merge(List<Bill> server, List<Bill> local) {
    final serverIds = server.map((b) => b.id).toSet();
    return [
      ...server,
      ...local.where((b) => !serverIds.contains(b.id)),
    ];
  }

  Bill _rowToBill(Map<String, dynamic> row) {
    final localId = row['local_id'] as String;
    final items = OfflineService.decodeItems(row['items_json'] as String);
    return Bill(
      id: localId,
      businessId: row['business_id'] as String,
      billNumber: 'LOCAL',
      tableId: row['table_id'] as String?,
      customerName: row['customer_name'] as String?,
      customerPhone: row['customer_phone'] as String?,
      subtotal: (row['subtotal'] as num).toDouble(),
      taxAmount: (row['tax_amount'] as num).toDouble(),
      discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0.0,
      total: (row['total'] as num).toDouble(),
      paymentMode: row['payment_mode'] as String,
      status: 'draft',
      createdByUserId: row['user_id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      items: items
          .map((li) => BillItem(
                id: li['item_id'] as String,
                billId: localId,
                itemId: li['item_id'] as String,
                variantId: li['variant_id'] as String?,
                itemName: li['item_name'] as String? ?? '',
                quantity: (li['quantity'] as num).toDouble(),
                unitPrice: (li['unit_price'] as num).toDouble(),
                taxRate: (li['tax_rate'] as num?)?.toDouble(),
                lineTotal: (li['line_total'] as num).toDouble(),
              ))
          .toList(),
    );
  }
}

final openDraftsProvider =
    AsyncNotifierProvider<OpenDraftsNotifier, List<Bill>>(
        OpenDraftsNotifier.new);

/// Whether any table-less drafts currently exist. Drives whether the Open
/// Orders tab appears in the shell. Defaults to false until the list loads.
final hasOpenDraftsProvider = Provider<bool>((ref) =>
    (ref.watch(openDraftsProvider).valueOrNull ?? const []).isNotEmpty);
