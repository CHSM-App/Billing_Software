import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../models/cart_entry.dart';
import 'session_provider.dart';

class CartNotifier extends Notifier<List<CartEntry>> {
  @override
  List<CartEntry> build() => [];

  /// Cart key for an item + optional variant — mirrors [CartEntry.key].
  static String keyFor(String itemId, [String? variantId]) =>
      variantId == null ? itemId : '$itemId:$variantId';

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
      state = [...state, CartEntry(item: item, variant: variant, quantity: 1)];
    }
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

  void clear() => state = [];

  void loadFromBill(Bill bill, List<Item> catalog) {
    state = bill.items.map((bi) {
      final catalogItem = catalog.firstWhere(
        (i) => i.id == bi.itemId,
        orElse: () => Item(
          id: bi.itemId ?? bi.id,
          businessId: '',
          name: bi.itemName,
          price: bi.unitPrice,
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
          price: bi.unitPrice,
        );
      }
      return CartEntry(item: catalogItem, variant: variant, quantity: bi.quantity);
    }).toList();
  }

  static String _labelFromName(String itemName) {
    final match = RegExp(r'\(([^)]+)\)\s*$').firstMatch(itemName);
    return match != null ? match.group(1)! : '';
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartEntry>>(CartNotifier.new);

// Fine-grained computed providers — only affected widgets rebuild
final cartSubtotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (s, e) => s + e.effectivePrice * e.quantity);
});

final cartTaxProvider = Provider<double>((ref) {
  // GST off → tax is ignored entirely, even if items carry a leftover tax_rate.
  if (!ref.watch(gstEnabledProvider)) return 0.0;
  return ref.watch(cartProvider).fold(0.0, (s, e) {
    if (e.item.taxRate == null) return s;
    return s + e.effectivePrice * e.quantity * (e.item.taxRate! / 100);
  });
});

final cartTotalProvider = Provider<double>((ref) =>
    ref.watch(cartSubtotalProvider) + ref.watch(cartTaxProvider));

// Number of distinct line entries in the cart (used for the cart badge).
// Not a sum of quantities — a 1.5 kg line still counts as one entry.
final cartItemCountProvider = Provider<int>((ref) =>
    ref.watch(cartProvider).length);
