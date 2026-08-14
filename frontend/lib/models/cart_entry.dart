import 'models.dart';

class CartEntry {
  final Item item;
  final ItemVariant? variant;
  final double quantity;

  const CartEntry({required this.item, this.variant, required this.quantity});

  /// Stable key identifying this line: item + optional variant. Two sizes of
  /// the same item are distinct lines; the same size stacks.
  String get key => variant == null ? item.id : '${item.id}:${variant!.id}';

  /// Price actually charged: the variant's price when set, else the item's.
  double get effectivePrice => variant?.price ?? item.price;

  /// Display name including the size, e.g. "T-Shirt (XL)".
  String get displayName =>
      variant == null ? item.name : '${item.name} (${variant!.label})';

  /// Net line amount — price × quantity, WITHOUT tax. This is what the order
  /// card shows: prices are tax-exclusive, so the per-line figure is the pre-tax
  /// value and tax is summarised separately in the totals below.
  double get lineNet => effectivePrice * quantity;

  /// Tax-inclusive line amount (net + this line's tax). Kept for callers that
  /// need the grossed line value; the order card uses [lineNet] instead.
  double get lineTotal {
    final tax = item.taxRate != null ? (item.taxRate! / 100) : 0.0;
    return effectivePrice * quantity * (1 + tax);
  }

  CartEntry copyWith({Item? item, ItemVariant? variant, double? quantity}) {
    return CartEntry(
      item: item ?? this.item,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
    );
  }
}
