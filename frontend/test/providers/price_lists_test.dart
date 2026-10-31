import 'package:Vittam/models/models.dart';
import 'package:Vittam/providers/cart_provider.dart';
import 'package:Vittam/providers/price_lists_provider.dart';
import 'package:Vittam/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Item item(String id, double? price, {List<ItemVariant> variants = const []}) =>
    Item(id: id, businessId: 'b', name: id, price: price, variants: variants, isActive: true);

final size = ItemVariant(id: 'L', itemId: 'tea', label: 'Large', price: 30);
final tea = item('tea', null, variants: [size]);
final rice = item('rice', 50);
final dal = item('dal', 40);

const party = PriceList(
  id: 'party',
  name: 'Party',
  adjustPct: 10,
  prices: {'rice': 70, 'tea:L': 35},
);

class _Lists extends PriceListsNotifier {
  @override
  Future<List<PriceList>> build() async => [party];
}

ProviderContainer container() => ProviderContainer(overrides: [
      gstEnabledProvider.overrideWithValue(false),
      inventoryEnabledProvider.overrideWithValue(false),
      priceListsProvider.overrideWith(_Lists.new),
    ]);

void main() {
  group('PriceList.priceFor', () {
    test('a fixed price beats the % rule', () {
      expect(party.priceFor(rice), 70);
      expect(party.priceFor(tea, size), 35);
    });

    test('no fixed price: the % rule on the default, to paise', () {
      expect(party.priceFor(dal), 44);
      expect(const PriceList(id: 'x', name: 'x', adjustPct: 10)
          .priceFor(item('i', 99)), 108.9);
    });

    test('a size is priced on its own, never from the item', () {
      const l = PriceList(id: 'x', name: 'x', adjustPct: 10, prices: {'tea': 1});
      expect(l.priceFor(tea, size), 33);
    });

    test('no rule and no fixed price: null (default stands)', () {
      const plain = PriceList(id: 'x', name: 'x');
      expect(plain.priceFor(dal), isNull);
      expect(party.priceFor(item('free', null)), isNull);
    });

    test('fromJson keys sizes like CartEntry.key', () {
      final l = PriceList.fromJson({
        'id': 'p', 'name': 'P', 'adjust_pct': '5.00',
        'items': [
          {'item_id': 'rice', 'variant_id': null, 'price': '60.00'},
          {'item_id': 'tea', 'variant_id': 'L', 'price': 32},
        ],
      });
      expect(l.adjustPct, 5);
      expect(l.prices, {'rice': 60, 'tea:L': 32});
    });
  });

  group('CartNotifier with a price list', () {
    test('applyPriceList re-prices every line, overwriting a hand edit', () {
      final c = container();
      final cart = c.read(cartProvider.notifier)
        ..addItem(rice)
        ..addItem(dal)
        ..setLineOverride('dal', price: 5, amt: 2);
      cart.applyPriceList(party);
      final lines = {for (final e in c.read(cartProvider)) e.key: e};
      expect(lines['rice']!.effectivePrice, 70);
      expect(lines['dal']!.effectivePrice, 44);
      expect(lines['dal']!.discountAmt, 2, reason: 'line discount is kept');
      expect(c.read(selectedPriceListProvider), party);

      cart.applyPriceList(null);
      expect(c.read(cartProvider).every((e) => e.priceOverride == null), isTrue);
    });

    test('items added while a list is selected get its price', () {
      final c = container();
      c.read(cartProvider.notifier)
        ..applyPriceList(party)
        ..addItem(tea, variant: size);
      expect(c.read(cartProvider).single.effectivePrice, 35);
    });

    test('clear() goes back to default prices', () {
      final c = container();
      c.read(cartProvider.notifier)
        ..applyPriceList(party)
        ..clear()
        ..addItem(rice);
      expect(c.read(selectedPriceListProvider), isNull);
      expect(c.read(cartProvider).single.effectivePrice, 50);
    });

    test('loadFromBill reopens on the bill\'s list; catalog-priced lines take it', () async {
      final c = container();
      await c.read(priceListsProvider.future);
      final bill = Bill(
        id: 'b1', businessId: 'b', billNumber: 'INV-1', subtotal: 0, taxAmount: 0,
        total: 0, paymentMode: 'cash', status: 'draft', createdByUserId: 'u',
        createdAt: DateTime(2026), priceListId: 'party',
        items: [
          // Already at the list price (stored as an override).
          BillItem(id: '1', billId: 'b1', itemId: 'rice', itemName: 'rice',
              quantity: 1, unitPrice: 70, lineTotal: 70),
          // A waiter added this at catalog price.
          BillItem(id: '2', billId: 'b1', itemId: 'dal', itemName: 'dal',
              quantity: 1, unitPrice: 40, lineTotal: 40),
        ],
      );
      c.read(cartProvider.notifier).loadFromBill(bill, [rice, dal]);
      final lines = {for (final e in c.read(cartProvider)) e.key: e};
      expect(c.read(selectedPriceListProvider)?.id, 'party');
      expect(lines['rice']!.effectivePrice, 70);
      expect(lines['dal']!.effectivePrice, 44);
      expect(lines['rice']!.priceList?.id, 'party');
      expect(lines['dal']!.priceList?.id, 'party');
    });
  });

  group('per-line price list', () {
    test('applyLineList re-prices only that line and keeps its discount', () {
      final c = container();
      final cart = c.read(cartProvider.notifier)
        ..addItem(rice)
        ..addItem(dal)
        ..setLineOverride('rice', amt: 3);
      cart.applyLineList('rice', party);
      final lines = {for (final e in c.read(cartProvider)) e.key: e};
      expect(lines['rice']!.effectivePrice, 70);
      expect(lines['rice']!.priceList, party);
      expect(lines['rice']!.discountAmt, 3);
      expect(lines['dal']!.effectivePrice, 40);
      expect(lines['dal']!.priceList, isNull);
      expect(c.read(selectedPriceListProvider), isNull,
          reason: 'the bill default is untouched');

      cart.applyLineList('rice', null);
      final back = c.read(cartProvider).firstWhere((e) => e.key == 'rice');
      expect(back.priceOverride, isNull);
      expect(back.priceList, isNull);
    });

    test('a discount keeps the line\'s list; a typed price drops it', () {
      final c = container();
      final cart = c.read(cartProvider.notifier)
        ..addItem(rice)
        ..applyLineList('rice', party)
        // The editor re-sends the list price along with the discount.
        ..setLineOverride('rice', price: 70, pct: 10);
      expect(c.read(cartProvider).single.priceList, party);
      cart.setLineOverride('rice', price: 65);
      expect(c.read(cartProvider).single.priceList, isNull);
    });

    test('loadFromBill finds a repriced line\'s list on a Default bill', () async {
      final c = container();
      await c.read(priceListsProvider.future);
      final bill = Bill(
        id: 'b1', businessId: 'b', billNumber: 'INV-1', subtotal: 0, taxAmount: 0,
        total: 0, paymentMode: 'cash', status: 'draft', createdByUserId: 'u',
        createdAt: DateTime(2026),
        items: [
          BillItem(id: '1', billId: 'b1', itemId: 'rice', itemName: 'rice',
              quantity: 1, unitPrice: 70, lineTotal: 70),
          BillItem(id: '2', billId: 'b1', itemId: 'dal', itemName: 'dal',
              quantity: 1, unitPrice: 33, lineTotal: 33),
        ],
      );
      c.read(cartProvider.notifier).loadFromBill(bill, [rice, dal]);
      final lines = {for (final e in c.read(cartProvider)) e.key: e};
      expect(lines['rice']!.priceList?.id, 'party');
      expect(lines['dal']!.priceList, isNull, reason: 'hand-typed price');
    });
  });
}
