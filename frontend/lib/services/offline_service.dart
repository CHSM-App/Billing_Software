import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

class OfflineService {
  OfflineService._();
  static final instance = OfflineService._();

  Database? _db;

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    final path = join(await getDatabasesPath(), 'billing_offline.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
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
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_cached_items_barcode
            ON cached_items (barcode)
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_cached_items_business
            ON cached_items (business_id)
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS offline_bills (
            local_id       TEXT    NOT NULL PRIMARY KEY,
            business_id    TEXT    NOT NULL,
            user_id        TEXT    NOT NULL,
            table_id       TEXT,
            customer_name  TEXT,
            customer_phone TEXT,
            subtotal       REAL    NOT NULL,
            tax_amount     REAL    NOT NULL,
            total          REAL    NOT NULL,
            payment_mode   TEXT    NOT NULL,
            items_json     TEXT    NOT NULL,
            created_at     INTEGER NOT NULL,
            sync_status    TEXT    NOT NULL DEFAULT 'pending',
            sync_error     TEXT,
            retry_count    INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_offline_bills_status
            ON offline_bills (sync_status)
        ''');
      },
    );
  }

  Database get _database {
    assert(_db != null, 'OfflineService.init() must be called before use');
    return _db!;
  }

  // ---------------------------------------------------------------------------
  // Item cache
  // ---------------------------------------------------------------------------

  /// Replaces entire item cache for this business with fresh server data.
  Future<void> replaceItemCache(List<Item> items, String businessId) async {
    final db = _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('cached_items',
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
      }
    });
  }

  /// Returns all active cached items for the business.
  Future<List<Item>> getCachedItems(String businessId) async {
    final rows = await _database.query(
      'cached_items',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
    );
    return rows.map(_rowToItem).toList();
  }

  /// Looks up a single item by barcode. Returns null if not found.
  Future<Item?> getCachedItemByBarcode(
      String barcode, String businessId) async {
    final rows = await _database.query(
      'cached_items',
      where: 'barcode = ? AND business_id = ? AND is_active = 1',
      whereArgs: [barcode, businessId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToItem(rows.first);
  }

  Item _rowToItem(Map<String, dynamic> row) {
    return Item(
      id: row['id'] as String,
      businessId: row['business_id'] as String,
      name: row['name'] as String,
      barcode: row['barcode'] as String?,
      category: row['category'] as String?,
      price: (row['price'] as num).toDouble(),
      taxRate: row['tax_rate'] != null
          ? (row['tax_rate'] as num).toDouble()
          : null,
      stockQuantity: row['stock_quantity'] != null
          ? (row['stock_quantity'] as num).toDouble()
          : null,
      isActive: (row['is_active'] as int) == 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Offline bill queue
  // ---------------------------------------------------------------------------

  /// Saves a bill to the offline queue. Returns the generated local_id.
  Future<String> queueOfflineBill(Map<String, dynamic> data) async {
    final localId = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    await _database.insert('offline_bills', {
      'local_id': localId,
      'business_id': data['business_id'],
      'user_id': data['user_id'],
      'table_id': data['table_id'],
      'customer_name': data['customer_name'],
      'customer_phone': data['customer_phone'],
      'subtotal': data['subtotal'],
      'tax_amount': data['tax_amount'],
      'total': data['total'],
      'payment_mode': data['payment_mode'],
      'items_json': data['items_json'],
      'created_at': data['created_at'],
      'sync_status': 'pending',
      'retry_count': 0,
    });
    return localId;
  }

  /// Returns all bills that need to be synced (pending + failed with retries left).
  Future<List<Map<String, dynamic>>> getPendingBills() async {
    return _database.query(
      'offline_bills',
      where: "sync_status IN ('pending', 'failed') AND retry_count < 3",
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markBillSyncing(String localId) async {
    await _database.update(
      'offline_bills',
      {'sync_status': 'syncing'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markBillSynced(String localId) async {
    await _database.delete(
      'offline_bills',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markBillFailed(String localId, String error) async {
    await _database.rawUpdate('''
      UPDATE offline_bills
      SET sync_status = 'failed',
          sync_error  = ?,
          retry_count = retry_count + 1
      WHERE local_id = ?
    ''', [error, localId]);
  }

  /// On app startup, reset any rows stuck in 'syncing' (from a crash).
  Future<void> resetStaleSyncing() async {
    await _database.update(
      'offline_bills',
      {'sync_status': 'pending'},
      where: "sync_status = 'syncing'",
    );
  }

  /// Total count of bills waiting to be synced.
  Future<int> getPendingCount() async {
    final result = await _database.rawQuery('''
      SELECT COUNT(*) as cnt FROM offline_bills
      WHERE sync_status IN ('pending', 'failed') AND retry_count < 3
    ''');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Decode items_json back into a list for display.
  static List<Map<String, dynamic>> decodeItems(String itemsJson) {
    return List<Map<String, dynamic>>.from(jsonDecode(itemsJson));
  }
}
