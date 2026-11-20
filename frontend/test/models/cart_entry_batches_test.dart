import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/models/cart_entry.dart';
import 'package:Vittam/models/models.dart';

// CartEntry.sellingFrom must pick batches in the server's order (fifoPlan in
// backend/src/batches.js), or the cost the cashier sees is not what the sale
// is costed at.
void main() {
  const a = StockBatch(id: 'a', code: 'B-0001', unitCost: 50, remaining: 5);
  const b = StockBatch(id: 'b', code: 'B-0002', unitCost: 60, remaining: 5);
  Item item() => Item(
      id: 'i', businessId: 'x', name: 'Rice', price: 80, isActive: true,
      batches: const [a, b]);

  List<String> from(double qty, [String? pick]) =>
      CartEntry(item: item(), quantity: qty, batchId: pick)
          .sellingFrom
          .map((s) => s.code)
          .toList();

  test('oldest batch first, the next only once the first runs out', () {
    expect(from(3), ['B-0001']);
    expect(from(7), ['B-0001', 'B-0002']);
  });

  test("the cashier's pick goes first", () {
    expect(from(3, 'b'), ['B-0002']);
    expect(from(7, 'b'), ['B-0002', 'B-0001']);
  });

  test('a size uses its own batches, not the item\'s', () {
    final v = ItemVariant(id: 'v', itemId: 'i', label: '5 kg', batches: const [b]);
    expect(CartEntry(item: item(), variant: v, quantity: 1).sellingFrom.single.code,
        'B-0002');
  });

  test('the pick reaches the bill payload', () {
    final e = CartEntry(item: item(), quantity: 1, batchId: 'b');
    expect(e.overridePayload(false)['batch_id'], 'b');
    expect(CartEntry(item: item(), quantity: 1).overridePayload(false),
        isNot(contains('batch_id')));
  });

  group('old stock and held bills', () {
    Item stocked(double stock, {double? avg}) => Item(
        id: 'i', businessId: 'x', name: 'Rice', price: 80, isActive: true,
        stockQuantity: stock, avgCost: avg, batches: const [a, b]);

    test('old (pre-batch) stock sells first, at its average cost', () {
      // 12 on the shelf, 10 in batches: 2 old.
      final e = CartEntry(item: stocked(12, avg: 45), quantity: 4);
      final from = e.sellingFrom;
      expect(from.first.isOldStock, isTrue);
      expect(from.first.unitCost, 45);
      expect(from[1].code, 'B-0001');
    });

    test('the cashier pick still comes before old stock', () {
      final e = CartEntry(item: stocked(12), quantity: 1, batchId: 'b');
      expect(e.sellingFrom.single.code, 'B-0002');
    });

    test('a reopened held bill counts what it took back', () {
      // The bill holds 3 of B-0001: the batch shows 2 left, the line can use 5.
      final held = Item(id: 'i', businessId: 'x', name: 'Rice', price: 80, isActive: true,
          stockQuantity: 7, batches: const [
            StockBatch(id: 'a', code: 'B-0001', unitCost: 50, remaining: 2),
            StockBatch(id: 'b', code: 'B-0002', unitCost: 60, remaining: 5),
          ]);
      final e = CartEntry(item: held, quantity: 3, held: const {'a': 3}, heldQty: 3);
      expect(e.sellingFrom.map((s) => s.code).toList(), ['B-0001']);
    });

    test('a cost hidden from staff reads as unknown', () {
      final hidden = StockBatch.fromJson({'id': 'a', 'code': 'B-0001', 'remaining': 2});
      expect(hidden.costKnown, isFalse);
    });
  });
}
