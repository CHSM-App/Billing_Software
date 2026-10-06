import 'models.dart';

class CartEntry {
  final Item item;
  final ItemVariant? variant;
  final double quantity;

  const CartEntry({required this.item, this.variant, required this.quantity});

  /// Stable key identifying this line: item + optional variant. Two sizes of
  /// the same item are distinct lines; the same size stacks.
  String get key => variant == null ? item.id : '${item.id}:${variant!.id}';

  /// Price as STORED on the item or variant — net or gross depending on
  /// [Item.priceInclusiveTax]. Use [netPrice] for arithmetic; this is the raw
  /// figure the owner typed, kept for the price-editing UI.
  ///
  /// Both can be null — a sized item has no price of its own, and a size may
  /// inherit it. Falling back to 0 keeps the cart arithmetic finite instead of
  /// producing NaN totals; the server rejects such a line outright, and the UI
  /// requires a size before a variant item can be added at all.
  double get effectivePrice => variant?.price ?? item.price ?? 0.0;

  /// The line's tax rate as a fraction (0.05 for 5%), or 0 when untaxed.
  ///
  /// [gstEnabled] is the business-level toggle: with GST off the rate is
  /// ignored entirely, even if the item still carries one from when GST was on.
  /// The backend applies the same rule (see routes/bills.js), so passing it
  /// through here keeps the cart's figures identical to the server's.
  double _taxFraction(bool gstEnabled) =>
      (gstEnabled && item.taxRate != null) ? item.taxRate! / 100 : 0.0;

  /// Net (pre-tax) unit price — what every total is built from.
  ///
  /// For an exclusive-priced item this IS the stored price. For an inclusive
  /// (MRP) item the tax is stripped back out: net = gross / (1 + rate). This
  /// mirrors resolveNetPriceAndRate in backend/src/routes/bills.js, so the
  /// figures shown while billing match what the server stores on the bill.
  ///
  /// With GST off there is no tax to extract, so an MRP price is already the
  /// whole amount charged and passes through untouched.
  double netPrice(bool gstEnabled) {
    final t = _taxFraction(gstEnabled);
    if (t == 0 || !item.priceInclusiveTax) return effectivePrice;
    return effectivePrice / (1 + t);
  }

  /// Gross (tax-inclusive) unit price — what the customer actually pays per
  /// unit. Equals the stored price for an inclusive item, and price + tax for
  /// an exclusive one.
  double grossPrice(bool gstEnabled) =>
      netPrice(gstEnabled) * (1 + _taxFraction(gstEnabled));

  /// This line's tax amount.
  double lineTax(bool gstEnabled) =>
      netPrice(gstEnabled) * quantity * _taxFraction(gstEnabled);

  /// Display name including the size, e.g. "T-Shirt (XL)".
  String get displayName =>
      variant == null ? item.name : '${item.name} (${variant!.label})';

  /// Net line amount — net price × quantity, WITHOUT tax. This is what the
  /// order card shows: the per-line figure is the pre-tax value and tax is
  /// summarised separately in the totals below. For an MRP item this is the
  /// back-calculated net, so it reads lower than the shelf price — the tax it
  /// excludes reappears in the tax row and the total still lands on the MRP.
  double lineNet(bool gstEnabled) => netPrice(gstEnabled) * quantity;

  /// Tax-inclusive line amount (net + this line's tax). Kept for callers that
  /// need the grossed line value; the order card uses [lineNet] instead.
  double lineTotal(bool gstEnabled) => grossPrice(gstEnabled) * quantity;

  CartEntry copyWith({Item? item, ItemVariant? variant, double? quantity}) {
    return CartEntry(
      item: item ?? this.item,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
    );
  }
}
