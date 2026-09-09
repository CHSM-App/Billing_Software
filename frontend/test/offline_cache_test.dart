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
}
