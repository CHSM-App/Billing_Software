import 'dart:convert';

/// Formats a quantity for display: whole numbers show without a decimal
/// (`2`), fractional weights show up to three trimmed decimals (`1.5`,
/// `0.25`). Used for cart rows, receipts, and history.
String formatQty(double qty) {
  if (qty % 1 == 0) return qty.toInt().toString();
  return qty
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Short display name for a unit, shown after a quantity ("2 kg", "3 btl").
/// SI symbols for metric units; the rest follow India's GST UQC names in the
/// lowercase form shop bills use. Dropdowns keep the full localized name.
String unitShort(String unit) => const {
      'piece': 'pcs',
      'kg': 'kg',
      'g': 'g',
      'litre': 'L',
      'ml': 'ml',
      'metre': 'm',
      'dozen': 'doz',
      'plate': 'plt',
      'packet': 'pkt',
      'box': 'box',
      'bottle': 'btl',
      'pair': 'pr',
      'set': 'set',
      'bundle': 'bdl',
      'bag': 'bag',
      'sqft': 'sqft',
      'ton': 't',
      'quintal': 'qtl',
      'roll': 'roll',
      'case': 'cs',
      'crate': 'crt',
      'carton': 'ctn',
    }[unit] ??
    unit;

/// EXPERIMENT (docs/experiments/receipt_units.md): item id → unit, refreshed
/// by ItemsNotifier, so receipts can print "2 kg" — bill lines carry no unit.
/// ponytail: global catalog map; store the unit on bill_items if this sticks.
Map<String, String> catalogUnits = const {};

/// A bill line's quantity for a receipt, with its short unit when the catalog
/// knows the item: "2 kg", "1.5 L", or just "3".
String receiptQty(BillItem item, String qty) {
  final unit = item.itemId == null ? null : catalogUnits[item.itemId];
  return unit == null ? qty : '$qty ${unitShort(unit)}';
}

/// [qty] base units as whole packs plus the loose rest: 17 bottles with a box of
/// 15 is (packs: 1, loose: 2). Null when there is no pack or not one full pack.
/// Display only: stock and bills always count base units.
({int packs, double loose})? packBreakdown(double qty, double? packSize) {
  if (packSize == null || packSize <= 1) return null;
  // The epsilon keeps 15.0 / 15 from flooring to 0 on a float that is 14.999…
  final packs = (qty / packSize + 1e-9).floor();
  if (packs < 1) return null;
  final loose = double.parse((qty - packs * packSize).toStringAsFixed(3));
  return (packs: packs, loose: loose < 0 ? 0 : loose);
}

/// Strips the leading letter prefix (the business's bill prefix, 'INV' by
/// default) and its dash from a bill number: 'INV-0007' → '0007',
/// 'INV-a7f4-0001' → 'a7f4-0001'. Numbers without such a prefix are returned
/// unchanged. Used wherever the number is shown to the customer.
String stripBillPrefix(String billNumber) =>
    billNumber.replaceFirst(RegExp(r'^[A-Za-z]+-'), '');

class User {
  final String id;
  final String name;
  final String phone;
  final String role;

  User({required this.id, required this.name, required this.phone, required this.role});

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        name: j['name'],
        phone: j['phone'],
        role: j['role'],
      );
}

class Business {
  final String id;
  final String name;
  final String businessType;
  final String? address;
  final bool inventoryEnabled;
  final bool hasBarcodeScanner;

  Business({
    required this.id,
    required this.name,
    required this.businessType,
    this.address,
    required this.inventoryEnabled,
    required this.hasBarcodeScanner,
  });

  factory Business.fromJson(Map<String, dynamic> j) => Business(
        id: j['id'],
        name: j['name'],
        businessType: j['business_type'],
        address: j['address'],
        inventoryEnabled: j['inventory_enabled'] == true,
        hasBarcodeScanner: j['has_barcode_scanner'] == true,
      );
}

/// A sellable variant of an item (e.g. a size S/M/L/XL) with its own stock and
/// optional price. When [price] is null the parent item's price applies.
class ItemVariant {
  final String id;
  final String itemId;
  final String label;
  final double? price;
  final String? barcode;
  final double? stockQuantity;
  final double? lowStockThreshold;

  /// This size's pack ("1 box = 24"), or null. See [packBreakdown].
  final String? packUnit;
  final double? packSize;
  final int sortOrder;
  final bool isActive;

  ItemVariant({
    required this.id,
    required this.itemId,
    required this.label,
    this.price,
    this.barcode,
    this.stockQuantity,
    this.lowStockThreshold,
    this.packUnit,
    this.packSize,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory ItemVariant.fromJson(Map<String, dynamic> j) => ItemVariant(
        id: j['id'],
        itemId: j['item_id'],
        label: j['label'],
        price: j['price'] != null ? double.parse(j['price'].toString()) : null,
        barcode: j['barcode'],
        stockQuantity: j['stock_quantity'] != null
            ? double.parse(j['stock_quantity'].toString())
            : null,
        lowStockThreshold: (j['low_stock_threshold'] as num?)?.toDouble(),
        packUnit: j['pack_unit'] as String?,
        packSize: j['pack_size'] != null
            ? double.parse(j['pack_size'].toString())
            : null,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        isActive: j['is_active'] == true || j['is_active'] == 1,
      );

  bool get isLowStock =>
      stockQuantity != null &&
      lowStockThreshold != null &&
      stockQuantity! <= lowStockThreshold!;
}

class Item {
  final String id;
  final String businessId;
  final String name;
  final String? barcode;

  /// Optional shop-assigned number ("101"); billing search matches it.
  final String? itemNo;

  /// Coarse grouping above [category] — "Chinese" to its "Chinese Starters".
  /// Free text and optional, exactly like [category]: null on every item saved
  /// before major categories existed, and on any item whose owner leaves the
  /// field blank. Billing treats a null major as the unset bucket and never
  /// hides the item.
  final String? majorCategory;

  /// The item's subcategory, and the level the item sheets group by. Free text;
  /// a category exists only while some item carries that exact string.
  final String? category;

  /// The item's own price, or null when it is sold only through its variants —
  /// each size then carries its own price. Use [CartEntry.effectivePrice] rather
  /// than reading this directly when billing.
  final double? price;
  final double? taxRate;

  /// Whether [price] (and each variant's price) already contains GST.
  ///
  /// false — the price is NET and tax is added on top: 20 @5% bills at 21.00.
  /// true  — the price is the GROSS/MRP the customer pays: 20 @5% bills at
  ///         20.00, of which 0.95 is tax. Billing back-calculates the net rate.
  ///
  /// Defaults to false so items saved before this flag existed keep billing
  /// exactly as they did. Has no effect when GST is off or [taxRate] is null —
  /// there is no tax to extract, so the price is net either way.
  final bool priceInclusiveTax;
  final String? hsnCode;
  final double? stockQuantity;
  final double? lowStockThreshold;
  final String unit;

  /// Pack of a plain item ("1 box = 15" [unit]), or null. A sized item keeps
  /// its packs on its variants. See [packBreakdown].
  final String? packUnit;
  final double? packSize;
  final List<ItemVariant> variants;
  final bool isActive;

  /// Customer-facing dish photo URL. Only populated by the owner-only Menu
  /// Photos endpoints; the billing/items list leaves this null so photos never
  /// load during billing.
  final String? imageUrl;

  /// "Retail & Warranty" shops only: whether selling this item should
  /// auto-create a warranty record (routes/bills.js' auto-create hook).
  final bool warrantyEligible;

  /// The warranty period (months) seeded onto an auto-created record. Null
  /// when [warrantyEligible] is false.
  final int? defaultWarrantyMonths;

  Item({
    required this.id,
    required this.businessId,
    required this.name,
    this.barcode,
    this.itemNo,
    this.majorCategory,
    this.category,
    this.price,
    this.taxRate,
    this.priceInclusiveTax = false,
    this.hsnCode,
    this.stockQuantity,
    this.lowStockThreshold,
    this.unit = 'piece',
    this.packUnit,
    this.packSize,
    this.variants = const [],
    required this.isActive,
    this.imageUrl,
    this.warrantyEligible = false,
    this.defaultWarrantyMonths,
  });

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'],
        businessId: j['business_id'],
        name: j['name'],
        barcode: j['barcode'],
        itemNo: j['item_no'] as String?,
        majorCategory: j['major_category'],
        category: j['category'],
        price: j['price'] != null ? double.parse(j['price'].toString()) : null,
        taxRate: j['tax_rate'] != null ? double.parse(j['tax_rate'].toString()) : null,
        // SQL Server BIT arrives as bool or 0/1 depending on the driver/cache.
        priceInclusiveTax:
            j['price_inclusive_tax'] == true || j['price_inclusive_tax'] == 1,
        hsnCode: j['hsn_code'] as String?,
        stockQuantity: j['stock_quantity'] != null ? double.parse(j['stock_quantity'].toString()) : null,
        lowStockThreshold: (j['low_stock_threshold'] as num?)?.toDouble(),
        unit: (j['unit'] as String?) ?? 'piece',
        packUnit: j['pack_unit'] as String?,
        packSize: j['pack_size'] != null
            ? double.parse(j['pack_size'].toString())
            : null,
        variants: (j['variants'] as List? ?? [])
            .map((v) => ItemVariant.fromJson(v))
            .toList(),
        isActive: j['is_active'] == true || j['is_active'] == 1,
        imageUrl: j['image_url'] as String?,
        warrantyEligible:
            j['warranty_eligible'] == true || j['warranty_eligible'] == 1,
        defaultWarrantyMonths: (j['default_warranty_months'] as num?)?.toInt(),
      );

  /// Whether this item is sold by a divisible measure (kg, g, litre, ...)
  /// rather than as whole pieces. Drives decimal-quantity entry in the cart.
  bool get isMeasured => unit != 'piece';

  /// Whether the cashier must pick a size before this item can be added.
  bool get hasVariants => variants.isNotEmpty;

  /// Name as the billing page shows it: "(101) Masala Dosa" when the shop has
  /// turned on [showItemNo] (Settings). Bills still store the plain [name].
  String billingName(bool showItemNo) =>
      showItemNo && (itemNo?.isNotEmpty ?? false) ? '($itemNo) $name' : name;

  /// Same item with a different set of sizes. Used to re-attach variants when a
  /// partial API response omits them, so a sized item never degrades into a
  /// plain one (which would bill at the base price).
  Item copyWithVariants(List<ItemVariant> newVariants) => Item(
        id: id,
        businessId: businessId,
        name: name,
        barcode: barcode,
        itemNo: itemNo,
        majorCategory: majorCategory,
        category: category,
        price: price,
        taxRate: taxRate,
        priceInclusiveTax: priceInclusiveTax,
        hsnCode: hsnCode,
        stockQuantity: stockQuantity,
        lowStockThreshold: lowStockThreshold,
        unit: unit,
        packUnit: packUnit,
        packSize: packSize,
        variants: newVariants,
        isActive: isActive,
        imageUrl: imageUrl,
        warrantyEligible: warrantyEligible,
        defaultWarrantyMonths: defaultWarrantyMonths,
      );

  bool get isLowStock =>
      stockQuantity != null &&
      lowStockThreshold != null &&
      stockQuantity! <= lowStockThreshold!;
}

/// A stock-tracked ingredient (bun, patty, cheese) that is consumed by a dish's
/// recipe. Raw materials never appear on the billing page — only sellable items
/// are billed; selling a dish deducts its recipe's raw materials behind the scenes.
class RawMaterial {
  final String id;
  final String businessId;
  final String name;
  final String unit;
  final double? stockQuantity;
  final double? lowStockThreshold;
  final bool isActive;

  RawMaterial({
    required this.id,
    required this.businessId,
    required this.name,
    this.unit = 'piece',
    this.stockQuantity,
    this.lowStockThreshold,
    this.isActive = true,
  });

  factory RawMaterial.fromJson(Map<String, dynamic> j) => RawMaterial(
        id: j['id'],
        businessId: j['business_id'],
        name: j['name'],
        unit: (j['unit'] as String?) ?? 'piece',
        stockQuantity: j['stock_quantity'] != null
            ? double.parse(j['stock_quantity'].toString())
            : null,
        lowStockThreshold: (j['low_stock_threshold'] as num?)?.toDouble(),
        isActive: j['is_active'] == true || j['is_active'] == 1,
      );

  bool get isLowStock =>
      stockQuantity != null &&
      lowStockThreshold != null &&
      stockQuantity! <= lowStockThreshold!;
}

/// One line of a dish's recipe: how much of a given raw material one unit of the
/// dish consumes.
class RecipeRow {
  final String rawMaterialId;
  final String rawMaterialName;
  final String rawMaterialUnit;
  final double quantity;

  /// The size this row belongs to, or null for an item that has no sizes.
  final String? variantId;

  RecipeRow({
    required this.rawMaterialId,
    required this.rawMaterialName,
    required this.rawMaterialUnit,
    required this.quantity,
    this.variantId,
  });

  factory RecipeRow.fromJson(Map<String, dynamic> j) => RecipeRow(
        rawMaterialId: j['raw_material_id'],
        rawMaterialName: (j['raw_material_name'] as String?) ?? '',
        rawMaterialUnit: (j['raw_material_unit'] as String?) ?? 'piece',
        quantity: double.parse(j['quantity'].toString()),
        variantId: j['variant_id'] as String?,
      );
}

class BillItem {
  final String id;
  final String billId;
  final String? itemId;
  final String? variantId;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double? taxRate;
  final String? hsnCode;
  final double lineTotal;
  /// ₹ taken off this line on the order card. Display only: [unitPrice] is
  /// already the discounted net rate, so totals never subtract it again.
  final double discountAmount;
  /// 'pending' | 'ready' | 'delivered' — the dish's kitchen progress. Only the
  /// draft-bill responses carry it; null elsewhere (and on offline drafts).
  final String? kitchenStatus;

  BillItem({
    required this.id,
    required this.billId,
    this.itemId,
    this.variantId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.taxRate,
    this.hsnCode,
    required this.lineTotal,
    this.discountAmount = 0,
    this.kitchenStatus,
  });

  /// Customer-facing line name: notes the item discount, e.g.
  /// "Egg Biryani (Disc ₹20.00)". Kitchen tickets keep plain [itemName].
  String get receiptName => discountAmount > 0
      ? '$itemName (Disc ₹${discountAmount.toStringAsFixed(2)})'
      : itemName;

  /// The receipt's Price column: the rate BEFORE the line discount. A discount
  /// must not look like a price change — 2 × ₹180 less ₹50 prints as Price
  /// 180, Total 310, not Price 155. Recovered from the stored discounted
  /// [unitPrice]; an edited price is already in [unitPrice], so it shows.
  double get receiptPrice =>
      quantity > 0 ? unitPrice + discountAmount / quantity : unitPrice;

  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
        // The credit endpoints return a receipt-only item shape without id /
        // bill_id (not needed to display or print a line). Default them so the
        // model parses there as well as on the full bill responses.
        id: j['id'] ?? '',
        billId: j['bill_id'] ?? '',
        itemId: j['item_id'],
        variantId: j['variant_id'],
        itemName: j['item_name'],
        quantity: double.parse(j['quantity'].toString()),
        unitPrice: double.parse(j['unit_price'].toString()),
        taxRate: j['tax_rate'] != null ? double.parse(j['tax_rate'].toString()) : null,
        hsnCode: j['hsn_code'] as String?,
        lineTotal: double.parse(j['line_total'].toString()),
        discountAmount:
            double.tryParse((j['discount_amount'] ?? 0).toString()) ?? 0.0,
        kitchenStatus: j['kitchen_status'] as String?,
      );
}

/// A bill-level additional charge — delivery, packaging, service, etc.
///
/// Charges are added on top of the taxed items: they are part of [Bill.total]
/// (total = subtotal + tax + charges), sit outside the taxable base (no GST)
/// and are never reduced by the discount. Mirrors backend/src/charges.js.
class BillCharge {
  final String name;
  final double amount;

  const BillCharge({required this.name, required this.amount});

  factory BillCharge.fromJson(Map<String, dynamic> j) => BillCharge(
        name: (j['name'] ?? '').toString().trim(),
        amount: double.tryParse((j['amount'] ?? 0).toString()) ?? 0.0,
      );

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount};

  /// Parses whatever a charge list arrives as: the server's JSON array, an
  /// offline row's encoded string, or null. Incomplete entries are dropped.
  static List<BillCharge> listFrom(dynamic raw) {
    dynamic list = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        list = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => BillCharge.fromJson(Map<String, dynamic>.from(m)))
        .where((c) => c.name.isNotEmpty && c.amount > 0)
        .toList();
  }

  /// JSON text for the offline queue / sync payloads.
  static String encode(List<BillCharge> charges) =>
      jsonEncode(charges.map((c) => c.toJson()).toList());

  static double sum(List<BillCharge> charges) =>
      charges.fold(0.0, (s, c) => s + c.amount);
}

/// A charge description the business has used before, offered as an
/// autocomplete suggestion while adding charges to a bill. Only the
/// description is suggested — the amount is always entered per bill.
class ChargeSuggestion {
  final String name;
  /// How many bills have carried it — drives the ordering.
  final int uses;

  const ChargeSuggestion({required this.name, this.uses = 1});

  factory ChargeSuggestion.fromJson(Map<String, dynamic> j) => ChargeSuggestion(
        name: (j['name'] ?? '').toString().trim(),
        uses: int.tryParse((j['uses'] ?? 1).toString()) ?? 1,
      );

  Map<String, dynamic> toJson() => {'name': name, 'uses': uses};

  ChargeSuggestion copyWith({String? name, int? uses}) => ChargeSuggestion(
        name: name ?? this.name,
        uses: uses ?? this.uses,
      );
}

class Bill {
  final String id;
  final String businessId;
  final String billNumber;
  final String? tableId;
  /// Display number of the table this bill belongs to (null for retail bills).
  /// Printed on the receipt so a table order is identifiable.
  final String? tableNumber;
  final String? customerName;
  final String? customerPhone;
  /// Optional B2B details (migration 061), printed under Bill To. Null on
  /// older bills and from older backends.
  final String? customerAddress;
  final String? customerGstin;
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  /// Sum of [additionalCharges]. Already INCLUDED in [total]
  /// (total = subtotal + tax + charges), so [grandTotal] needs no extra term.
  final double chargesAmount;
  /// Itemised additional charges (delivery, packaging, ...) for display.
  final List<BillCharge> additionalCharges;
  /// Warranty details captured at billing time (migration 065) — e.g. a
  /// tyre's vehicle KM reading — printed on the receipt when the owner's
  /// Billing Setup toggle allows it. Empty for most bills.
  final List<WarrantyExtraField> warrantyExtraData;
  final double total;
  /// Signed invoice-level round-off adjustment (e.g. -0.22, +0.40). 0 when the
  /// business has rounding disabled. NEVER folded into subtotal/tax/total — the
  /// final payable is [grandTotal] = total - discount + roundOff.
  final double roundOff;
  /// cash / upi / card / other / credit — or 'split', paid in the [payments].
  final String paymentMode;
  final String status;
  /// 'paid' | 'unpaid'. Unpaid means a credit (udhaari) bill awaiting
  /// settlement. Defaults to 'paid' for older bills / partial responses.
  final String paymentStatus;
  final String createdByUserId;

  /// Name of the staff member who settled the bill ("Billed by"), or of the
  /// one who started it on older bills and drafts. Null when unknown — a
  /// queued offline bill, or a bill shape that doesn't carry it.
  final String? billedBy;

  /// The [PriceList] a held bill was priced with, so reopening it keeps the
  /// list selected. Null for default prices and on older bills.
  final String? priceListId;

  /// When the bill was first written — for a held order, the ORDER time.
  final DateTime createdAt;
  /// When the sale was finalized. Null for a draft, and for an unsynced
  /// offline bill (its [createdAt] already is the moment it was finalized).
  final DateTime? finalizedAt;
  final List<BillItem> items;

  /// The bill's date: what it prints as "Date" and what history and reports
  /// file it under. A bill held on the 7th and settled on the 12th is dated
  /// the 12th; a draft has only its order time.
  DateTime get billDate => finalizedAt ?? createdAt;

  /// True when the bill sat open before being settled, so its order time is
  /// worth showing beside [billDate].
  bool get wasHeld =>
      finalizedAt != null &&
      finalizedAt!.difference(createdAt) >= const Duration(minutes: 1);

  /// The parts of a split bill, e.g. cash 300 + upi 200 + credit 200. Empty
  /// for a bill paid in one mode.
  final List<BillPayment> payments;

  /// The part of this bill left on credit — its 'credit' payment. Null for a
  /// whole-bill credit (all of [grandTotal] is owed) and for paid bills.
  final double? creditAmount;

  /// Old credit bills paid off along with this one — printed after the grand
  /// total as "Prev. due · Bill 0007 ₹500". Empty for most bills.
  final List<CollectedDue> collected;

  /// The money behind [collected], per mode — with this bill's own parts it is
  /// everything the customer handed over (see [tendered]).
  final List<BillPayment> collectedByMode;

  /// For a credit bill: every payment made on it since, oldest first — from a
  /// later bill ("paid in Bill 0012") or from the Credit tab.
  final List<CreditPaymentEntry> creditPayments;

  /// Set only on a bill that began life as an online-store order: the advance
  /// the customer already paid and the UPI reference they typed. Both live on
  /// the ORDER, not the bill, and are joined in by the API — which also means
  /// orders accepted before this shipped show their details too.
  ///
  /// The counter needs these before handing a delivery over: without them a
  /// prepaid order looks unpaid and gets charged in full a second time.
  final double onlinePaidAmount;
  final String? onlinePaymentTxnId;
  final String? onlineOrderNumber;

  /// True when money was taken online for this bill.
  bool get hasOnlinePrepayment => onlinePaidAmount > 0;

  /// True when this is a credit bill that hasn't been settled yet.
  bool get isUnpaidCredit => paymentStatus == 'unpaid';

  /// [billNumber] without its letter prefix, for customer-facing output
  /// (printed receipts, invoice PDFs, WhatsApp). 'INV-0007' → '0007',
  /// offline 'INV-a7f4-0001' → 'a7f4-0001'. Numbers with no prefix are
  /// returned unchanged. The full [billNumber] stays the in-app identifier.
  String get displayNumber => stripBillPrefix(billNumber);

  /// The final amount the customer pays: total, less discount, plus round-off.
  double get grandTotal => total - discountAmount + roundOff;

  /// Full name of [billedBy], whitespace collapsed — "Ramesh Patil" from
  /// "  Ramesh  Patil " — for receipts and History. Null when unknown or blank.
  String? get billedByName {
    final n = billedBy?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    return n.isEmpty ? null : n;
  }

  /// What an unpaid bill still owes: its credit part (else the whole bill),
  /// less what has been paid on it. Same rule as the server's DUE
  /// (src/creditPayments.js).
  double get amountDue => double.parse(
      ((creditAmount ?? grandTotal) - creditPaid).toStringAsFixed(2));

  /// Paid so far on this credit bill.
  double get creditPaid => creditPayments.fold(0.0, (s, p) => s + p.amount);

  /// Old dues this bill collected, in total.
  double get collectedTotal => collected.fold(0.0, (s, c) => s + c.amount);

  /// What the customer handed over: this bill plus the old dues it collected.
  double get totalPaid => grandTotal + collectedTotal;

  bool get isSplit => paymentMode == 'split' && payments.isNotEmpty;

  /// Everything the customer handed over, per mode: this bill's own parts
  /// plus the money that paid off [collected] old dues. Without collected
  /// dues it is just this bill's parts (one entry for a single-mode bill).
  List<BillPayment> get tendered {
    final own = isSplit ? payments : [BillPayment(paymentMode, grandTotal)];
    if (collected.isEmpty) return own;
    // Not saved yet (a preview): its parts, or its one mode, already cover
    // the old dues too.
    if (collectedByMode.isEmpty) {
      return isSplit ? payments : [BillPayment(paymentMode, totalPaid)];
    }
    final byMode = <String, double>{};
    for (final p in [...own, ...collectedByMode]) {
      byMode[p.mode] = (byMode[p.mode] ?? 0) + p.amount;
    }
    return [
      for (final e in byMode.entries)
        BillPayment(e.key, double.parse(e.value.toStringAsFixed(2))),
    ];
  }

  /// How the bill was paid, for history, receipts and exports:
  /// "Cash" or "Cash ₹300.00 + UPI ₹200.00 + Credit ₹200.00". With old dues
  /// collected it is everything handed over, not just this bill's share.
  /// [nameOf] turns a mode into its display name.
  String tenderLabel(String Function(String mode) nameOf) {
    final parts = tendered;
    if (parts.length == 1 && collected.isEmpty) return nameOf(parts.first.mode);
    return parts
        .map((p) => '${nameOf(p.mode)} ₹${p.amount.toStringAsFixed(2)}')
        .join(' + ');
  }

  Bill({
    required this.id,
    required this.businessId,
    required this.billNumber,
    this.tableId,
    this.tableNumber,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.customerGstin,
    required this.subtotal,
    required this.taxAmount,
    this.discountAmount = 0.0,
    this.chargesAmount = 0.0,
    this.additionalCharges = const [],
    this.warrantyExtraData = const [],
    required this.total,
    this.roundOff = 0.0,
    required this.paymentMode,
    required this.status,
    this.paymentStatus = 'paid',
    required this.createdByUserId,
    this.billedBy,
    this.priceListId,
    required this.createdAt,
    this.finalizedAt,
    required this.items,
    // Absent on every bill that did not come from the online store, and on the
    // lighter bill shapes the credit endpoints return.
    this.onlinePaidAmount = 0.0,
    this.onlinePaymentTxnId,
    this.onlineOrderNumber,
    this.payments = const [],
    this.creditAmount,
    this.collected = const [],
    this.collectedByMode = const [],
    this.creditPayments = const [],
  });

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: j['id'],
        // The credit endpoints return a lighter bill shape without these
        // fields; default them so the model parses in both contexts.
        businessId: j['business_id'] ?? '',
        billNumber: j['bill_number'],
        tableId: j['table_id'],
        tableNumber: j['table_number'],
        customerName: j['customer_name'],
        customerPhone: j['customer_phone'],
        customerAddress: j['customer_address'] as String?,
        customerGstin: j['customer_gstin'] as String?,
        subtotal: double.parse(j['subtotal'].toString()),
        taxAmount: double.parse(j['tax_amount'].toString()),
        discountAmount: j['discount_amount'] != null
            ? double.parse(j['discount_amount'].toString())
            : 0.0,
        chargesAmount: j['charges_amount'] != null
            ? double.parse(j['charges_amount'].toString())
            : 0.0,
        additionalCharges: BillCharge.listFrom(j['additional_charges']),
        warrantyExtraData: (j['warranty_extra_data'] as List? ?? [])
            .map((e) => WarrantyExtraField.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: double.parse(j['total'].toString()),
        roundOff: j['round_off'] != null
            ? double.parse(j['round_off'].toString())
            : 0.0,
        paymentMode: j['payment_mode'],
        status: j['status'] ?? 'finalized',
        paymentStatus: j['payment_status'] ?? 'paid',
        createdByUserId: j['created_by_user_id'] ?? '',
        billedBy: j['billed_by'] as String?,
        priceListId: j['price_list_id'] as String?,
        createdAt: DateTime.parse(j['created_at']),
        finalizedAt: j['finalized_at'] == null
            ? null
            : DateTime.tryParse('${j['finalized_at']}'),
        onlinePaidAmount:
            double.tryParse('${j['online_paid_amount'] ?? 0}') ?? 0.0,
        onlinePaymentTxnId: j['online_payment_txn_id'] as String?,
        onlineOrderNumber: j['online_order_number'] as String?,
        items: (j['items'] as List? ?? []).map((i) => BillItem.fromJson(i)).toList(),
        payments: BillPayment.listFrom(j['payments']),
        creditAmount: j['credit_amount'] != null
            ? double.tryParse(j['credit_amount'].toString())
            : null,
        collected: [
          for (final c in (j['collected'] as List? ?? const []).whereType<Map>())
            CollectedDue(
              billId: '${c['bill_id']}',
              billNumber: '${c['bill_number']}',
              amount: double.tryParse('${c['amount']}') ?? 0.0,
            ),
        ],
        collectedByMode: BillPayment.listFrom(j['collected_by_mode']),
        creditPayments: [
          for (final p
              in (j['credit_payments'] as List? ?? const []).whereType<Map>())
            CreditPaymentEntry(
              amount: double.tryParse('${p['amount']}') ?? 0.0,
              mode: '${p['mode']}',
              createdAt: DateTime.tryParse('${p['created_at']}') ??
                  DateTime.now(),
              paidInBillNumber: p['paid_in_bill_number'] as String?,
            ),
        ],
      );
}

/// A named set of prices — "Party", "Wholesale" — the cashier can bill with.
///
/// [adjustPct] is an optional % on every default price (+10 = 10% more);
/// [prices] holds fixed prices keyed like [CartEntry.key] (`itemId`, or
/// `itemId:variantId` for a size), in the same form as the catalog price
/// (gross for an MRP item). Billing sends the result as the line's
/// price_override, so nothing else about pricing changes.
class PriceList {
  final String id;
  final String name;
  final double? adjustPct;
  final Map<String, double> prices;

  const PriceList({
    required this.id,
    required this.name,
    this.adjustPct,
    this.prices = const {},
  });

  factory PriceList.fromJson(Map<String, dynamic> j) => PriceList(
        id: j['id'],
        name: j['name'],
        adjustPct: j['adjust_pct'] == null
            ? null
            : double.tryParse(j['adjust_pct'].toString()),
        prices: {
          for (final e in (j['items'] as List? ?? const []).whereType<Map>())
            e['variant_id'] == null
                ? '${e['item_id']}'
                : '${e['item_id']}:${e['variant_id']}':
                double.parse(e['price'].toString()),
        },
      );

  /// This list's price for an item or one of its sizes: the fixed price,
  /// else the default price moved by [adjustPct] (to paise), else null —
  /// meaning the default price stands. A size never borrows its item's
  /// fixed price; sizes are priced on their own.
  double? priceFor(Item item, [ItemVariant? variant]) {
    final fixed =
        prices[variant == null ? item.id : '${item.id}:${variant.id}'];
    if (fixed != null) return fixed;
    final base = variant != null ? (variant.price ?? item.price) : item.price;
    final pct = adjustPct;
    if (base == null || pct == null || pct == 0) return null;
    return double.parse((base * (1 + pct / 100)).toStringAsFixed(2));
  }
}

/// An old credit bill paid off (in full or in part) along with a new bill.
class CollectedDue {
  final String billId;
  final String billNumber;
  final double amount;

  const CollectedDue(
      {required this.billId, required this.billNumber, required this.amount});

  /// [billNumber] without its prefix, for the customer.
  String get displayNumber => stripBillPrefix(billNumber);
}

/// One payment made on a credit bill.
class CreditPaymentEntry {
  final double amount;
  final String mode;
  final DateTime createdAt;

  /// The bill it was collected with; null when paid from the Credit tab.
  final String? paidInBillNumber;

  const CreditPaymentEntry({
    required this.amount,
    required this.mode,
    required this.createdAt,
    this.paidInBillNumber,
  });
}

/// One Credit-tab payment that paid one or more credit bills — printed and
/// sent as a single Payment Receipt (backend migration 052).
class CreditSettlement {
  final String id;
  final String receiptToken;
  final DateTime createdAt;
  final String mode;
  final double total;
  final String? customerName;
  final String? customerPhone;
  final List<SettlementLine> lines;

  const CreditSettlement({
    required this.id,
    required this.receiptToken,
    required this.createdAt,
    required this.mode,
    required this.total,
    this.customerName,
    this.customerPhone,
    required this.lines,
  });

  factory CreditSettlement.fromJson(Map<String, dynamic> j) => CreditSettlement(
        id: j['id'] as String,
        receiptToken: (j['receipt_token'] ?? '') as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        mode: (j['mode'] ?? 'cash') as String,
        total: _money(j['total']),
        customerName: j['customer_name'] as String?,
        customerPhone: j['customer_phone'] as String?,
        lines: [
          for (final l in (j['lines'] as List? ?? const []))
            SettlementLine.fromJson(l as Map<String, dynamic>),
        ],
      );
}

/// One bill on a Payment Receipt: what it came to, what was paid on it in
/// this payment, and what it still owes after.
class SettlementLine {
  final String billNumber;
  final DateTime billDate;
  final double billTotal;
  final double paid;
  final double due;

  const SettlementLine({
    required this.billNumber,
    required this.billDate,
    required this.billTotal,
    required this.paid,
    required this.due,
  });

  String get displayNumber => stripBillPrefix(billNumber);

  factory SettlementLine.fromJson(Map<String, dynamic> j) => SettlementLine(
        billNumber: (j['bill_number'] ?? '') as String,
        billDate: DateTime.parse(j['bill_date'] as String),
        billTotal: _money(j['bill_total']),
        paid: _money(j['paid']),
        due: _money(j['due']),
      );
}

/// A money field that may arrive as a number or a numeric string.
double _money(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// One part of a split bill: [mode] is cash / upi / card / other / credit.
class BillPayment {
  final String mode;
  final double amount;

  const BillPayment(this.mode, this.amount);

  Map<String, dynamic> toJson() => {'mode': mode, 'amount': amount};

  /// Accepts the API's list or the JSON string the offline queue stores.
  static List<BillPayment> listFrom(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (raw is! List) return const [];
    return [
      for (final p in raw.whereType<Map>())
        BillPayment(p['mode'].toString(),
            double.tryParse('${p['amount']}') ?? 0.0),
    ];
  }
}

/// A debtor row for the Credit tab: one customer (grouped by phone) with their
/// total outstanding and how many unpaid bills make it up.
class CreditCustomer {
  final String? customerName;
  final String customerPhone;
  final int unpaidCount;
  final double outstanding;
  final DateTime? lastBillAt;

  CreditCustomer({
    required this.customerName,
    required this.customerPhone,
    required this.unpaidCount,
    required this.outstanding,
    this.lastBillAt,
  });

  factory CreditCustomer.fromJson(Map<String, dynamic> j) => CreditCustomer(
        customerName: j['customer_name'],
        customerPhone: j['customer_phone'] ?? '',
        unpaidCount: (j['unpaid_count'] as num?)?.toInt() ?? 0,
        outstanding: double.parse((j['outstanding'] ?? 0).toString()),
        lastBillAt: j['last_bill_at'] != null
            ? DateTime.tryParse(j['last_bill_at'].toString())
            : null,
      );
}

/// A row of the owner's Customers screen. Counts/spend are computed by the
/// server from finalized bills.
class Customer {
  final String id;
  final String? name;
  final String phone;
  final bool optedOut;
  final int billCount;
  final double totalSpend;
  final DateTime? lastVisit;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.optedOut,
    required this.billCount,
    required this.totalSpend,
    this.lastVisit,
  });

  /// Name, or the phone when no name was ever recorded.
  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : phone;

  Customer copyWith({bool? optedOut}) => Customer(
        id: id,
        name: name,
        phone: phone,
        optedOut: optedOut ?? this.optedOut,
        billCount: billCount,
        totalSpend: totalSpend,
        lastVisit: lastVisit,
      );

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String?,
        phone: j['phone'] as String? ?? '',
        optedOut: j['opted_out'] == true,
        billCount: (j['bill_count'] as num?)?.toInt() ?? 0,
        totalSpend: double.parse((j['total_spend'] ?? 0).toString()),
        lastVisit: j['last_visit'] != null
            ? DateTime.tryParse(j['last_visit'].toString())
            : null,
      );
}

/// One labeled value on a [Warranty] record — either filled from a
/// [WarrantyFieldTemplate] field or typed ad-hoc by staff. The backend stores
/// both the same way (routes/warranties.js), so the app never needs to tell
/// them apart.
class WarrantyExtraField {
  final String label;
  final String value;

  WarrantyExtraField({required this.label, required this.value});

  factory WarrantyExtraField.fromJson(Map<String, dynamic> j) =>
      WarrantyExtraField(
        label: (j['label'] as String?) ?? '',
        value: (j['value'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

/// A warranty record for a "Retail & Warranty" shop (tyre/battery/electronics
/// retailers): who bought what, when, for how long, and anything extra the
/// shop's category template or staff chose to capture (km reading, serial
/// number, ...). See migration 064 / routes/warranties.js.
class Warranty {
  final String id;
  final String? customerName;
  final String customerPhone;
  final String? itemId;
  final String itemName;
  final String? category;
  final String? billId;
  final String? serialNumber;
  final DateTime purchaseDate;
  final int warrantyMonths;
  final DateTime expiryDate;
  final List<WarrantyExtraField> extraData;
  final String? notes;

  Warranty({
    required this.id,
    this.customerName,
    required this.customerPhone,
    this.itemId,
    required this.itemName,
    this.category,
    this.billId,
    this.serialNumber,
    required this.purchaseDate,
    required this.warrantyMonths,
    required this.expiryDate,
    this.extraData = const [],
    this.notes,
  });

  /// Name, or the phone when no name was recorded — same fallback as
  /// [Customer.displayName].
  String get displayName =>
      (customerName != null && customerName!.trim().isNotEmpty)
          ? customerName!.trim()
          : customerPhone;

  bool get isExpired => expiryDate.isBefore(DateTime.now());

  /// Expires within 30 days — the same "expiring soon" horizon the backend
  /// list filter uses (routes/warranties.js STATUS_FILTER).
  bool get isExpiringSoon =>
      !isExpired && expiryDate.isBefore(DateTime.now().add(const Duration(days: 30)));

  factory Warranty.fromJson(Map<String, dynamic> j) => Warranty(
        id: j['id'] as String,
        customerName: j['customer_name'] as String?,
        customerPhone: j['customer_phone'] as String? ?? '',
        itemId: j['item_id'] as String?,
        itemName: (j['item_name'] as String?) ?? '',
        category: j['category'] as String?,
        billId: j['bill_id'] as String?,
        serialNumber: j['serial_number'] as String?,
        purchaseDate: DateTime.parse(j['purchase_date'].toString()),
        warrantyMonths: (j['warranty_months'] as num?)?.toInt() ?? 0,
        expiryDate: DateTime.parse(j['expiry_date'].toString()),
        extraData: (j['extra_data'] as List? ?? [])
            .map((e) => WarrantyExtraField.fromJson(e))
            .toList(),
        notes: j['notes'] as String?,
      );
}

/// The extra fields a business wants to ask for on every warranty record in
/// one item category (migration 063) — e.g. "KM Reading"/"Vehicle Number" for
/// Tyres, "Serial Number"/"IMEI" for Electronics.
class WarrantyFieldTemplate {
  final String category;
  final List<WarrantyTemplateField> fields;

  WarrantyFieldTemplate({required this.category, required this.fields});

  factory WarrantyFieldTemplate.fromJson(Map<String, dynamic> j) =>
      WarrantyFieldTemplate(
        category: j['category'] as String,
        fields: (j['fields'] as List? ?? [])
            .map((f) => WarrantyTemplateField.fromJson(f))
            .toList(),
      );
}

/// One field definition within a [WarrantyFieldTemplate]. [type] is a UI
/// rendering hint only (text/number/date) — the value is always stored as a
/// string on the record itself.
class WarrantyTemplateField {
  final String key;
  final String label;
  final String type;

  WarrantyTemplateField({
    required this.key,
    required this.label,
    required this.type,
  });

  factory WarrantyTemplateField.fromJson(Map<String, dynamic> j) =>
      WarrantyTemplateField(
        key: j['key'] as String,
        label: j['label'] as String,
        type: (j['type'] as String?) ?? 'text',
      );

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'type': type};
}

class Expense {
  final String id;
  final String category;
  final String? description;
  final double amount;
  final String paymentMode;
  final DateTime expenseDate;
  final DateTime createdAt;
  final String? createdByName;

  Expense({
    required this.id,
    required this.category,
    this.description,
    required this.amount,
    required this.paymentMode,
    required this.expenseDate,
    required this.createdAt,
    this.createdByName,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'],
        category: j['category'],
        description: j['description'],
        amount: double.parse(j['amount'].toString()),
        paymentMode: j['payment_mode'],
        expenseDate: DateTime.parse(j['expense_date']),
        createdAt: DateTime.parse(j['created_at']),
        createdByName: j['created_by_name'],
      );
}

class RecurringExpense {
  final String id;
  final String category;
  final String? description;
  final double amount;
  final String paymentMode;

  RecurringExpense({
    required this.id,
    required this.category,
    this.description,
    required this.amount,
    required this.paymentMode,
  });

  factory RecurringExpense.fromJson(Map<String, dynamic> j) => RecurringExpense(
        id: j['id'],
        category: j['category'],
        description: j['description'],
        amount: double.parse(j['amount'].toString()),
        paymentMode: j['payment_mode'],
      );
}

class DailyReport {
  final String day;
  final double revenue;
  final double expenses;
  final double profit;

  DailyReport({
    required this.day,
    required this.revenue,
    required this.expenses,
    required this.profit,
  });

  factory DailyReport.fromJson(Map<String, dynamic> j) => DailyReport(
        day: j['day'],
        revenue: double.parse(j['revenue'].toString()),
        // expenses/profit are absent from the weekly-sales (sales-only) shape.
        expenses: j['expenses'] != null
            ? double.parse(j['expenses'].toString())
            : 0.0,
        profit: j['profit'] != null
            ? double.parse(j['profit'].toString())
            : 0.0,
      );
}

class ReportSummary {
  final String from;
  final String to;
  final int billCount;
  final double totalRevenue;
  final double totalDiscount;
  final double totalTax;
  final double totalExpenses;
  final double netProfit;
  final Map<String, double> byPaymentMode;
  final List<DailyReport> daily;
  final List<MapEntry<String, double>> expensesByCategory;
  final List<MapEntry<String, double>> revenueByPaymentMode;
  final List<TopItem> topItems;
  final List<RecentBill> recentBills;

  /// Old credit paid off in the period, per mode, plus 'total' — counted on
  /// the day the money came in, separate from the period's sales.
  final Map<String, double> creditCollected;

  ReportSummary({
    required this.from,
    required this.to,
    required this.billCount,
    required this.totalRevenue,
    this.totalDiscount = 0.0,
    required this.totalTax,
    required this.totalExpenses,
    required this.netProfit,
    required this.byPaymentMode,
    required this.daily,
    required this.expensesByCategory,
    required this.revenueByPaymentMode,
    this.topItems = const [],
    this.recentBills = const [],
    this.creditCollected = const {},
  });

  /// Net sales for the period. total_revenue is already net of discount from
  /// the summary endpoint (SUM(total - discount)), so no further subtraction.
  double get netSales => totalRevenue;

  /// Average bill value over the period (0 when no bills).
  double get avgBill => billCount > 0 ? netSales / billCount : 0.0;

  factory ReportSummary.fromJson(Map<String, dynamic> j) {
    final bpm = (j['by_payment_mode'] as Map<String, dynamic>? ?? {});
    final expCat = (j['expenses_by_category'] as List? ?? [])
        .map((e) => MapEntry<String, double>(e['category'], double.parse(e['total'].toString())))
        .toList();
    final revMode = (j['revenue_by_payment_mode'] as List? ?? [])
        .map((e) => MapEntry<String, double>(e['mode'], double.parse(e['total'].toString())))
        .toList();
    return ReportSummary(
      from: j['from'],
      to: j['to'],
      billCount: j['bill_count'],
      totalRevenue: double.parse(j['total_revenue'].toString()),
      totalDiscount: j['total_discount'] != null
          ? double.parse(j['total_discount'].toString())
          : 0.0,
      totalTax: double.parse(j['total_tax'].toString()),
      totalExpenses: double.parse(j['total_expenses'].toString()),
      netProfit: double.parse(j['net_profit'].toString()),
      byPaymentMode: bpm.map((k, v) => MapEntry(k, double.parse(v.toString()))),
      daily: (j['daily'] as List? ?? []).map((d) => DailyReport.fromJson(d)).toList(),
      expensesByCategory: expCat,
      revenueByPaymentMode: revMode,
      topItems: (j['top_items'] as List? ?? [])
          .map((e) => TopItem.fromJson(e))
          .toList(),
      recentBills: (j['recent_bills'] as List? ?? [])
          .map((e) => RecentBill.fromJson(e))
          .toList(),
      creditCollected: (j['credit_collected'] as Map? ?? const {}).map(
          (k, v) => MapEntry('$k', double.tryParse('$v') ?? 0.0)),
    );
  }
}

/// A top-selling item over a report period.
class TopItem {
  final String itemName;
  final double qtySold;
  final double revenue;

  TopItem({required this.itemName, required this.qtySold, required this.revenue});

  factory TopItem.fromJson(Map<String, dynamic> j) => TopItem(
        itemName: j['item_name'] ?? '',
        qtySold: double.parse((j['qty_sold'] ?? 0).toString()),
        revenue: double.parse((j['revenue'] ?? 0).toString()),
      );
}

/// A recent bill row for the report list.
class RecentBill {
  final String billNumber;
  final double total;
  final double discountAmount;
  /// When the sale was finalized — what the report files it under.
  final DateTime billDate;
  final String? customerName;
  final String? tableNumber;

  RecentBill({
    required this.billNumber,
    required this.total,
    required this.discountAmount,
    required this.billDate,
    this.customerName,
    this.tableNumber,
  });

  double get net => total - discountAmount;

  factory RecentBill.fromJson(Map<String, dynamic> j) => RecentBill(
        billNumber: j['bill_number'] ?? '',
        total: double.parse((j['total'] ?? 0).toString()),
        discountAmount: double.parse((j['discount_amount'] ?? 0).toString()),
        billDate: DateTime.parse(j['bill_date']),
        customerName: j['customer_name'],
        tableNumber: j['table_number']?.toString(),
      );
}

class TableModel {
  final String id;
  final String businessId;
  final String tableNumber;
  final double floorX;
  final double floorY;
  final String status;
  final String? activeBillId;
  final String? qrToken;

  TableModel({
    required this.id,
    required this.businessId,
    required this.tableNumber,
    required this.floorX,
    required this.floorY,
    required this.status,
    this.activeBillId,
    this.qrToken,
  });

  factory TableModel.fromJson(Map<String, dynamic> j) => TableModel(
        id: j['id'],
        businessId: j['business_id'],
        tableNumber: j['table_number'],
        floorX: double.parse(j['floor_x'].toString()),
        floorY: double.parse(j['floor_y'].toString()),
        status: j['status'],
        activeBillId: j['active_bill_id'],
        qrToken: j['qr_token'] as String?,
      );
}

/// One line of an [OnlineOrder]. Mirrors a `bill_items` row: [unitPrice] is
/// already the NET rate, so accepting the order copies it across untouched.
class OnlineOrderItem {
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  OnlineOrderItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory OnlineOrderItem.fromJson(Map<String, dynamic> j) => OnlineOrderItem(
        itemName: j['item_name'] ?? '',
        quantity: double.parse((j['quantity'] ?? 0).toString()),
        unitPrice: double.parse((j['unit_price'] ?? 0).toString()),
        lineTotal: double.parse((j['line_total'] ?? 0).toString()),
      );
}

/// An order placed from the public online store, waiting on (or already given)
/// a decision. It is NOT a bill — accepting one is what creates the draft bill,
/// and [billNumber] is only set from that point on.
class OnlineOrder {
  final String id;
  final String orderNumber;
  final String? customerName;
  final String customerPhone;

  /// 'pickup' | 'delivery'. [address] is only ever set for delivery.
  final String fulfilment;
  final String? address;
  final String? note;

  final double subtotal;
  final double deliveryCharge;
  final double total;

  /// What the shop asked for up front (its advance % of [total]).
  final double amountDue;

  /// What the customer says they paid, with the UPI reference they typed.
  /// Unverifiable server-side — see [paymentStatus].
  final double paidAmount;
  final String? paymentTxnId;

  /// 'unpaid' | 'claimed' | 'verified'. 'claimed' means the customer entered a
  /// transaction id; only a human confirming it in their UPI app makes it
  /// 'verified'.
  final String paymentStatus;

  /// 'pending' | 'accepted' | 'rejected'.
  final String status;
  final String? rejectReason;

  /// The draft bill this order became, once accepted. Needed to open it in the
  /// billing screen straight from the order card.
  final String? billId;
  final String? billNumber;

  /// Status of the draft bill this order became — 'draft' until staff settle it,
  /// then 'finalized'/'voided'. Null while the order is still pending or was
  /// rejected. This, not [status], is what says whether the shop is done.
  final String? billStatus;

  final DateTime createdAt;

  final List<OnlineOrderItem> items;

  OnlineOrder({
    required this.id,
    required this.orderNumber,
    this.customerName,
    required this.customerPhone,
    required this.fulfilment,
    this.address,
    this.note,
    required this.subtotal,
    required this.deliveryCharge,
    required this.total,
    required this.amountDue,
    required this.paidAmount,
    this.paymentTxnId,
    required this.paymentStatus,
    required this.status,
    this.rejectReason,
    this.billId,
    this.billNumber,
    this.billStatus,
    required this.createdAt,
    required this.items,
  });

  bool get isPending => status == 'pending';
  bool get isDelivery => fulfilment == 'delivery';

  /// Whether the shop still has something to do with this order.
  ///
  /// Accepting is NOT finishing: it creates a draft bill that still has to be
  /// settled at the counter. So an accepted order stays "open" until its bill
  /// leaves draft. Rejected orders are done the moment they are rejected.
  ///
  /// Drives whether the Online sub-tab appears in Orders — hiding it the second
  /// the last order was accepted would take the accepted order off screen while
  /// the customer is still waiting for it.
  bool get isOpen =>
      isPending || (status == 'accepted' && billStatus == 'draft');

  /// Accepted, and its bill is still an unsettled draft — so there is something
  /// to bill. Once the bill is finalized there is nothing left to do from here.
  bool get canBill =>
      status == 'accepted' && billStatus == 'draft' && (billId?.isNotEmpty ?? false);

  /// True when the customer submitted a payment reference nobody has confirmed
  /// yet — the one thing the accept sheet must put in front of the owner.
  bool get needsPaymentCheck =>
      paymentStatus == 'claimed' && (paymentTxnId?.isNotEmpty ?? false);

  factory OnlineOrder.fromJson(Map<String, dynamic> j) => OnlineOrder(
        id: j['id'],
        orderNumber: j['order_number'] ?? '',
        customerName: j['customer_name'] as String?,
        customerPhone: j['customer_phone'] ?? '',
        fulfilment: j['fulfilment'] ?? 'pickup',
        address: j['address'] as String?,
        note: j['note'] as String?,
        subtotal: double.parse((j['subtotal'] ?? 0).toString()),
        deliveryCharge: double.parse((j['delivery_charge'] ?? 0).toString()),
        total: double.parse((j['total'] ?? 0).toString()),
        amountDue: double.parse((j['amount_due'] ?? 0).toString()),
        paidAmount: double.parse((j['paid_amount'] ?? 0).toString()),
        paymentTxnId: j['payment_txn_id'] as String?,
        paymentStatus: j['payment_status'] ?? 'unpaid',
        status: j['status'] ?? 'pending',
        rejectReason: j['reject_reason'] as String?,
        billId: j['bill_id'] as String?,
        billNumber: j['bill_number'] as String?,
        billStatus: j['bill_status'] as String?,
        createdAt: DateTime.parse(j['created_at']),
        items: ((j['items'] as List?) ?? const [])
            .map((i) => OnlineOrderItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}
