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

  group('suggestStockTargets', () {
    StockTarget t(String id, String name) =>
        StockTarget(name: name, unit: 'pcs', itemId: id);
    final targets = [
      t('1', 'Parle G Biscuit'),
      t('2', 'Tata Salt'),
      t('3', 'Sunflower Oil'),
      t('4', 'Boiled Rice'),
      t('5', 'Basmati Rice'),
      t('6', 'Rice Flour'),
      t('7', 'Rice Bran Oil'),
    ];
    List<String> ids(String text) =>
        [for (final s in suggestStockTargets(targets, text)) s.itemId!];

    test('matches supplier wording, ignoring sizes and punctuation', () {
      expect(ids('PARLE-G BISCUIT 50G'), ['1']);
      expect(ids('TATASALT 1KG'), ['2']);
    });

    test('short words do not match inside longer ones', () {
      expect(ids('BOILED EGGS'), isNot(contains('3')));
    });

    test('best match first, never more than three', () {
      final r = ids('BASMATI RICE 5KG');
      expect(r.first, '5');
      expect(r.length, lessThanOrEqualTo(3));
    });

    test('nothing for empty or unrelated text', () {
      expect(ids(''), isEmpty);
      expect(ids('Cement Bag'), isEmpty);
    });

    // Sharma Tyre Service, invoice 1478: the numbers are the tyre.
    group('tyre sizes', () {
      final tyres = [
        t('a', 'Apollo Tyres 175/60 R15 (GT Max)'),
        t('b', 'Apollo Tyres 175/65 R15 (GT Max)'),
        t('c', 'Apollo Tyres 175/65 R15 (Earth-1 Max)'),
        t('d', 'Apollo Tyres 185/60 R15 (GT Max)'),
        t('e', 'Apollo Tyres 215/65 R16 (G055)'),
        t('f', 'Apollo Tyres 215/65 R16 (G015)'),
        t('g', 'Apollo Tyres 255/65 R16'),
        t('h', 'Apollo Tyres 185/60 R16'),
        t('i', 'Fortune Oil 1L'),
      ];
      List<String> tyreIds(String text) =>
          [for (final s in suggestStockTargets(tyres, text)) s.itemId!];

      test('only the same size, the named variant first', () {
        expect(tyreIds('Apollo 175/65 R15 GT Max'), ['b']);
      });

      test('a misread code still offers both entries of that size', () {
        expect(tyreIds('Apollo 215/65 R16 GOSS'), unorderedEquals(['e', 'f']));
      });

      test('the size reads the same however it is spaced', () {
        expect(tyreIds('APOLLO 175/65R15 GT-MAX'), ['b']);
        expect(tyreIds('FORTUNE OIL 1 LTR'), ['i']);
      });
    });
  });
}
