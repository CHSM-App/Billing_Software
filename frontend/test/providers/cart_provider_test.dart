import 'package:Vittam/models/models.dart';
import 'package:Vittam/providers/cart_provider.dart';
import 'package:Vittam/providers/session_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


Item makeItem({
  String id = 'item-1',
  String name = 'Rice',
  double price = 50.0,
  double? taxRate,
  bool priceInclusiveTax = false,
  double? stockQuantity,
  List<ItemVariant> variants = const [],
}) =>
    Item(
      id: id,
      businessId: 'biz-1',
      name: name,
      price: price,
      taxRate: taxRate,
      priceInclusiveTax: priceInclusiveTax,
      stockQuantity: stockQuantity,
      variants: variants,
      isActive: true,
    );

ItemVariant makeVariant({
  String id = 'var-1',
  String itemId = 'item-1',
  String label = 'XL',
  double? price,
  double? stockQuantity,
}) =>
    ItemVariant(
      id: id,
      itemId: itemId,
      label: label,
      price: price,
      stockQuantity: stockQuantity,
    );

/// [gstEnabled] mirrors the business's master GST toggle. It defaults to true so
/// the tax/total tests exercise the normal taxed path; pass false to assert that
/// tax is ignored entirely even when items still carry a tax_rate.
///
/// [inventoryEnabled] mirrors the per-business stock toggle that gates the
/// over-stock warning. It defaults to false, matching a business that does not
/// track stock — for which no warning may ever fire.
ProviderContainer makeContainer({
  bool gstEnabled = true,
  bool inventoryEnabled = false,
}) =>
    ProviderContainer(overrides: [
      gstEnabledProvider.overrideWithValue(gstEnabled),
      inventoryEnabledProvider.overrideWithValue(inventoryEnabled),
    ]);

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

    test('sets a fractional (weight) quantity', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem(price: 80.0)); // e.g. ₹80/kg
      notifier.setQty('item-1', 1.5);
      final entry = container.read(cartProvider).first;
      expect(entry.quantity, 1.5);
      // 1.5 kg × ₹80 = ₹120 subtotal
      expect(container.read(cartSubtotalProvider), closeTo(120.0, 0.001));
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

    test('ignores tax entirely when GST is disabled', () {
      // The item still carries a leftover tax_rate from when GST was on, but the
      // business toggle is off — tax must be 0 so the printed receipt's grand
      // total matches the net payable shown on the order card.
      final container = makeContainer(gstEnabled: false);
      container.read(cartProvider.notifier).addItem(makeItem(price: 100.0, taxRate: 10.0));
      expect(container.read(cartTaxProvider), 0.0);
      expect(container.read(cartTotalProvider), closeTo(100.0, 0.001));
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

    test('counts distinct line entries, not summed quantities', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem(id: 'item-1'));
      notifier.addItem(makeItem(id: 'item-1'));
      notifier.addItem(makeItem(id: 'item-2'));
      // item-1 (qty 2) + item-2 (qty 1) → 2 distinct lines
      expect(container.read(cartItemCountProvider), 2);
    });

    test('measured items count as one line each', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(makeItem(id: 'item-1'));
      notifier.setQty('item-1', 1.5);
      expect(container.read(cartItemCountProvider), 1);
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

  // ─────────────────────────────────────────────────────────────
  // Variants (sizes)
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier variants', () {
    test('two sizes of one item are separate cart lines', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      final item = makeItem(variants: [
        makeVariant(id: 'v-m', label: 'M', price: 500),
        makeVariant(id: 'v-xl', label: 'XL', price: 550),
      ]);
      notifier.addItem(item, variant: item.variants[0]);
      notifier.addItem(item, variant: item.variants[1]);
      final cart = container.read(cartProvider);
      expect(cart.length, 2);
      expect(cart.map((e) => e.key).toSet(), {'item-1:v-m', 'item-1:v-xl'});
    });

    test('same size stacks quantity', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      final item = makeItem(variants: [makeVariant(id: 'v-xl', label: 'XL')]);
      notifier.addItem(item, variant: item.variants[0]);
      notifier.addItem(item, variant: item.variants[0]);
      final cart = container.read(cartProvider);
      expect(cart.length, 1);
      expect(cart.first.quantity, 2);
    });

    test('variant price overrides item price in subtotal', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      final item = makeItem(price: 500, variants: [
        makeVariant(id: 'v-xl', label: 'XL', price: 550),
      ]);
      notifier.addItem(item, variant: item.variants[0]);
      expect(container.read(cartSubtotalProvider), 550.0);
    });

    test('variant with null price falls back to item price', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      final item = makeItem(price: 500, variants: [
        makeVariant(id: 'v-m', label: 'M', price: null),
      ]);
      notifier.addItem(item, variant: item.variants[0]);
      expect(container.read(cartSubtotalProvider), 500.0);
    });

    test('changeQty by variant key targets the right line', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      final item = makeItem(variants: [
        makeVariant(id: 'v-m', label: 'M'),
        makeVariant(id: 'v-xl', label: 'XL'),
      ]);
      notifier.addItem(item, variant: item.variants[0]);
      notifier.addItem(item, variant: item.variants[1]);
      notifier.changeQty('item-1:v-xl', 2);
      final cart = container.read(cartProvider);
      expect(cart.firstWhere((e) => e.key == 'item-1:v-m').quantity, 1);
      expect(cart.firstWhere((e) => e.key == 'item-1:v-xl').quantity, 3);
    });

    test('displayName includes the size label', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      final item = makeItem(name: 'T-Shirt', variants: [
        makeVariant(id: 'v-xl', label: 'XL'),
      ]);
      notifier.addItem(item, variant: item.variants[0]);
      expect(container.read(cartProvider).first.displayName, 'T-Shirt (XL)');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Tax-inclusive (MRP) pricing through the cart totals
  // ─────────────────────────────────────────────────────────────
  group('tax-inclusive pricing', () {
    test('subtotal is the back-calculated NET, not the MRP', () {
      final container = makeContainer();
      container.read(cartProvider.notifier).addItem(
            makeItem(price: 105.0, taxRate: 5.0, priceInclusiveTax: true),
          );
      // 105 inclusive of 5% = 100 net + 5 tax.
      expect(container.read(cartSubtotalProvider), closeTo(100.0, 0.001));
      expect(container.read(cartTaxProvider), closeTo(5.0, 0.001));
    });

    test('total equals the MRP the customer was quoted', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(
        makeItem(price: 20.0, taxRate: 5.0, priceInclusiveTax: true),
      );
      notifier.changeQty('item-1', 2); // delta, so qty becomes 3
      // The behaviour this feature exists for: 3 x 20 MRP totals 60, not 63.
      expect(container.read(cartTotalProvider), closeTo(60.0, 1e-9));
    });

    test('an exclusive item with the same price totals higher', () {
      final incl = makeContainer();
      incl.read(cartProvider.notifier).addItem(
            makeItem(price: 100.0, taxRate: 18.0, priceInclusiveTax: true),
          );
      final excl = makeContainer();
      excl.read(cartProvider.notifier).addItem(
            makeItem(price: 100.0, taxRate: 18.0),
          );
      expect(incl.read(cartTotalProvider), closeTo(100.0, 1e-9));
      expect(excl.read(cartTotalProvider), closeTo(118.0, 1e-9));
    });

    test('GST off: an MRP price is charged whole, with no tax split', () {
      final container = makeContainer(gstEnabled: false);
      container.read(cartProvider.notifier).addItem(
            makeItem(price: 105.0, taxRate: 5.0, priceInclusiveTax: true),
          );
      // Nothing to extract, so the subtotal is the full price and tax is 0.
      expect(container.read(cartSubtotalProvider), closeTo(105.0, 0.001));
      expect(container.read(cartTaxProvider), 0.0);
      expect(container.read(cartTotalProvider), closeTo(105.0, 0.001));
    });

    test('inclusive and exclusive items mix correctly in one cart', () {
      final container = makeContainer();
      final notifier = container.read(cartProvider.notifier);
      notifier.addItem(
        makeItem(id: 'a', price: 105.0, taxRate: 5.0, priceInclusiveTax: true),
      );
      notifier.addItem(makeItem(id: 'b', price: 200.0, taxRate: 5.0));
      // a: 100 net + 5 tax (MRP 105).  b: 200 net + 10 tax (bills at 210).
      expect(container.read(cartSubtotalProvider), closeTo(300.0, 0.001));
      expect(container.read(cartTaxProvider), closeTo(15.0, 0.001));
      expect(container.read(cartTotalProvider), closeTo(315.0, 0.001));
    });

    test('a variant price inherits the parent item inclusive flag', () {
      final container = makeContainer();
      final variant = makeVariant(id: 'v1', itemId: 'item-1', price: 210.0);
      container.read(cartProvider.notifier).addItem(
            makeItem(
              price: 105.0,
              taxRate: 5.0,
              priceInclusiveTax: true,
              variants: [variant],
            ),
            variant: variant,
          );
      // The size's 210 is an MRP too: 200 net + 10 tax.
      expect(container.read(cartSubtotalProvider), closeTo(200.0, 0.001));
      expect(container.read(cartTotalProvider), closeTo(210.0, 0.001));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // loadFromBill — duplicate bill lines must merge
  //
  // The server APPENDS a bill_items row per order rather than merging: a QR
  // self-order (public_order.js) and PUT /:id/add-items both insert. So one
  // dish ordered twice arrives as two lines sharing an item id.
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier.loadFromBill — duplicate lines', () {
    Bill billWith(List<BillItem> items) => Bill(
          id: 'bill-1',
          businessId: 'biz-1',
          billNumber: 'INV-0001',
          subtotal: 0,
          taxAmount: 0,
          total: 0,
          paymentMode: 'cash',
          status: 'draft',
          createdByUserId: 'user-1',
          createdAt: DateTime.now(),
          items: items,
        );

    test('two lines for the same item merge into one entry', () {
      final container = makeContainer();
      final rice = makeItem(id: 'item-1', name: 'Rice', price: 50.0);
      final bill = billWith([
        BillItem(
            id: 'bi-1',
            billId: 'bill-1',
            itemId: 'item-1',
            itemName: 'Rice',
            quantity: 2,
            unitPrice: 50.0,
            lineTotal: 100.0),
        BillItem(
            id: 'bi-2',
            billId: 'bill-1',
            itemId: 'item-1',
            itemName: 'Rice',
            quantity: 3,
            unitPrice: 50.0,
            lineTotal: 150.0),
      ]);

      container.read(cartProvider.notifier).loadFromBill(bill, [rice]);
      final cart = container.read(cartProvider);
      expect(cart.length, 1, reason: 'duplicate keys must fold into one line');
      expect(cart.first.quantity, 5);
    });

    test('a merged line is still editable and deletable', () {
      // The real damage of a duplicate: every lookup is indexWhere (first match
      // only), so the second row could never be edited, while deleting "one"
      // used to remove both at once.
      final container = makeContainer();
      final rice = makeItem(id: 'item-1', name: 'Rice', price: 50.0);
      final bill = billWith([
        BillItem(
            id: 'bi-1',
            billId: 'bill-1',
            itemId: 'item-1',
            itemName: 'Rice',
            quantity: 2,
            unitPrice: 50.0,
            lineTotal: 100.0),
        BillItem(
            id: 'bi-2',
            billId: 'bill-1',
            itemId: 'item-1',
            itemName: 'Rice',
            quantity: 1,
            unitPrice: 50.0,
            lineTotal: 50.0),
      ]);
      container.read(cartProvider.notifier).loadFromBill(bill, [rice]);

      container.read(cartProvider.notifier).changeQty('item-1', 4);
      expect(container.read(cartProvider).single.quantity, 7);

      container.read(cartProvider.notifier).setQty('item-1', 0);
      expect(container.read(cartProvider), isEmpty);
    });

    test('different sizes of one item stay separate lines', () {
      // Merging is by item+variant, so this must NOT collapse.
      final container = makeContainer();
      final half =
          makeVariant(id: 'v1', itemId: 'item-1', label: 'half', price: 180);
      final full =
          makeVariant(id: 'v2', itemId: 'item-1', label: 'Full', price: 280);
      final dish =
          makeItem(id: 'item-1', name: 'Chicken 65', variants: [half, full]);
      final bill = billWith([
        BillItem(
            id: 'bi-1',
            billId: 'bill-1',
            itemId: 'item-1',
            variantId: 'v1',
            itemName: 'Chicken 65 (half)',
            quantity: 1,
            unitPrice: 180,
            lineTotal: 180),
        BillItem(
            id: 'bi-2',
            billId: 'bill-1',
            itemId: 'item-1',
            variantId: 'v2',
            itemName: 'Chicken 65 (Full)',
            quantity: 1,
            unitPrice: 280,
            lineTotal: 280),
      ]);

      container.read(cartProvider.notifier).loadFromBill(bill, [dish]);
      expect(container.read(cartProvider).length, 2);
    });

    test('same size ordered twice merges', () {
      final container = makeContainer();
      final half =
          makeVariant(id: 'v1', itemId: 'item-1', label: 'half', price: 180);
      final dish = makeItem(id: 'item-1', name: 'Chicken 65', variants: [half]);
      final bill = billWith([
        BillItem(
            id: 'bi-1',
            billId: 'bill-1',
            itemId: 'item-1',
            variantId: 'v1',
            itemName: 'Chicken 65 (half)',
            quantity: 1,
            unitPrice: 180,
            lineTotal: 180),
        BillItem(
            id: 'bi-2',
            billId: 'bill-1',
            itemId: 'item-1',
            variantId: 'v1',
            itemName: 'Chicken 65 (half)',
            quantity: 2,
            unitPrice: 180,
            lineTotal: 360),
      ]);

      container.read(cartProvider.notifier).loadFromBill(bill, [dish]);
      final cart = container.read(cartProvider);
      expect(cart.length, 1);
      expect(cart.single.quantity, 3);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // stockShortfall — warn past available stock, never block
  // ─────────────────────────────────────────────────────────────
  group('CartNotifier.stockShortfall', () {
    test('null while the quantity still fits', () {
      final container = makeContainer(inventoryEnabled: true);
      container.read(cartProvider.notifier).addItem(makeItem(stockQuantity: 8));
      expect(container.read(cartProvider.notifier).stockShortfall('item-1'),
          isNull);
    });

    test('reports the available stock once the cart exceeds it', () {
      final container = makeContainer(inventoryEnabled: true);
      final rice = makeItem(stockQuantity: 2);
      container.read(cartProvider.notifier)
        ..addItem(rice)
        ..addItem(rice)
        ..addItem(rice);
      expect(container.read(cartProvider.notifier).stockShortfall('item-1'), 2);
      // Warned, NOT blocked — the line still holds all three.
      expect(container.read(cartProvider).single.quantity, 3);
    });

    test('silent when the business does not track inventory', () {
      final container = makeContainer(inventoryEnabled: false);
      final rice = makeItem(stockQuantity: 1);
      container.read(cartProvider.notifier)
        ..addItem(rice)
        ..addItem(rice);
      expect(container.read(cartProvider.notifier).stockShortfall('item-1'),
          isNull);
    });

    test('silent when the item carries no stock figure', () {
      // Untracked is not the same as zero.
      final container = makeContainer(inventoryEnabled: true);
      container
          .read(cartProvider.notifier)
          .addItem(makeItem(stockQuantity: null));
      expect(container.read(cartProvider.notifier).stockShortfall('item-1'),
          isNull);
    });

    test('a sized line is measured against its own size stock', () {
      final container = makeContainer(inventoryEnabled: true);
      final half = makeVariant(
          id: 'v1',
          itemId: 'item-1',
          label: 'half',
          price: 180,
          stockQuantity: 1);
      final dish = makeItem(
          id: 'item-1',
          name: 'Chicken 65',
          stockQuantity: 99,
          variants: [half]);
      container.read(cartProvider.notifier)
        ..addItem(dish, variant: half)
        ..addItem(dish, variant: half);
      // 2 in the cart against the SIZE's stock of 1 — the parent's 99 is
      // irrelevant for a sized item.
      expect(
          container.read(cartProvider.notifier).stockShortfall('item-1:v1'), 1);
    });

    test('null for a key that is not in the cart', () {
      final container = makeContainer(inventoryEnabled: true);
      expect(
          container.read(cartProvider.notifier).stockShortfall('nope'), isNull);
    });
  });
}
