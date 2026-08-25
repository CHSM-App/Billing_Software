import 'package:Vittam/models/models.dart';
import 'package:Vittam/widgets/stock_target_picker.dart';
import 'package:flutter_test/flutter_test.dart';

Item _item(String id, String name,
        {List<ItemVariant> variants = const [],
        double? stock,
        String? hsn,
        double? tax}) =>
    Item(
      id: id,
      businessId: 'b1',
      name: name,
      isActive: true,
      unit: 'kg',
      stockQuantity: stock,
      hsnCode: hsn,
      taxRate: tax,
      variants: variants,
    );

void main() {
  group('buildStockTargets', () {
    test('plain item produces itemId only', () {
      final t = buildStockTargets(
        isRestaurant: false,
        items: [_item('i1', 'Rice', stock: 10, hsn: '1006', tax: 5)],
        materials: const [],
      );
      expect(t, hasLength(1));
      expect(t.single.itemId, 'i1');
      expect(t.single.variantId, isNull);
      expect(t.single.rawMaterialId, isNull);
      expect(t.single.unit, 'kg');
      expect(t.single.currentStock, 10);
      expect(t.single.hsnCode, '1006');
      expect(t.single.taxRate, 5);
    });

    test('sized item produces one row per variant with variantId only', () {
      final t = buildStockTargets(
        isRestaurant: false,
        items: [
          _item('i1', 'Tee', variants: [
            ItemVariant(id: 'v1', itemId: 'i1', label: 'S', stockQuantity: 3),
            ItemVariant(id: 'v2', itemId: 'i1', label: 'M', stockQuantity: 4),
          ]),
        ],
        materials: const [],
      );
      expect(t.map((e) => e.name), ['Tee (M)', 'Tee (S)']);
      for (final row in t) {
        expect(row.itemId, isNull,
            reason: 'variant rows must not also carry the parent item id');
        expect(row.variantId, isNotNull);
        expect(row.rawMaterialId, isNull);
      }
      expect(t.firstWhere((e) => e.name == 'Tee (S)').variantId, 'v1');
    });

    test('restaurant produces raw materials with rawMaterialId only', () {
      final t = buildStockTargets(
        isRestaurant: true,
        items: [_item('i1', 'Burger')],
        materials: [
          RawMaterial(id: 'r1', businessId: 'b1', name: 'Bun', unit: 'piece'),
        ],
      );
      expect(t, hasLength(1));
      expect(t.single.rawMaterialId, 'r1');
      expect(t.single.itemId, isNull);
      expect(t.single.variantId, isNull);
    });

    test('exclude drops rows by display name', () {
      final t = buildStockTargets(
        isRestaurant: false,
        items: [_item('i1', 'Rice'), _item('i2', 'Dal')],
        materials: const [],
        exclude: {'Rice'},
      );
      expect(t.map((e) => e.name), ['Dal']);
    });
  });

  group('findStockTargetByName', () {
    final targets = buildStockTargets(
      isRestaurant: false,
      items: [_item('i1', 'Basmati Rice')],
      materials: const [],
    );

    test('matches case-insensitively and trims', () {
      expect(findStockTargetByName(targets, '  basmati rice ')?.itemId, 'i1');
    });

    test('returns null for unknown or empty names', () {
      expect(findStockTargetByName(targets, 'Rice'), isNull);
      expect(findStockTargetByName(targets, ''), isNull);
    });
  });
}
