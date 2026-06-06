import 'package:VBill/models/models.dart';
import 'package:VBill/providers/cart_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


Item makeItem({
  String id = 'item-1',
  String name = 'Rice',
  double price = 50.0,
  double? taxRate,
  double? stockQuantity,
}) =>
    Item(
      id: id,
      businessId: 'biz-1',
      name: name,
      price: price,
      taxRate: taxRate,
      stockQuantity: stockQuantity,
      isActive: true,
    );

ProviderContainer makeContainer() => ProviderContainer();

void main() {
  // ─────────────────────────────────────────────────────────────
  // CartNotifier — addItem
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier.addItem', () {
    test('adds new item with quantity 1', () {
      final container = makeContainer();
      container.read(cartProvider.notifier).addItem(makeItem());
      final cart = container.read(cartProvider);
      expect(cart.length, 1);
      expect(cart.first.item.name, 'Rice');
      expect(cart.first.quantity, 1);
    });

    test('increments quantity for existing item', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.addItem(makeItem());
      final cart = container.read(cartProvider);
      expect(cart.length, 1);
      expect(cart.first.quantity, 2);
    });

    test('adds different items separately', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem(id: 'item-1', name: 'Rice'));
      notifier.addItem(makeItem(id: 'item-2', name: 'Dal'));
      final cart = container.read(cartProvider);
      expect(cart.length, 2);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // CartNotifier — changeQty
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier.changeQty', () {
    test('increments quantity by delta', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.changeQty('item-1', 2);
      expect(container.read(cartProvider).first.quantity, 3);
    });

    test('decrements quantity by delta', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.addItem(makeItem());
      notifier.changeQty('item-1', -1);
      expect(container.read(cartProvider).first.quantity, 1);
    });

    test('removes item when quantity drops to 0', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.changeQty('item-1', -1);
      expect(container.read(cartProvider), isEmpty);
    });

    test('removes item when quantity goes negative', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.changeQty('item-1', -5);
      expect(container.read(cartProvider), isEmpty);
    });

    test('does nothing for unknown item id', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.changeQty('unknown-id', 1);
      expect(container.read(cartProvider).first.quantity, 1);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // CartNotifier — setQty
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier.setQty', () {
    test('sets quantity to exact value', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.setQty('item-1', 10);
      expect(container.read(cartProvider).first.quantity, 10);
    });

    test('removes item when qty set to 0', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.setQty('item-1', 0);
      expect(container.read(cartProvider), isEmpty);
    });

    test('removes item when qty set to negative', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.setQty('item-1', -3);
      expect(container.read(cartProvider), isEmpty);
    });

    test('does nothing for unknown item id', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem());
      notifier.setQty('unknown', 5);
      // item-1 quantity unchanged
      expect(container.read(cartProvider).first.quantity, 1);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // CartNotifier — clear
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier.clear', () {
    test('removes all items', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem(id: 'item-1'));
      notifier.addItem(makeItem(id: 'item-2'));
      notifier.clear();
      expect(container.read(cartProvider), isEmpty);
    });

    test('clear on empty cart is safe', () {
      final container = makeContainer();
      expect(() => container.read(cartProvider.notifier).clear(), returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Computed providers
  // ─────────────────────────────────────────────────────────────
  group('cartSubtotalProvider', () {
    test('returns 0 for empty cart', () {
      final container = makeContainer();
      expect(container.read(cartSubtotalProvider), 0.0);
    });

    test('sums price * quantity (ignoring tax)', () {
      final container = makeContainer();
      container.read(cartProvider.notifier).addItem(makeItem(price: 50.0, taxRate: 10.0));
      container.read(cartProvider.notifier).addItem(makeItem(id: 'item-2', price: 30.0));
      // subtotal = 50 * 1 + 30 * 1 = 80 (no tax in subtotal)
      expect(container.read(cartSubtotalProvider), 80.0);
    });
  });

  group('cartTaxProvider', () {
    test('returns 0 for cart with no-tax items', () {
      final container = makeContainer();
      container.read(cartProvider.notifier).addItem(makeItem(price: 100.0));
      expect(container.read(cartTaxProvider), 0.0);
    });

    test('calculates tax correctly', () {
      final container = makeContainer();
      container.read(cartProvider.notifier).addItem(makeItem(price: 100.0, taxRate: 10.0));
      // tax = 100 * 1 * 0.10 = 10
      expect(container.read(cartTaxProvider), closeTo(10.0, 0.001));
    });
  });

  group('cartTotalProvider', () {
    test('returns subtotal + tax', () {
      final container = makeContainer();
      container.read(cartProvider.notifier).addItem(makeItem(price: 100.0, taxRate: 10.0));
      // subtotal = 100, tax = 10, total = 110
      expect(container.read(cartTotalProvider), closeTo(110.0, 0.001));
    });

    test('returns 0 for empty cart', () {
      final container = makeContainer();
      expect(container.read(cartTotalProvider), 0.0);
    });
  });

  group('cartItemCountProvider', () {
    test('returns 0 for empty cart', () {
      final container = makeContainer();
      expect(container.read(cartItemCountProvider), 0);
    });

    test('sums quantities across all items', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem(id: 'item-1'));
      notifier.addItem(makeItem(id: 'item-1'));
      notifier.addItem(makeItem(id: 'item-2'));
      // item-1 qty = 2, item-2 qty = 1 → total = 3
      expect(container.read(cartItemCountProvider), 3);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // loadFromBill
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier.loadFromBill', () {
    test('loads items from bill', () {
      final container = makeContainer();
      final catalogItem = makeItem(id: 'item-1', name: 'Rice', price: 50.0);

      final bill = Bill(
        id: 'bill-1',
        businessId: 'biz-1',
        billNumber: 'INV-0001',
        subtotal: 100.0,
        taxAmount: 0.0,
        total: 100.0,
        paymentMode: 'cash',
        status: 'draft',
        createdByUserId: 'user-1',
        createdAt: DateTime.now(),
        items: [
          BillItem(
            id: 'bi-1',
            billId: 'bill-1',
            itemId: 'item-1',
            itemName: 'Rice',
            quantity: 3,
            unitPrice: 50.0,
            lineTotal: 150.0,
          ),
        ],
      );

      container.read(cartProvider.notifier).loadFromBill(bill, [catalogItem]);
      final cart = container.read(cartProvider);
      expect(cart.length, 1);
      expect(cart.first.quantity, 3);
      expect(cart.first.item.name, 'Rice');
    });

    test('creates fallback item when not in catalog', () {
      final container = makeContainer();

      final bill = Bill(
        id: 'bill-1',
        businessId: 'biz-1',
        billNumber: 'INV-0001',
        subtotal: 50.0,
        taxAmount: 0.0,
        total: 50.0,
        paymentMode: 'cash',
        status: 'draft',
        createdByUserId: 'user-1',
        createdAt: DateTime.now(),
        items: [
          BillItem(
            id: 'bi-1',
            billId: 'bill-1',
            itemId: 'unknown-item',
            itemName: 'Mystery Item',
            quantity: 1,
            unitPrice: 50.0,
            lineTotal: 50.0,
          ),
        ],
      );

      container.read(cartProvider.notifier).loadFromBill(bill, []);
      final cart = container.read(cartProvider);
      expect(cart.length, 1);
      expect(cart.first.item.name, 'Mystery Item');
      expect(cart.first.item.price, 50.0);
    });

    test('loadFromBill replaces existing cart', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);

      // Pre-populate cart
      notifier.addItem(makeItem(id: 'old-item'));
      expect(container.read(cartProvider).length, 1);

      final bill = Bill(
        id: 'bill-1',
        businessId: 'biz-1',
        billNumber: 'INV-0001',
        subtotal: 0.0,
        taxAmount: 0.0,
        total: 0.0,
        paymentMode: 'cash',
        status: 'draft',
        createdByUserId: 'user-1',
        createdAt: DateTime.now(),
        items: [],
      );

      notifier.loadFromBill(bill, []);
      expect(container.read(cartProvider), isEmpty);
    });
  });
}
