import 'dart:io';

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
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // A private folder, never the default: on desktop the default databases
    // path is relative to the working directory, which for `flutter test` is
    // the same frontend/ folder `flutter run` uses — so these tests (which
    // delete the DB and rebuild it with only the cache tables) were wiping
    // the developer's real offline DB and breaking the next app start.
    final dir = await Directory.systemTemp.createTemp('vittam_offline_test');
    await databaseFactory.setDatabasesPath(dir.path);
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

  // Item No (v15): "(101)" label and number search must work offline too.
  test('item_no survives the round trip (the v15 column)', () async {
    final withNo = Item.fromJson({
      'id': 'a', 'business_id': 'biz-1', 'name': 'Masala Dosa',
      'item_no': '101', 'price': 80, 'is_active': 1,
    });
    await OfflineService.instance
        .replaceItemCache([withNo, _item('b')], 'biz-1');

    final items =
        (await OfflineService.instance.getCachedItemsWithStatus('biz-1')).items;
    expect(items.firstWhere((i) => i.id == 'a').itemNo, '101');
    expect(items.firstWhere((i) => i.id == 'b').itemNo, isNull);
  });

  test('a v14 device upgrades and gains cached_items.item_no and packs', () async {
    final path =
        '${await databaseFactory.getDatabasesPath()}/billing_offline.db';
    await databaseFactory.deleteDatabase(path);
    // The v14 item cache: today's table without item_no. The rest of the
    // schema is restored by init's self-heal.
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 14,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE cached_items (
              id TEXT NOT NULL PRIMARY KEY, business_id TEXT NOT NULL,
              name TEXT NOT NULL, barcode TEXT, major_category TEXT,
              category TEXT, price REAL, tax_rate REAL,
              price_inclusive_tax INTEGER NOT NULL DEFAULT 0,
              stock_quantity REAL, unit TEXT NOT NULL DEFAULT 'piece',
              is_active INTEGER NOT NULL DEFAULT 1, cached_at INTEGER NOT NULL)
          '''),
        ));
    await old.close();

    await OfflineService.instance.init();

    // Same single instance the service holds — inspect it, don't close it.
    final db = await databaseFactory.openDatabase(path);
    final cols = await db.rawQuery('PRAGMA table_info(cached_items)');
    expect(cols.map((c) => c['name']), containsAll(['item_no', 'pack_unit', 'pack_size']));
    expect(await db.getVersion(), 17);

    // And the cache works end to end on the upgraded table.
    await OfflineService.instance.replaceItemCache([
      Item.fromJson({'id': 'a', 'business_id': 'biz-1', 'name': 'Idli',
          'item_no': '7', 'price': 40, 'is_active': 1,
          'pack_unit': 'box', 'pack_size': 15}),
    ], 'biz-1');
    final items =
        (await OfflineService.instance.getCachedItemsWithStatus('biz-1')).items;
    expect(items.single.itemNo, '7');
    expect(items.single.packUnit, 'box');
    expect(items.single.packSize, 15);
  });

  // v17: customer address / GSTIN. A bill queued by the previous app version
  // must survive the upgrade and still read (and sync) as before.
  test('a v16 device keeps its queued bill and gains customer address/GSTIN', () async {
    final path =
        '${await databaseFactory.getDatabasesPath()}/billing_offline.db';
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 16,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE offline_bills (
                local_id TEXT NOT NULL PRIMARY KEY,
                client_bill_id TEXT NOT NULL UNIQUE,
                business_id TEXT NOT NULL, user_id TEXT NOT NULL,
                table_id TEXT, bill_number TEXT,
                customer_name TEXT, customer_phone TEXT,
                subtotal REAL NOT NULL, tax_amount REAL NOT NULL,
                discount_amount REAL NOT NULL DEFAULT 0,
                charges_amount REAL NOT NULL DEFAULT 0,
                additional_charges TEXT, total REAL NOT NULL,
                round_off REAL NOT NULL DEFAULT 0,
                payment_mode TEXT NOT NULL, payments TEXT,
                items_json TEXT NOT NULL, created_at INTEGER NOT NULL,
                sync_status TEXT NOT NULL DEFAULT 'pending',
                sync_error TEXT, retry_count INTEGER NOT NULL DEFAULT 0)
            ''');
            await db.insert('offline_bills', {
              'local_id': 'LOCAL-1', 'client_bill_id': 'c-1',
              'business_id': 'biz-1', 'user_id': 'u-1',
              'customer_name': 'Asha', 'customer_phone': '9876543210',
              'subtotal': 100, 'tax_amount': 0, 'total': 100,
              'payment_mode': 'cash', 'items_json': '[]', 'created_at': 1,
            });
          },
        ));
    await old.close();

    await OfflineService.instance.init();

    final db = await databaseFactory.openDatabase(path);
    expect(await db.getVersion(), 17);
    final cols = (await db.rawQuery('PRAGMA table_info(offline_bills)'))
        .map((c) => c['name']);
    expect(cols, containsAll(['customer_address', 'customer_gstin']));
    final pending = await OfflineService.instance.getPendingBills();
    expect(pending.single['customer_name'], 'Asha');
    expect(pending.single['customer_address'], isNull);
  });
}
