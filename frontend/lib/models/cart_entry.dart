import 'models.dart';

class CartEntry {
  final Item item;
  final int quantity;

  const CartEntry({required this.item, required this.quantity});

  double get lineTotal {
    final tax = item.taxRate != null ? (item.taxRate! / 100) : 0.0;
    return item.price * quantity * (1 + tax);
  }

  CartEntry copyWith({Item? item, int? quantity}) {
    return CartEntry(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
    );
  }
}
