import 'models.dart';

class CartEntry {
  final Item item;
  final ItemVariant? variant;
  final double quantity;

  /// This bill's own price for the line, typed on the order card. Same meaning
  /// as the catalog price it replaces (gross for an MRP item). Null = catalog.
  final double? priceOverride;

  /// Line discount typed on the order card: a % of the line's net when
  /// [discountPct] is set (so it scales with quantity), else [discountAmt] ₹.
  /// Like the bill-level discount it comes off the NET (pre-tax) amount.
  final double? discountPct;
  final double discountAmt;

  const CartEntry({
    required this.item,
    this.variant,
    required this.quantity,
    this.priceOverride,
    this.discountPct,
    this.discountAmt = 0,
  });

  /// Stable key identifying this line: item + optional variant. Two sizes of
  /// the same item are distinct lines; the same size stacks.
  String get key => variant == null ? item.id : '${item.id}:${variant!.id}';

  /// Catalog price as STORED on the item or variant, ignoring any override.
  double get catalogPrice => variant?.price ?? item.price ?? 0.0;

  /// Price as STORED on the item or variant — net or gross depending on
  /// [Item.priceInclusiveTax] — or this bill's [priceOverride]. Use [netPrice]
  /// for arithmetic; this is the raw figure the owner typed, kept for the
  /// price-editing UI.
  ///
  /// Both can be null — a sized item has no price of its own, and a size may
  /// inherit it. Falling back to 0 keeps the cart arithmetic finite instead of
  /// producing NaN totals; the server rejects such a line outright, and the UI
  /// requires a size before a variant item can be added at all.
  double get effectivePrice => priceOverride ?? catalogPrice;

  /// The line's tax rate as a fraction (0.05 for 5%), or 0 when untaxed.
  ///
  /// [gstEnabled] is the business-level toggle: with GST off the rate is
  /// ignored entirely, even if the item still carries one from when GST was on.
  /// The backend applies the same rule (see routes/bills.js), so passing it
  /// through here keeps the cart's figures identical to the server's.
  double _taxFraction(bool gstEnabled) =>
      (gstEnabled && item.taxRate != null) ? item.taxRate! / 100 : 0.0;

  /// Net (pre-tax) unit price, BEFORE the line discount.
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

  /// ₹ taken off this line's net, clamped to the line, rounded to paise like
  /// the server (applyLineOverrides in routes/bills.js).
  double lineDiscount(bool gstEnabled) {
    final gross = netPrice(gstEnabled) * quantity;
    final d = discountPct != null ? gross * discountPct! / 100 : discountAmt;
    return double.parse(d.clamp(0.0, gross).toStringAsFixed(2));
  }

  /// Net unit rate AFTER the line discount — what bill_items.unit_price stores.
  double discountedNetPrice(bool gstEnabled) =>
      quantity > 0 ? lineNet(gstEnabled) / quantity : netPrice(gstEnabled);

  /// Gross (tax-inclusive) unit price — what the customer actually pays per
  /// unit. Equals the stored price for an inclusive item, and price + tax for
  /// an exclusive one. Before the line discount.
  double grossPrice(bool gstEnabled) =>
      netPrice(gstEnabled) * (1 + _taxFraction(gstEnabled));

  /// This line's tax amount, charged on the discounted net.
  double lineTax(bool gstEnabled) =>
      lineNet(gstEnabled) * _taxFraction(gstEnabled);

  /// The line's pack ("1 box = 15"): the size's own when a size is picked —
  /// never the item's, which a sized item doesn't carry — else the item's.
  String? get packUnit => variant != null ? variant!.packUnit : item.packUnit;
  double? get packSize => variant != null ? variant!.packSize : item.packSize;

  /// 17 bottles → (packs: 1, loose: 2). Null under one full pack. Display only.
  ({int packs, double loose})? get packs => packBreakdown(quantity, packSize);

  /// Display name including the size, e.g. "T-Shirt (XL)".
  String get displayName =>
      variant == null ? item.name : '${item.name} (${variant!.label})';

  /// [displayName] as the billing page shows it — with "(101)" in front when
  /// the shop shows item numbers. On-screen only; bills keep [displayName].
  String billingDisplayName(bool showItemNo) => variant == null
      ? item.billingName(showItemNo)
      : '${item.billingName(showItemNo)} (${variant!.label})';

  /// Net line amount — net price × quantity less the line discount, WITHOUT
  /// tax. This is what the order card shows: the per-line figure is the pre-tax
  /// value and tax is summarised separately in the totals below. For an MRP
  /// item this is the back-calculated net, so it reads lower than the shelf
  /// price — the tax it excludes reappears in the tax row and the total still
  /// lands on the MRP.
  double lineNet(bool gstEnabled) =>
      netPrice(gstEnabled) * quantity - lineDiscount(gstEnabled);

  /// Tax-inclusive line amount (discounted net + this line's tax). Kept for
  /// callers that need the grossed line value; the order card uses [lineNet].
  double lineTotal(bool gstEnabled) =>
      lineNet(gstEnabled) + lineTax(gstEnabled);

  /// Wire fields for the line's overrides (POST /bills, update-items, offline
  /// sync): `price_override` is the NET pre-discount rate, `discount_amount`
  /// the ₹ off the line. Empty when the line is at catalog price, undiscounted.
  Map<String, dynamic> overridePayload(bool gstEnabled) {
    final disc = lineDiscount(gstEnabled);
    return {
      if (priceOverride != null) 'price_override': netPrice(gstEnabled),
      if (disc > 0) 'discount_amount': disc,
    };
  }

  /// [clearOverrides] drops the price override and discount (copyWith can't
  /// set a field back to null on its own).
  CartEntry copyWith({
    Item? item,
    ItemVariant? variant,
    double? quantity,
    double? priceOverride,
    double? discountPct,
    double? discountAmt,
    bool clearOverrides = false,
  }) {
    return CartEntry(
      item: item ?? this.item,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
      priceOverride:
          clearOverrides ? priceOverride : (priceOverride ?? this.priceOverride),
      discountPct:
          clearOverrides ? discountPct : (discountPct ?? this.discountPct),
      discountAmt: discountAmt ?? (clearOverrides ? 0 : this.discountAmt),
    );
  }
}
