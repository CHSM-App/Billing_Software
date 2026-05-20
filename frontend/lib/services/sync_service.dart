import 'dart:convert';
import '../api.dart';
import 'offline_service.dart';

class SyncResult {
  final int synced;
  final int failed;
  const SyncResult({required this.synced, required this.failed});
}

class SyncService {
  SyncService._();
  static final instance = SyncService._();

  bool _running = false;

  /// Push all pending offline bills to the server.
  /// Never throws — errors are absorbed and stored per bill.
  Future<SyncResult> syncAll() async {
    if (_running) return const SyncResult(synced: 0, failed: 0);
    _running = true;

    int synced = 0;
    int failed = 0;

    try {
      final pending = await OfflineService.instance.getPendingBills();
      if (pending.isEmpty) return const SyncResult(synced: 0, failed: 0);

      for (final row in pending) {
        final localId = row['local_id'] as String;
        await OfflineService.instance.markBillSyncing(localId);

        try {
          final payload = _buildApiPayload(row);
          await createBill(payload);
          await OfflineService.instance.markBillSynced(localId);
          synced++;
        } catch (e) {
          await OfflineService.instance.markBillFailed(localId, e.toString());
          failed++;
        }
      }
    } finally {
      _running = false;
    }

    return SyncResult(synced: synced, failed: failed);
  }

  /// Converts a stored offline_bills row into the payload for POST /api/bills.
  Map<String, dynamic> _buildApiPayload(Map<String, dynamic> row) {
    final lineItems = List<Map<String, dynamic>>.from(
      jsonDecode(row['items_json'] as String),
    );

    return {
      'items': lineItems
          .map((li) => {
                'item_id': li['item_id'],
                'quantity': li['quantity'],
              })
          .toList(),
      if (row['table_id'] != null) 'table_id': row['table_id'],
      if (row['customer_name'] != null) 'customer_name': row['customer_name'],
      if (row['customer_phone'] != null)
        'customer_phone': row['customer_phone'],
      'payment_mode': row['payment_mode'],
      'status': 'finalized',
    };
  }
}
