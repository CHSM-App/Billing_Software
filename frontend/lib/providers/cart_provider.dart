import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../models/models.dart';
import '../models/cart_entry.dart';
import 'price_lists_provider.dart';
import 'session_provider.dart';

class CartNotifier extends Notifier<List<CartEntry>> {
  @override
  List<CartEntry> build() => [];

  /// Cart key for an item + optional variant — mirrors [CartEntry.key].
  static String keyFor(String itemId, [String? variantId]) =>
      variantId == null ? itemId : '$itemId:$variantId';

  /// Stock available for a line — the variant's own count when the item is
  /// sold by size, otherwise the item's. Null means "not tracked", which is
  /// not the same as zero.
  static double? _stockOf(Item item, ItemVariant? variant) =>
      variant != null ? variant.stockQuantity : item.stockQuantity;

  /// The available stock for [key] when the cart now holds MORE than that, or
  /// null when there is nothing to warn about.
  ///
  /// Null when the business does not track inventory, when the item carries no
  /// stock figure, or when the quantity still fits. Deliberately only REPORTS:
  /// the cart accepts the quantity either way, because a counted stock figure
  /// drifts from the shelf and refusing a sale the shop can actually serve is
  /// worse than allowing it. The server still enforces the hard limit at settle
  /// time (checkInsufficientStock in routes/bills.js).
  ///
  /// Lives here rather than on the `+` button because all four add paths — the
  /// button, swipe-right, tapping the quantity box, and the barcode scanner —
  /// route through this notifier; gating the widget would leave the other three
  /// unguarded.
  double? stockShortfall(String key) {
    if (!ref.read(inventoryEnabledProvider)) return null;
    final idx = state.indexWhere((e) => e.key == key);
    if (idx < 0) return null;
    final stock = _stockOf(state[idx].item, state[idx].variant);
    if (stock == null || state[idx].quantity <= stock) return null;
    return stock;
  }

  /// Add one unit of an item (optionally a specific variant/size). Same
  /// item+variant stacks; a different variant of the same item is a new line.
  void addItem(Item item, {ItemVariant? variant}) {
    final k = variant == null ? item.id : '${item.id}:${variant.id}';
    final idx = state.indexWhere((e) => e.key == k);
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          i == idx ? state[i].copyWith(quantity: state[i].quantity + 1) : state[i]
      ];
    } else {
      final line = CartEntry(item: item, variant: variant, quantity: 1);
      state = grouped(
          [...state, _priced(line, ref.read(selectedPriceListProvider))]);
    }
  }

  /// [e] at [list]'s price — an override only where the list differs from
  /// the catalog — keeping its quantity and line discount.
  static CartEntry _priced(CartEntry e, PriceList? list) {
    final p = list?.priceFor(e.item, e.variant);
    return e.copyWith(
        clearOverrides: true,
        priceOverride:
            p == null || (p - e.catalogPrice).abs() < 0.005 ? null : p,
        discountPct: e.discountPct,
        discountAmt: e.discountAmt);
  }

  /// Bill with [list] (null = default prices). Re-prices EVERY line, so a
  /// hand-typed price is replaced too — what's on screen is always the list.
  void applyPriceList(PriceList? list) {
    ref.read(selectedPriceListProvider.notifier).set(list);
    state = [for (final e in state) _priced(e, list)];
  }

  /// Lines grouped by menu category — major A–Z, then subcategory A–Z,
  /// uncategorised last, then name — the same order the server returns bill
  /// lines in (backend/src/billItemsOrder.js), so the cart, the Open Orders
  /// card and every print agree. Ties (sizes of one dish) keep add order.
  @visibleForTesting
  static List<CartEntry> grouped(List<CartEntry> lines) {
    // Case-insensitive A–Z, with an empty group after every named one.
    int cmp(String? a, String? b) {
      final x = a?.trim().toLowerCase() ?? '';
      final y = b?.trim().toLowerCase() ?? '';
      if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
      return x.compareTo(y);
    }

    final indexed = lines.indexed.toList()
      ..sort((a, b) {
        final p = a.$2.item, q = b.$2.item;
        var c = cmp(p.majorCategory, q.majorCategory);
        if (c == 0) c = cmp(p.category, q.category);
        if (c == 0) c = cmp(p.name, q.name);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final (_, e) in indexed) e];
  }

  void changeQty(String key, double delta) {
    final idx = state.indexWhere((e) => e.key == key);
    if (idx < 0) return;
    final newQty = state[idx].quantity + delta;
    if (newQty <= 0) {
      state = state.where((e) => e.key != key).toList();
    } else {
      state = [
        for (int i = 0; i < state.length; i++)
          i == idx ? state[i].copyWith(quantity: newQty) : state[i]
      ];
    }
  }

  void setQty(String key, double qty) {
    if (qty <= 0) {
      state = state.where((e) => e.key != key).toList();
    } else {
      final idx = state.indexWhere((e) => e.key == key);
      if (idx < 0) return;
      state = [
        for (int i = 0; i < state.length; i++)
          i == idx ? state[i].copyWith(quantity: qty) : state[i]
      ];
    }
  }

  /// This bill's price and discount for one line (order-card row editor).
  /// [price] null = back to the catalog price; [pct] set = % discount, else
  /// [amt] ₹ off the line.
  void setLineOverride(String key, {double? price, double? pct, double amt = 0}) {
    state = [
      for (final e in state)
        e.key == key
            ? e.copyWith(
                clearOverrides: true,
                priceOverride: price,
                discountPct: pct,
                discountAmt: pct == null ? amt : 0)
            : e
    ];
  }

  /// Empty the cart. The price list is per bill, so it goes back to default.
  void clear() {
    state = [];
    ref.read(selectedPriceListProvider.notifier).set(null);
  }

  /// Rebuild the cart from a saved bill/draft.
  ///
  /// Bill lines are merged by [CartEntry.key]: the server APPENDS a row per
  /// order rather than merging (a QR self-order and `PUT /:id/add-items` both
  /// insert), so one dish ordered twice arrives as two rows. Mapping those 1:1
  /// used to produce two cart entries sharing a key, and every lookup here is
  /// `indexWhere` — first match only — so the second was uneditable, while
  /// deleting "one" of them removed both. Folding on the way in is the only
  /// place a duplicate key can enter the cart, so it fixes every caller.
  void loadFromBill(Bill bill, List<Item> catalog) {
    final merged = <String, CartEntry>{};
    for (final entry in _entriesFromBill(bill, catalog)) {
      final existing = merged[entry.key];
      // ponytail: the first row's price wins when one dish's rows carry
      // different price overrides; discounts add up.
      merged[entry.key] = existing == null
          ? entry
          : existing.copyWith(
              quantity: existing.quantity + entry.quantity,
              discountAmt: existing.discountAmt + entry.discountAmt);
    }
    // Reopen on the bill's own list. Lines still at catalog price (a waiter
    // added them) take the list price; repriced lines keep what they carry.
    // ponytail: a list not loaded yet (or deleted since) reopens as Default;
    // the lines keep their prices either way.
    final list = bill.priceListId == null
        ? null
        : ref
            .read(priceListsProvider)
            .valueOrNull
            ?.where((l) => l.id == bill.priceListId)
            .firstOrNull;
    ref.read(selectedPriceListProvider.notifier).set(list);
    state = grouped([
      for (final e in merged.values)
        e.priceOverride == null ? _priced(e, list) : e,
    ]);
  }

  Iterable<CartEntry> _entriesFromBill(Bill bill, List<Item> catalog) {
    final gstEnabled = ref.read(gstEnabledProvider);
    return bill.items.map((bi) {
      // bill_items.unit_price is the DISCOUNTED net rate; add the line
      // discount back to get the rate the line was priced at.
      final preNet = bi.unitPrice +
          (bi.quantity > 0 ? bi.discountAmount / bi.quantity : 0.0);
      final catalogItem = catalog.firstWhere(
        (i) => i.id == bi.itemId,
        orElse: () => Item(
          id: bi.itemId ?? bi.id,
          businessId: '',
          name: bi.itemName,
          price: preNet,
          taxRate: bi.taxRate,
          isActive: true,
        ),
      );
      // Resolve the variant from the catalog item when the bill line carries
      // one; fall back to a synthetic variant so price/label survive round-trips.
      ItemVariant? variant;
      if (bi.variantId != null) {
        variant = catalogItem.variants
            .where((v) => v.id == bi.variantId)
            .cast<ItemVariant?>()
            .firstWhere((v) => v != null, orElse: () => null);
        variant ??= ItemVariant(
          id: bi.variantId!,
          itemId: catalogItem.id,
          // Recover the label from "Name (Label)" when possible.
          label: _labelFromName(bi.itemName),
          price: preNet,
        );
      }
      final entry = CartEntry(
          item: catalogItem,
          variant: variant,
          quantity: bi.quantity,
          discountAmt: bi.discountAmount);
      // Priced off-catalog on the order card → restore it as an override, in
      // the same form the cashier typed it (gross for an MRP item). A catalog
      // price changed since the draft was saved also lands here, keeping the
      // draft at the price it was opened with.
      if ((entry.netPrice(gstEnabled) - preNet).abs() < 0.005) return entry;
      final t = (bi.taxRate ?? 0) / 100;
      return entry.copyWith(
          priceOverride:
              catalogItem.priceInclusiveTax ? preNet * (1 + t) : preNet);
    });
  }

  static String _labelFromName(String itemName) {
    final match = RegExp(r'\(([^)]+)\)\s*$').firstMatch(itemName);
    return match != null ? match.group(1)! : '';
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartEntry>>(CartNotifier.new);

// Fine-grained computed providers — only affected widgets rebuild
// NET subtotal. For an MRP (tax-inclusive) item this is the back-calculated
// pre-tax value, so subtotal + tax still lands on the shelf price.
final cartSubtotalProvider = Provider<double>((ref) {
  final gstEnabled = ref.watch(gstEnabledProvider);
  return ref.watch(cartProvider)
      .fold(0.0, (s, e) => s + e.lineNet(gstEnabled));
});

final cartTaxProvider = Provider<double>((ref) {
  // GST off → tax is ignored entirely, even if items carry a leftover tax_rate.
  // CartEntry applies that rule itself, so an MRP price also stops being split.
  final gstEnabled = ref.watch(gstEnabledProvider);
  if (!gstEnabled) return 0.0;
  return ref.watch(cartProvider)
      .fold(0.0, (s, e) => s + e.lineTax(gstEnabled));
});

final cartTotalProvider = Provider<double>((ref) =>
    ref.watch(cartSubtotalProvider) + ref.watch(cartTaxProvider));

// Number of distinct line entries in the cart (used for the cart badge).
// Not a sum of quantities — a 1.5 kg line still counts as one entry.
final cartItemCountProvider = Provider<int>((ref) =>
    ref.watch(cartProvider).length);
