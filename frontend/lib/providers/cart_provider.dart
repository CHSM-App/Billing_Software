import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../models/cart_entry.dart';

class CartNotifier extends Notifier<List<CartEntry>> {
  @override
  List<CartEntry> build() => [];

  void addItem(Item item) {
    final idx = state.indexWhere((e) => e.item.id == item.id);
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          i == idx ? state[i].copyWith(quantity: state[i].quantity + 1) : state[i]
      ];
    } else {
      state = [...state, CartEntry(item: item, quantity: 1)];
    }
  }

  void changeQty(String itemId, int delta) {
    final idx = state.indexWhere((e) => e.item.id == itemId);
    if (idx < 0) return;
    final newQty = state[idx].quantity + delta;
    if (newQty <= 0) {
      state = state.where((e) => e.item.id != itemId).toList();
    } else {
      state = [
        for (int i = 0; i < state.length; i++)
          i == idx ? state[i].copyWith(quantity: newQty) : state[i]
      ];
    }
  }

  void setQty(String itemId, int qty) {
    if (qty <= 0) {
      state = state.where((e) => e.item.id != itemId).toList();
    } else {
      final idx = state.indexWhere((e) => e.item.id == itemId);
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
      return CartEntry(item: catalogItem, quantity: bi.quantity.toInt());
    }).toList();
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartEntry>>(CartNotifier.new);

// Fine-grained computed providers — only affected widgets rebuild
final cartSubtotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (s, e) => s + e.item.price * e.quantity);
});

final cartTaxProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (s, e) {
    if (e.item.taxRate == null) return s;
    return s + e.item.price * e.quantity * (e.item.taxRate! / 100);
  });
});

final cartTotalProvider = Provider<double>((ref) =>
    ref.watch(cartSubtotalProvider) + ref.watch(cartTaxProvider));

final cartItemCountProvider = Provider<int>((ref) =>
    ref.watch(cartProvider).fold(0, (s, e) => s + e.quantity));
