import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

// ---------------------------------------------------------------------------
// UUID v4 generator (no external package needed)
// ---------------------------------------------------------------------------

String _generateUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  // Set version bits (version 4)
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Set variant bits
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}'
      '-${hex(bytes[4])}${hex(bytes[5])}'
      '-${hex(bytes[6])}${hex(bytes[7])}'
      '-${hex(bytes[8])}${hex(bytes[9])}'
      '-${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
}

// ---------------------------------------------------------------------------
// Sync status constants
// ---------------------------------------------------------------------------

/// All possible values of offline_bills.sync_status.
///
///   pending   — queued, not yet attempted
///   syncing   — in-flight (reset to pending on app restart via resetStaleSyncing)
///   failed    — server error or network failure; will retry up to [maxRetries]
///   conflict  — server rejected permanently (409 stock conflict, 400 bad data);
///               will NOT be retried automatically — requires user action
///   done      — row has been deleted after a successful sync (never persisted)
class SyncStatus {
  static const pending  = 'pending';
  static const syncing  = 'syncing';
  static const failed   = 'failed';
  static const conflict = 'conflict';
}

/// Bills are retried at most this many times before being abandoned as failed.
const int maxRetries = 3;

// ---------------------------------------------------------------------------
// Cache TTL
// ---------------------------------------------------------------------------

/// How long a fresh item cache is considered valid before a background refresh
/// is triggered.  Balances price freshness vs. unnecessary network traffic.
const Duration kItemCacheTtl = Duration(hours: 1);

/// A cache is considered "dangerously stale" after this duration: items may
/// have been added/removed/repriced and the user must be warned.
const Duration kItemCacheWarnTtl = Duration(hours: 6);

/// Describes the current state of the cached_items table for a business.
enum CacheStatus {
  /// Cache exists and was populated within [kItemCacheTtl].
  fresh,

  /// Cache exists but is older than [kItemCacheTtl].
  /// The provider will attempt a background refresh when online.
  stale,

  /// Cache exists but is older than [kItemCacheWarnTtl].
  /// The UI should show a warning banner.
  veryStale,

  /// No cache rows exist for this business.
  empty,
}

// ---------------------------------------------------------------------------
// OfflineService
// ---------------------------------------------------------------------------

class OfflineService {
  OfflineService._();
  static final instance = OfflineService._();

  Database? _db;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    final path = join(await getDatabasesPath(), 'billing_offline.db');
    _db = await openDatabase(
      path,
      version: 7,
      onCreate: _createSchema,
      onUpgrade: _migrateSchema,
    );
  }

  /// Full schema for fresh installs (version 2).
  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_items (
        id             TEXT    NOT NULL PRIMARY KEY,
        business_id    TEXT    NOT NULL,
        name           TEXT    NOT NULL,
        barcode        TEXT,
        category       TEXT,
        price          REAL    NOT NULL,
        tax_rate       REAL,
        stock_quantity REAL,
        is_active      INTEGER NOT NULL DEFAULT 1,
        cached_at      INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_items_barcode ON cached_items (barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_items_business ON cached_items (business_id)',
    );
    await _createVariantCacheTable(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_bills (
        local_id        TEXT    NOT NULL PRIMARY KEY,
        client_bill_id  TEXT    NOT NULL UNIQUE,
        business_id     TEXT    NOT NULL,
        user_id         TEXT    NOT NULL,
        table_id        TEXT,
        bill_number     TEXT,
        customer_name   TEXT,
        customer_phone  TEXT,
        subtotal        REAL    NOT NULL,
        tax_amount      REAL    NOT NULL,
        discount_amount REAL    NOT NULL DEFAULT 0,
        total           REAL    NOT NULL,
        round_off       REAL    NOT NULL DEFAULT 0,
        payment_mode    TEXT    NOT NULL,
        items_json      TEXT    NOT NULL,
        created_at      INTEGER NOT NULL,
        sync_status     TEXT    NOT NULL DEFAULT '${SyncStatus.pending}',
        sync_error      TEXT,
        retry_count     INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_offline_bills_status ON offline_bills (sync_status)',
    );
    await _createDraftsTable(db);
  }

  /// Offline draft queue — mirrors [offline_bills] but for `status:'draft'`
  /// (open orders / table drafts) created while disconnected. Kept in its own
  /// table because a draft is reopened and edited before it is finalized, so it
  /// must persist the full priced line items for local display — unlike a
  /// finalized offline bill which is fire-and-forget.
  Future<void> _createDraftsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_drafts (
        local_id        TEXT    NOT NULL PRIMARY KEY,
        client_bill_id  TEXT    NOT NULL UNIQUE,
        business_id     TEXT    NOT NULL,
        user_id         TEXT    NOT NULL,
        table_id        TEXT,
        table_number    TEXT,
        customer_name   TEXT,
        customer_phone  TEXT,
        subtotal        REAL    NOT NULL,
        tax_amount      REAL    NOT NULL,
        discount_amount REAL    NOT NULL DEFAULT 0,
        total           REAL    NOT NULL,
        payment_mode    TEXT    NOT NULL,
        items_json      TEXT    NOT NULL,
        created_at      INTEGER NOT NULL,
        sync_status     TEXT    NOT NULL DEFAULT '${SyncStatus.pending}',
        sync_error      TEXT,
        retry_count     INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_offline_drafts_status ON offline_drafts (sync_status)',
    );
  }

  /// Variant (size) cache — mirrors the item cache so a scanned size barcode
  /// resolves to its parent item + size while offline. Rebuilt wholesale on
  /// every [replaceItemCache].
  Future<void> _createVariantCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_variants (
        id                  TEXT    NOT NULL PRIMARY KEY,
        item_id             TEXT    NOT NULL,
        business_id         TEXT    NOT NULL,
        label               TEXT    NOT NULL,
        price               REAL,
        barcode             TEXT,
        stock_quantity      REAL,
        low_stock_threshold REAL,
        sort_order          INTEGER NOT NULL DEFAULT 0,
        is_active           INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_variants_barcode ON cached_variants (barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_variants_item ON cached_variants (item_id)',
    );
  }

  /// Incremental migrations.
  Future<void> _migrateSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: add client_bill_id for idempotent sync.
      await db.execute(
        'ALTER TABLE offline_bills ADD COLUMN client_bill_id TEXT',
      );
      final rows = await db.query('offline_bills', columns: ['local_id']);
      for (final row in rows) {
        await db.update(
          'offline_bills',
          {'client_bill_id': _generateUuidV4()},
          where: 'local_id = ?',
          whereArgs: [row['local_id']],
        );
      }
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_offline_bills_client_id ON offline_bills (client_bill_id)',
      );
    }
    // v2 → v3: no schema change — cached_at was already present.
    // Version bump records that TTL logic is now active.
    if (oldVersion < 4) {
      // v3 → v4: add the offline draft queue.
      await _createDraftsTable(db);
    }
    if (oldVersion < 5) {
      // v4 → v5: add the variant (size) cache so size barcodes scan offline.
      await _createVariantCacheTable(db);
    }
    if (oldVersion < 6) {
      // v5 → v6: offline_bills gains bill_number (the INV-<tag>-#### shown on the
      // receipt + in history) and discount_amount (was silently dropped before).
      // ALTER ADD is safe & additive; existing rows default sensibly.
      await db.execute('ALTER TABLE offline_bills ADD COLUMN bill_number TEXT');
      await db.execute(
        'ALTER TABLE offline_bills ADD COLUMN discount_amount REAL NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 7) {
      // v6 → v7: offline_bills gains round_off — the signed invoice-level
      // adjustment printed on the receipt, preserved verbatim on sync.
      await db.execute(
        'ALTER TABLE offline_bills ADD COLUMN round_off REAL NOT NULL DEFAULT 0',
      );
    }
  }

  Database get _database {
    assert(_db != null, 'OfflineService.init() must be called before use');
    return _db!;
  }

  // ── Item cache ────────────────────────────────────────────────────────────

  /// Replaces the entire item cache for this business with fresh server data.
  Future<void> replaceItemCache(List<Item> items, String businessId) async {
    final db = _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('cached_items',
          where: 'business_id = ?', whereArgs: [businessId]);
      await txn.delete('cached_variants',
          where: 'business_id = ?', whereArgs: [businessId]);
      for (final item in items) {
        await txn.insert('cached_items', {
          'id': item.id,
          'business_id': businessId,
          'name': item.name,
          'barcode': item.barcode,
          'category': item.category,
          'price': item.price,
          'tax_rate': item.taxRate,
          'stock_quantity': item.stockQuantity,
          'is_active': item.isActive ? 1 : 0,
          'cached_at': now,
        });
        for (final v in item.variants) {
          await txn.insert('cached_variants', {
            'id': v.id,
            'item_id': item.id,
            'business_id': businessId,
            'label': v.label,
            'price': v.price,
            'barcode': v.barcode,
            'stock_quantity': v.stockQuantity,
            'low_stock_threshold': v.lowStockThreshold,
            'sort_order': v.sortOrder,
            'is_active': v.isActive ? 1 : 0,
          });
        }
      }
    });
  }

  /// Returns all active cached items for the business, each with its sizes
  /// (variants) attached so size selection works offline.
  Future<List<Item>> getCachedItems(String businessId) async {
    final rows = await _database.query(
      'cached_items',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
    );
    return _attachCachedVariants(rows, businessId);
  }

  /// Attach cached variants to a set of item rows in ONE query (avoids an
  /// N+1 lookup when building the full catalog).
  Future<List<Item>> _attachCachedVariants(
      List<Map<String, dynamic>> itemRows, String businessId) async {
    if (itemRows.isEmpty) return [];
    final variantRows = await _database.query(
      'cached_variants',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'sort_order ASC, label ASC',
    );
    final byItem = <String, List<ItemVariant>>{};
    for (final r in variantRows) {
      (byItem[r['item_id'] as String] ??= []).add(_rowToVariant(r));
    }
    return itemRows.map((row) {
      final base = _rowToItem(row);
      final variants = byItem[base.id];
      if (variants == null || variants.isEmpty) return base;
      return Item(
        id: base.id,
        businessId: base.businessId,
        name: base.name,
        barcode: base.barcode,
        category: base.category,
        price: base.price,
        taxRate: base.taxRate,
        stockQuantity: base.stockQuantity,
        lowStockThreshold: base.lowStockThreshold,
        unit: base.unit,
        variants: variants,
        isActive: base.isActive,
        imageUrl: base.imageUrl,
      );
    }).toList();
  }

  /// Returns the [CacheStatus] for a business without loading all rows.
  /// Uses MAX(cached_at) for efficiency — a single aggregate query.
  Future<CacheStatus> getCacheStatus(String businessId) async {
    final result = await _database.rawQuery(
      'SELECT MAX(cached_at) AS newest FROM cached_items WHERE business_id = ?',
      [businessId],
    );
    final newest = result.first['newest'] as int?;
    if (newest == null) return CacheStatus.empty;

    final age = DateTime.now().millisecondsSinceEpoch - newest;
    if (age > kItemCacheWarnTtl.inMilliseconds) return CacheStatus.veryStale;
    if (age > kItemCacheTtl.inMilliseconds) return CacheStatus.stale;
    return CacheStatus.fresh;
  }

  /// Returns cached items together with their [CacheStatus].
  /// Use this when you need both the data and the freshness signal in one call.
  Future<({List<Item> items, CacheStatus status})> getCachedItemsWithStatus(
      String businessId) async {
    final rows = await _database.query(
      'cached_items',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
    );
    if (rows.isEmpty) {
      return (items: <Item>[], status: CacheStatus.empty);
    }

    final items = await _attachCachedVariants(rows, businessId);

    // Determine age from the freshest row in this result set.
    int newest = 0;
    for (final row in rows) {
      final t = (row['cached_at'] as int?) ?? 0;
      if (t > newest) newest = t;
    }
    final age = DateTime.now().millisecondsSinceEpoch - newest;
    final CacheStatus status;
    if (age > kItemCacheWarnTtl.inMilliseconds) {
      status = CacheStatus.veryStale;
    } else if (age > kItemCacheTtl.inMilliseconds) {
      status = CacheStatus.stale;
    } else {
      status = CacheStatus.fresh;
    }

    return (items: items, status: status);
  }

  /// Returns the age of the cache for a business as a human-readable string,
  /// e.g. "3h 12m ago".  Returns null if no cache exists.
  Future<String?> getCacheAgeLabel(String businessId) async {
    final result = await _database.rawQuery(
      'SELECT MAX(cached_at) AS newest FROM cached_items WHERE business_id = ?',
      [businessId],
    );
    final newest = result.first['newest'] as int?;
    if (newest == null) return null;

    final diff = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - newest,
    );
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m > 0 ? '${h}h ${m}m ago' : '${h}h ago';
  }

  /// Looks up a single item by barcode. Returns null if not found.
  /// Normalise a barcode the same way the backend does: strip spaces, dashes,
  /// dots so scanner formatting differences never cause a miss.
  static String _normaliseBarcode(String barcode) =>
      barcode.replaceAll(RegExp(r'[\s\-\.]'), '');

  /// Resolves a scanned barcode against the cache. The code may belong to an
  /// item OR to one of its sizes (variants); returns the item plus the matched
  /// variant (null when the item itself matched). Returns null if nothing
  /// matched. Filtering happens in Dart because SQLite has no regex replace.
  Future<({Item item, ItemVariant? variant})?> getBarcodeMatch(
      String barcode, String businessId) async {
    final normalised = _normaliseBarcode(barcode);

    // 1) Try the item-level barcode first.
    final itemRows = await _database.query(
      'cached_items',
      where: 'business_id = ? AND is_active = 1 AND barcode IS NOT NULL',
      whereArgs: [businessId],
    );
    final itemMatch = itemRows.where((r) {
      final stored = r['barcode'] as String?;
      return stored != null && _normaliseBarcode(stored) == normalised;
    }).firstOrNull;
    if (itemMatch != null) {
      return (item: await _rowToItemWithVariants(itemMatch), variant: null);
    }

    // 2) Fall back to a size (variant) barcode.
    final variantRows = await _database.query(
      'cached_variants',
      where: 'business_id = ? AND is_active = 1 AND barcode IS NOT NULL',
      whereArgs: [businessId],
    );
    final variantMatch = variantRows.where((r) {
      final stored = r['barcode'] as String?;
      return stored != null && _normaliseBarcode(stored) == normalised;
    }).firstOrNull;
    if (variantMatch == null) return null;

    final parentRows = await _database.query(
      'cached_items',
      where: 'id = ? AND is_active = 1',
      whereArgs: [variantMatch['item_id']],
      limit: 1,
    );
    if (parentRows.isEmpty) return null;
    final item = await _rowToItemWithVariants(parentRows.first);
    final variant = item.variants
        .where((v) => v.id == variantMatch['id'])
        .firstOrNull;
    return (item: item, variant: variant);
  }

  Item _rowToItem(Map<String, dynamic> row) {
    return Item(
      id: row['id'] as String,
      businessId: row['business_id'] as String,
      name: row['name'] as String,
      barcode: row['barcode'] as String?,
      category: row['category'] as String?,
      price: (row['price'] as num).toDouble(),
      taxRate:
          row['tax_rate'] != null ? (row['tax_rate'] as num).toDouble() : null,
      stockQuantity: row['stock_quantity'] != null
          ? (row['stock_quantity'] as num).toDouble()
          : null,
      isActive: (row['is_active'] as int) == 1,
    );
  }

  ItemVariant _rowToVariant(Map<String, dynamic> row) {
    return ItemVariant(
      id: row['id'] as String,
      itemId: row['item_id'] as String,
      label: row['label'] as String,
      price: row['price'] != null ? (row['price'] as num).toDouble() : null,
      barcode: row['barcode'] as String?,
      stockQuantity: row['stock_quantity'] != null
          ? (row['stock_quantity'] as num).toDouble()
          : null,
      lowStockThreshold: row['low_stock_threshold'] != null
          ? (row['low_stock_threshold'] as num).toDouble()
          : null,
      sortOrder: (row['sort_order'] as int?) ?? 0,
      isActive: (row['is_active'] as int) == 1,
    );
  }

  /// Load the cached variants (sizes) for a single item, ordered like the API.
  Future<List<ItemVariant>> _variantsForItem(String itemId) async {
    final rows = await _database.query(
      'cached_variants',
      where: 'item_id = ? AND is_active = 1',
      whereArgs: [itemId],
      orderBy: 'sort_order ASC, label ASC',
    );
    return rows.map(_rowToVariant).toList();
  }

  Future<Item> _rowToItemWithVariants(Map<String, dynamic> row) async {
    final base = _rowToItem(row);
    final variants = await _variantsForItem(base.id);
    if (variants.isEmpty) return base;
    return Item(
      id: base.id,
      businessId: base.businessId,
      name: base.name,
      barcode: base.barcode,
      category: base.category,
      price: base.price,
      taxRate: base.taxRate,
      stockQuantity: base.stockQuantity,
      lowStockThreshold: base.lowStockThreshold,
      unit: base.unit,
      variants: variants,
      isActive: base.isActive,
      imageUrl: base.imageUrl,
    );
  }

  // ── Offline bill queue ────────────────────────────────────────────────────

  /// Saves a bill to the offline queue.
  /// Generates and stores a UUID v4 as [client_bill_id] for idempotent sync.
  /// Returns a record with both [localId] and [clientBillId].
  Future<({String localId, String clientBillId})> queueOfflineBill(
      Map<String, dynamic> data) async {
    final localId      = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    final clientBillId = _generateUuidV4();

    await _database.insert('offline_bills', {
      'local_id':        localId,
      'client_bill_id':  clientBillId,
      'business_id':     data['business_id'],
      'user_id':         data['user_id'],
      'table_id':        data['table_id'],
      'bill_number':     data['bill_number'],
      'customer_name':   data['customer_name'],
      'customer_phone':  data['customer_phone'],
      'subtotal':        data['subtotal'],
      'tax_amount':      data['tax_amount'],
      'discount_amount': data['discount_amount'] ?? 0,
      'total':           data['total'],
      'round_off':       data['round_off'] ?? 0,
      'payment_mode':    data['payment_mode'],
      'items_json':      data['items_json'],
      'created_at':      data['created_at'],
      'sync_status':     SyncStatus.pending,
      'retry_count':     0,
    });

    return (localId: localId, clientBillId: clientBillId);
  }

  /// Bills eligible for the next sync attempt:
  ///   • status is pending or failed
  ///   • retry_count has not reached [maxRetries]
  Future<List<Map<String, dynamic>>> getPendingBills() async {
    return _database.query(
      'offline_bills',
      where:
          "sync_status IN ('${SyncStatus.pending}', '${SyncStatus.failed}') AND retry_count < $maxRetries",
      orderBy: 'created_at ASC',
    );
  }

  /// Bills that were permanently rejected by the server (stock conflict etc.)
  /// and need the user to manually resolve or dismiss them.
  Future<List<Map<String, dynamic>>> getConflictedBills() async {
    return _database.query(
      'offline_bills',
      where: "sync_status = '${SyncStatus.conflict}'",
      orderBy: 'created_at ASC',
    );
  }

  /// Bills that exhausted all retries (retry_count >= [maxRetries]) without
  /// resolving to a conflict.  These are likely transient-failure victims.
  Future<List<Map<String, dynamic>>> getExhaustedBills() async {
    return _database.query(
      'offline_bills',
      where:
          "sync_status = '${SyncStatus.failed}' AND retry_count >= $maxRetries",
      orderBy: 'created_at ASC',
    );
  }

  // ── Status transitions ────────────────────────────────────────────────────

  Future<void> markBillSyncing(String localId) async {
    await _database.update(
      'offline_bills',
      {'sync_status': SyncStatus.syncing},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Deletes the row after a successful server round-trip.
  Future<void> markBillSynced(String localId) async {
    await _database.delete(
      'offline_bills',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Transient failure (network error, 5xx).  Will be retried until
  /// [maxRetries] is reached.
  Future<void> markBillFailed(String localId, String error) async {
    await _database.rawUpdate('''
      UPDATE offline_bills
      SET sync_status = '${SyncStatus.failed}',
          sync_error  = ?,
          retry_count = retry_count + 1
      WHERE local_id = ?
    ''', [error, localId]);
  }

  /// Permanent server rejection (409 stock conflict, 422 validation).
  /// Sets status to [SyncStatus.conflict] without incrementing retry_count.
  /// The bill will NOT be retried automatically.
  Future<void> markBillConflict(String localId, String error) async {
    await _database.update(
      'offline_bills',
      {'sync_status': SyncStatus.conflict, 'sync_error': error},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Puts a conflicted bill back into the pending queue so it can be
  /// retried with refreshed item data (called from conflict resolution UI).
  Future<void> requeueConflictedBill(String localId) async {
    await _database.update(
      'offline_bills',
      {
        'sync_status': SyncStatus.pending,
        'sync_error':  null,
        'retry_count': 0,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Permanently removes a bill from the queue (user chose "Dismiss").
  Future<void> dismissBill(String localId) async {
    await _database.delete(
      'offline_bills',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// On app startup, reset any rows stuck in 'syncing' (from a crash).
  Future<void> resetStaleSyncing() async {
    await _database.update(
      'offline_bills',
      {'sync_status': SyncStatus.pending},
      where: "sync_status = '${SyncStatus.syncing}'",
    );
  }

  /// Total count of bills waiting to be synced (pending + retryable failed).
  Future<int> getPendingCount() async {
    final result = await _database.rawQuery('''
      SELECT COUNT(*) AS cnt FROM offline_bills
      WHERE sync_status IN ('${SyncStatus.pending}', '${SyncStatus.failed}')
        AND retry_count < $maxRetries
    ''');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Total count of bills needing user attention (conflicts + exhausted).
  Future<int> getAttentionCount() async {
    final result = await _database.rawQuery('''
      SELECT COUNT(*) AS cnt FROM offline_bills
      WHERE sync_status = '${SyncStatus.conflict}'
         OR (sync_status = '${SyncStatus.failed}' AND retry_count >= $maxRetries)
    ''');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Decode items_json back into a list for display.
  static List<Map<String, dynamic>> decodeItems(String itemsJson) {
    return List<Map<String, dynamic>>.from(jsonDecode(itemsJson));
  }

  /// All finalized offline bills for a business, newest first — for DISPLAY in
  /// history (so an offline sale is visible before it syncs). Includes every
  /// sync_status except ones already deleted on success; a synced bill is
  /// removed from this table by [markBillSynced], so it naturally drops off once
  /// the authoritative server copy exists.
  Future<List<Bill>> getAllBills(String businessId) async {
    final rows = await _database.query(
      'offline_bills',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToOfflineBill).toList();
  }

  /// Convert a queued offline_bills row into a [Bill] for display. The bill is
  /// marked status 'unsynced' so the UI can badge it, and carries the local
  /// `INV-<tag>-####` number stored at queue time.
  Bill _rowToOfflineBill(Map<String, dynamic> row) {
    final localId = row['local_id'] as String;
    final items = decodeItems(row['items_json'] as String).map((li) {
      final itemId = (li['item_id'] ?? '') as String;
      return BillItem(
        id: itemId.isEmpty ? localId : itemId,
        billId: localId,
        itemId: li['item_id'] as String?,
        variantId: li['variant_id'] as String?,
        itemName: (li['item_name'] ?? '') as String,
        quantity: (li['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (li['unit_price'] as num?)?.toDouble() ?? 0,
        taxRate: (li['tax_rate'] as num?)?.toDouble(),
        lineTotal: (li['line_total'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
    return Bill(
      id: localId,
      businessId: row['business_id'] as String,
      billNumber: (row['bill_number'] as String?) ?? localId,
      customerName: row['customer_name'] as String?,
      customerPhone: row['customer_phone'] as String?,
      subtotal: (row['subtotal'] as num).toDouble(),
      taxAmount: (row['tax_amount'] as num).toDouble(),
      discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0,
      total: (row['total'] as num).toDouble(),
      roundOff: (row['round_off'] as num?)?.toDouble() ?? 0,
      paymentMode: row['payment_mode'] as String,
      status: 'unsynced',
      createdByUserId: row['user_id'] as String,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      items: items,
    );
  }

  // ── Offline draft queue ────────────────────────────────────────────────────
  //
  // A draft is an *open order* (status:'draft') saved while disconnected. It is
  // queued here and pushed to POST /bills with client_bill_id on reconnect. The
  // full priced items_json is stored so the draft can be shown in Open Orders
  // and reopened for editing before the sync lands.

  /// Queues a draft. Returns its [localId] and generated [clientBillId].
  Future<({String localId, String clientBillId})> queueOfflineDraft(
      Map<String, dynamic> data) async {
    final localId      = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    final clientBillId = _generateUuidV4();

    await _database.insert('offline_drafts', {
      'local_id':        localId,
      'client_bill_id':  clientBillId,
      'business_id':     data['business_id'],
      'user_id':         data['user_id'],
      'table_id':        data['table_id'],
      'table_number':    data['table_number'],
      'customer_name':   data['customer_name'],
      'customer_phone':  data['customer_phone'],
      'subtotal':        data['subtotal'],
      'tax_amount':      data['tax_amount'],
      'discount_amount': data['discount_amount'] ?? 0,
      'total':           data['total'],
      'payment_mode':    data['payment_mode'],
      'items_json':      data['items_json'],
      'created_at':      data['created_at'],
      'sync_status':     SyncStatus.pending,
      'retry_count':     0,
    });

    return (localId: localId, clientBillId: clientBillId);
  }

  /// All queued drafts (any status) for local display in Open Orders.
  Future<List<Map<String, dynamic>>> getAllDrafts() async {
    return _database.query('offline_drafts', orderBy: 'created_at ASC');
  }

  /// A single queued draft by its local id, or null.
  Future<Map<String, dynamic>?> getDraftByLocalId(String localId) async {
    final rows = await _database.query('offline_drafts',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Drafts eligible for the next sync attempt (pending/failed under retry cap).
  Future<List<Map<String, dynamic>>> getPendingDrafts() async {
    return _database.query(
      'offline_drafts',
      where:
          "sync_status IN ('${SyncStatus.pending}', '${SyncStatus.failed}') AND retry_count < $maxRetries",
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markDraftSyncing(String localId) async {
    await _database.update('offline_drafts', {'sync_status': SyncStatus.syncing},
        where: 'local_id = ?', whereArgs: [localId]);
  }

  /// Deletes the draft row after it has been created on the server.
  Future<void> markDraftSynced(String localId) async {
    await _database.delete('offline_drafts',
        where: 'local_id = ?', whereArgs: [localId]);
  }

  /// Removes a queued draft that has been consumed locally (finalized into an
  /// offline bill while still offline). Unlike [markDraftSynced] this is not
  /// tied to a server round-trip — the draft must simply stop existing so it
  /// doesn't linger in Open Orders or later sync as a duplicate draft.
  Future<void> deleteDraft(String localId) async {
    await _database.delete('offline_drafts',
        where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<void> markDraftFailed(String localId, String error) async {
    await _database.rawUpdate('''
      UPDATE offline_drafts
      SET sync_status = '${SyncStatus.failed}',
          sync_error  = ?,
          retry_count = retry_count + 1
      WHERE local_id = ?
    ''', [error, localId]);
  }

  Future<void> markDraftConflict(String localId, String error) async {
    await _database.update('offline_drafts',
        {'sync_status': SyncStatus.conflict, 'sync_error': error},
        where: 'local_id = ?', whereArgs: [localId]);
  }

  /// On startup, reset drafts stuck in 'syncing' (from a crash mid-sync).
  Future<void> resetStaleSyncingDrafts() async {
    await _database.update('offline_drafts', {'sync_status': SyncStatus.pending},
        where: "sync_status = '${SyncStatus.syncing}'");
  }
}
