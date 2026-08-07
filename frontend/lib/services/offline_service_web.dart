// Web implementation of OfflineService.
// Uses in-memory storage — no SQLite, no persistence across page reloads.
// Offline bill queuing is a best-effort no-op on web; the app is expected
// to be online when running in a browser.

import 'dart:convert';
import 'dart:math';
import '../models/models.dart';

// Re-export constants so import sites see the same names.
export 'offline_service_web.dart' show SyncStatus, CacheStatus, maxRetries,
    kItemCacheTtl, kItemCacheWarnTtl, OfflineService;

class SyncStatus {
  static const pending  = 'pending';
  static const syncing  = 'syncing';
  static const failed   = 'failed';
  static const conflict = 'conflict';
}

const int maxRetries = 3;
const Duration kItemCacheTtl     = Duration(hours: 1);
const Duration kItemCacheWarnTtl = Duration(hours: 6);

enum CacheStatus { fresh, stale, veryStale, empty }

String _generateUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}'
      '-${hex(bytes[4])}${hex(bytes[5])}'
      '-${hex(bytes[6])}${hex(bytes[7])}'
      '-${hex(bytes[8])}${hex(bytes[9])}'
      '-${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
}

class OfflineService {
  OfflineService._();
  static final instance = OfflineService._();

  // In-memory caches
  final Map<String, List<Item>> _itemCache = {};
  final Map<String, int> _itemCacheTime = {};
  final Map<String, Map<String, dynamic>> _bills = {};
  final Map<String, Map<String, dynamic>> _drafts = {};

  Future<void> init() async {}

  Future<void> resetStaleSyncing() async {}

  Future<void> resetStaleSyncingDrafts() async {}

  // ── Item cache ─────────────────────────────────────────────────────────────

  Future<void> replaceItemCache(List<Item> items, String businessId) async {
    _itemCache[businessId] = List.of(items);
    _itemCacheTime[businessId] = DateTime.now().millisecondsSinceEpoch;
  }

  Future<List<Item>> getCachedItems(String businessId) async =>
      List.of(_itemCache[businessId] ?? []);

  Future<CacheStatus> getCacheStatus(String businessId) async {
    final t = _itemCacheTime[businessId];
    if (t == null) return CacheStatus.empty;
    final age = DateTime.now().millisecondsSinceEpoch - t;
    if (age > kItemCacheWarnTtl.inMilliseconds) return CacheStatus.veryStale;
    if (age > kItemCacheTtl.inMilliseconds) return CacheStatus.stale;
    return CacheStatus.fresh;
  }

  Future<({List<Item> items, CacheStatus status})> getCachedItemsWithStatus(
      String businessId) async {
    final items = await getCachedItems(businessId);
    if (items.isEmpty) return (items: <Item>[], status: CacheStatus.empty);
    return (items: items, status: await getCacheStatus(businessId));
  }

  Future<String?> getCacheAgeLabel(String businessId) async {
    final t = _itemCacheTime[businessId];
    if (t == null) return null;
    final diff = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m > 0 ? '${h}h ${m}m ago' : '${h}h ago';
  }

  static String _normaliseBarcode(String barcode) =>
      barcode.replaceAll(RegExp(r'[\s\-\.]'), '');

  /// Resolves a scanned barcode against the cache. The code may belong to an
  /// item OR to one of its sizes (variants); returns the item plus the matched
  /// variant (null when the item itself matched). Returns null if nothing
  /// matched.
  Future<({Item item, ItemVariant? variant})?> getBarcodeMatch(
      String barcode, String businessId) async {
    final normalised = _normaliseBarcode(barcode);
    final items = _itemCache[businessId] ?? [];

    // 1) Item-level barcode.
    final itemMatch = items.where((i) {
      return i.barcode != null && _normaliseBarcode(i.barcode!) == normalised;
    }).firstOrNull;
    if (itemMatch != null) return (item: itemMatch, variant: null);

    // 2) Size (variant) barcode.
    for (final i in items) {
      final v = i.variants.where((v) {
        return v.barcode != null &&
            _normaliseBarcode(v.barcode!) == normalised;
      }).firstOrNull;
      if (v != null) return (item: i, variant: v);
    }
    return null;
  }

  // ── Offline bill queue (in-memory only) ────────────────────────────────────

  Future<({String localId, String clientBillId})> queueOfflineBill(
      Map<String, dynamic> data) async {
    final localId      = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    final clientBillId = _generateUuidV4();
    _bills[localId] = {
      ...data,
      'local_id':       localId,
      'client_bill_id': clientBillId,
      'sync_status':    SyncStatus.pending,
      'retry_count':    0,
    };
    return (localId: localId, clientBillId: clientBillId);
  }

  Future<List<Map<String, dynamic>>> getPendingBills() async => _bills.values
      .where((b) =>
          (b['sync_status'] == SyncStatus.pending ||
           b['sync_status'] == SyncStatus.failed) &&
          (b['retry_count'] as int) < maxRetries)
      .toList();

  Future<List<Map<String, dynamic>>> getConflictedBills() async => _bills.values
      .where((b) => b['sync_status'] == SyncStatus.conflict)
      .toList();

  Future<List<Map<String, dynamic>>> getExhaustedBills() async => _bills.values
      .where((b) =>
          b['sync_status'] == SyncStatus.failed &&
          (b['retry_count'] as int) >= maxRetries)
      .toList();

  Future<void> markBillSyncing(String localId) async =>
      _bills[localId]?['sync_status'] = SyncStatus.syncing;

  Future<void> markBillSynced(String localId) async => _bills.remove(localId);

  Future<void> markBillFailed(String localId, String error) async {
    final b = _bills[localId];
    if (b == null) return;
    b['sync_status'] = SyncStatus.failed;
    b['sync_error']  = error;
    b['retry_count'] = (b['retry_count'] as int) + 1;
  }

  Future<void> markBillConflict(String localId, String error) async {
    final b = _bills[localId];
    if (b == null) return;
    b['sync_status'] = SyncStatus.conflict;
    b['sync_error']  = error;
  }

  Future<void> requeueConflictedBill(String localId) async {
    final b = _bills[localId];
    if (b == null) return;
    b['sync_status'] = SyncStatus.pending;
    b['sync_error']  = null;
    b['retry_count'] = 0;
  }

  Future<void> dismissBill(String localId) async => _bills.remove(localId);

  Future<int> getPendingCount() async => (await getPendingBills()).length;

  Future<int> getAttentionCount() async =>
      (await getConflictedBills()).length + (await getExhaustedBills()).length;

  static List<Map<String, dynamic>> decodeItems(String itemsJson) =>
      List<Map<String, dynamic>>.from(jsonDecode(itemsJson));

  // ── Offline draft queue (in-memory only) ───────────────────────────────────

  Future<({String localId, String clientBillId})> queueOfflineDraft(
      Map<String, dynamic> data) async {
    final localId      = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    final clientBillId = _generateUuidV4();
    _drafts[localId] = {
      ...data,
      'local_id':        localId,
      'client_bill_id':  clientBillId,
      'discount_amount': data['discount_amount'] ?? 0,
      'sync_status':     SyncStatus.pending,
      'retry_count':     0,
    };
    return (localId: localId, clientBillId: clientBillId);
  }

  Future<List<Map<String, dynamic>>> getAllDrafts() async =>
      _drafts.values.toList()
        ..sort((a, b) =>
            (a['created_at'] as int).compareTo(b['created_at'] as int));

  Future<Map<String, dynamic>?> getDraftByLocalId(String localId) async =>
      _drafts[localId];

  Future<List<Map<String, dynamic>>> getPendingDrafts() async => _drafts.values
      .where((d) =>
          (d['sync_status'] == SyncStatus.pending ||
           d['sync_status'] == SyncStatus.failed) &&
          (d['retry_count'] as int) < maxRetries)
      .toList();

  Future<void> markDraftSyncing(String localId) async =>
      _drafts[localId]?['sync_status'] = SyncStatus.syncing;

  Future<void> markDraftSynced(String localId) async => _drafts.remove(localId);

  Future<void> markDraftFailed(String localId, String error) async {
    final d = _drafts[localId];
    if (d == null) return;
    d['sync_status'] = SyncStatus.failed;
    d['sync_error']  = error;
    d['retry_count'] = (d['retry_count'] as int) + 1;
  }

  Future<void> markDraftConflict(String localId, String error) async {
    final d = _drafts[localId];
    if (d == null) return;
    d['sync_status'] = SyncStatus.conflict;
    d['sync_error']  = error;
  }
}
