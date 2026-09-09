import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/services/offline_service.dart';

/// Does the offline item cache actually round-trip?
///
/// The billing screen offline is exactly this: write the cache while online,
/// read it back with no network. Everything upstream of it (the provider, the
/// screen) is well covered by reading the code — this is the layer nobody can
/// inspect from a phone, so pin it.
Item _item(String id, {bool isActive = true, String? major}) => Item(
      id: id,
      businessId: 'biz-1',
      name: 'Item $id',
      majorCategory: major,
      category: 'Drinks',
      price: 100,
      taxRate: 18,
      stockQuantity: 5,
      isActive: isActive,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await databaseFactory.deleteDatabase(
        '${await databaseFactory.getDatabasesPath()}/billing_offline.db');
    await OfflineService.instance.init();
  });

  test('items written while online come back when read offline', () async {
    await OfflineService.instance
        .replaceItemCache([_item('a'), _item('b')], 'biz-1');

    final result =
        await OfflineService.instance.getCachedItemsWithStatus('biz-1');

    expect(result.items.length, 2, reason: 'the billing screen reads THIS');
    expect(result.status, CacheStatus.fresh);
  });

  test('an inactive item is cached but never served', () async {
    await OfflineService.instance.replaceItemCache(
        [_item('a'), _item('b', isActive: false)], 'biz-1');

    final result =
        await OfflineService.instance.getCachedItemsWithStatus('biz-1');
    expect(result.items.single.id, 'a');
  });

  test('a major category survives the round trip (the v11 column)', () async {
    await OfflineService.instance
        .replaceItemCache([_item('a', major: 'Bar')], 'biz-1');

    final result =
        await OfflineService.instance.getCachedItemsWithStatus('biz-1');
    expect(result.items.single.majorCategory, 'Bar');
  });

  test('another business sees nothing of ours', () async {
    await OfflineService.instance.replaceItemCache([_item('a')], 'biz-1');

    final other =
        await OfflineService.instance.getCachedItemsWithStatus('biz-2');
    expect(other.items, isEmpty);
    expect(other.status, CacheStatus.empty);
  });

  test('a re-cache replaces rather than accumulates', () async {
    await OfflineService.instance.replaceItemCache([_item('a')], 'biz-1');
    await OfflineService.instance.replaceItemCache([_item('c')], 'biz-1');

    final result =
        await OfflineService.instance.getCachedItemsWithStatus('biz-1');
    expect(result.items.single.id, 'c');
  });

  // A sized item carries no base price of its own (items.price is NULL on the
  // server for variant-only items — migration 031). The cache column was
  // `price REAL NOT NULL`, so ONE such item on the menu aborted the whole
  // replaceItemCache transaction and the shop's cache stayed empty forever.
  test('a variant-only item (no base price) does not abort the cache write',
      () async {
    final sized = Item(
      id: 'sized',
      businessId: 'biz-1',
      name: 'Pizza',
      price: null,
      isActive: true,
      variants: [
        ItemVariant(id: 'v1', itemId: 'sized', label: 'Small', price: 100),
      ],
    );

    await OfflineService.instance.replaceItemCache([sized, _item('a')], 'biz-1');

    final result =
        await OfflineService.instance.getCachedItemsWithStatus('biz-1');
    expect(result.items.length, 2);
    expect(result.items.firstWhere((i) => i.id == 'sized').price, isNull);
    expect(result.items.firstWhere((i) => i.id == 'sized').variants.single.price,
        100);
  });

  // Every shop already on the old schema arrives here through onUpgrade, not
  // onCreate — a migration that fails leaves them exactly as broken as before.
  test('an existing v11 database migrates to a nullable price', () async {
    final path =
        '${await databaseFactory.getDatabasesPath()}/billing_offline.db';
    await databaseFactory.deleteDatabase(path);
    // Recreate the v11 table as it shipped: price NOT NULL, no unit column.
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 11,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE cached_items (
                id TEXT NOT NULL PRIMARY KEY, business_id TEXT NOT NULL,
                name TEXT NOT NULL, barcode TEXT, major_category TEXT,
                category TEXT, price REAL NOT NULL, tax_rate REAL,
                price_inclusive_tax INTEGER NOT NULL DEFAULT 0,
                stock_quantity REAL, is_active INTEGER NOT NULL DEFAULT 1,
                cached_at INTEGER NOT NULL)
            ''');
            await db.execute('''
              CREATE TABLE cached_variants (
                id TEXT NOT NULL PRIMARY KEY, item_id TEXT NOT NULL,
                business_id TEXT NOT NULL, label TEXT NOT NULL, price REAL,
                barcode TEXT, stock_quantity REAL, low_stock_threshold REAL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1)
            ''');
          },
        ));
    await old.close();

    await OfflineService.instance.init();
    await OfflineService.instance.replaceItemCache([
      Item(id: 'sized', businessId: 'biz-1', name: 'Pizza', isActive: true),
    ], 'biz-1');

    final result =
        await OfflineService.instance.getCachedItemsWithStatus('biz-1');
    expect(result.items.single.price, isNull);
  });
}
