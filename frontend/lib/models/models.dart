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
  final List<ItemVariant> variants;
  final bool isActive;

  /// Customer-facing dish photo URL. Only populated by the owner-only Menu
  /// Photos endpoints; the billing/items list leaves this null so photos never
  /// load during billing.
  final String? imageUrl;

  Item({
    required this.id,
    required this.businessId,
    required this.name,
    this.barcode,
    this.category,
    this.price,
    this.taxRate,
    this.priceInclusiveTax = false,
    this.hsnCode,
    this.stockQuantity,
    this.lowStockThreshold,
    this.unit = 'piece',
    this.variants = const [],
    required this.isActive,
    this.imageUrl,
  });

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'],
        businessId: j['business_id'],
        name: j['name'],
        barcode: j['barcode'],
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
        variants: (j['variants'] as List? ?? [])
            .map((v) => ItemVariant.fromJson(v))
            .toList(),
        isActive: j['is_active'] == true || j['is_active'] == 1,
        imageUrl: j['image_url'] as String?,
      );

  /// Whether this item is sold by a divisible measure (kg, g, litre, ...)
  /// rather than as whole pieces. Drives decimal-quantity entry in the cart.
  bool get isMeasured => unit != 'piece';

  /// Whether the cashier must pick a size before this item can be added.
  bool get hasVariants => variants.isNotEmpty;

  /// Same item with a different set of sizes. Used to re-attach variants when a
  /// partial API response omits them, so a sized item never degrades into a
  /// plain one (which would bill at the base price).
  Item copyWithVariants(List<ItemVariant> newVariants) => Item(
        id: id,
        businessId: businessId,
        name: name,
        barcode: barcode,
        category: category,
        price: price,
        taxRate: taxRate,
        priceInclusiveTax: priceInclusiveTax,
        hsnCode: hsnCode,
        stockQuantity: stockQuantity,
        lowStockThreshold: lowStockThreshold,
        unit: unit,
        variants: newVariants,
        isActive: isActive,
        imageUrl: imageUrl,
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
  });

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
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  final double total;
  /// Signed invoice-level round-off adjustment (e.g. -0.22, +0.40). 0 when the
  /// business has rounding disabled. NEVER folded into subtotal/tax/total — the
  /// final payable is [grandTotal] = total - discount + roundOff.
  final double roundOff;
  final String paymentMode;
  final String status;
  /// 'paid' | 'unpaid'. Unpaid means a credit (udhaari) bill awaiting
  /// settlement. Defaults to 'paid' for older bills / partial responses.
  final String paymentStatus;
  final String createdByUserId;
  final DateTime createdAt;
  final List<BillItem> items;

  /// True when this is a credit bill that hasn't been settled yet.
  bool get isUnpaidCredit => paymentStatus == 'unpaid';

  /// The final amount the customer pays: total, less discount, plus round-off.
  double get grandTotal => total - discountAmount + roundOff;

  Bill({
    required this.id,
    required this.businessId,
    required this.billNumber,
    this.tableId,
    this.tableNumber,
    this.customerName,
    this.customerPhone,
    required this.subtotal,
    required this.taxAmount,
    this.discountAmount = 0.0,
    required this.total,
    this.roundOff = 0.0,
    required this.paymentMode,
    required this.status,
    this.paymentStatus = 'paid',
    required this.createdByUserId,
    required this.createdAt,
    required this.items,
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
        subtotal: double.parse(j['subtotal'].toString()),
        taxAmount: double.parse(j['tax_amount'].toString()),
        discountAmount: j['discount_amount'] != null
            ? double.parse(j['discount_amount'].toString())
            : 0.0,
        total: double.parse(j['total'].toString()),
        roundOff: j['round_off'] != null
            ? double.parse(j['round_off'].toString())
            : 0.0,
        paymentMode: j['payment_mode'],
        status: j['status'] ?? 'finalized',
        paymentStatus: j['payment_status'] ?? 'paid',
        createdByUserId: j['created_by_user_id'] ?? '',
        createdAt: DateTime.parse(j['created_at']),
        items: (j['items'] as List? ?? []).map((i) => BillItem.fromJson(i)).toList(),
      );
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
  final DateTime createdAt;
  final String? customerName;
  final String? tableNumber;

  RecentBill({
    required this.billNumber,
    required this.total,
    required this.discountAmount,
    required this.createdAt,
    this.customerName,
    this.tableNumber,
  });

  double get net => total - discountAmount;

  factory RecentBill.fromJson(Map<String, dynamic> j) => RecentBill(
        billNumber: j['bill_number'] ?? '',
        total: double.parse((j['total'] ?? 0).toString()),
        discountAmount: double.parse((j['discount_amount'] ?? 0).toString()),
        createdAt: DateTime.parse(j['created_at']),
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
