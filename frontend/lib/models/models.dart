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

class Item {
  final String id;
  final String businessId;
  final String name;
  final String? barcode;
  final String? category;
  final double price;
  final double? taxRate;
  final double? stockQuantity;
  final bool isActive;

  Item({
    required this.id,
    required this.businessId,
    required this.name,
    this.barcode,
    this.category,
    required this.price,
    this.taxRate,
    this.stockQuantity,
    required this.isActive,
  });

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'],
        businessId: j['business_id'],
        name: j['name'],
        barcode: j['barcode'],
        category: j['category'],
        price: double.parse(j['price'].toString()),
        taxRate: j['tax_rate'] != null ? double.parse(j['tax_rate'].toString()) : null,
        stockQuantity: j['stock_quantity'] != null ? double.parse(j['stock_quantity'].toString()) : null,
        isActive: j['is_active'] == true || j['is_active'] == 1,
      );
}

class BillItem {
  final String id;
  final String billId;
  final String? itemId;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double? taxRate;
  final double lineTotal;

  BillItem({
    required this.id,
    required this.billId,
    this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.taxRate,
    required this.lineTotal,
  });

  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
        id: j['id'],
        billId: j['bill_id'],
        itemId: j['item_id'],
        itemName: j['item_name'],
        quantity: double.parse(j['quantity'].toString()),
        unitPrice: double.parse(j['unit_price'].toString()),
        taxRate: j['tax_rate'] != null ? double.parse(j['tax_rate'].toString()) : null,
        lineTotal: double.parse(j['line_total'].toString()),
      );
}

class Bill {
  final String id;
  final String businessId;
  final String billNumber;
  final String? tableId;
  final String? customerName;
  final String? customerPhone;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String paymentMode;
  final String status;
  final String createdByUserId;
  final DateTime createdAt;
  final List<BillItem> items;

  Bill({
    required this.id,
    required this.businessId,
    required this.billNumber,
    this.tableId,
    this.customerName,
    this.customerPhone,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.paymentMode,
    required this.status,
    required this.createdByUserId,
    required this.createdAt,
    required this.items,
  });

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: j['id'],
        businessId: j['business_id'],
        billNumber: j['bill_number'],
        tableId: j['table_id'],
        customerName: j['customer_name'],
        customerPhone: j['customer_phone'],
        subtotal: double.parse(j['subtotal'].toString()),
        taxAmount: double.parse(j['tax_amount'].toString()),
        total: double.parse(j['total'].toString()),
        paymentMode: j['payment_mode'],
        status: j['status'],
        createdByUserId: j['created_by_user_id'],
        createdAt: DateTime.parse(j['created_at']),
        items: (j['items'] as List? ?? []).map((i) => BillItem.fromJson(i)).toList(),
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
        expenses: double.parse(j['expenses'].toString()),
        profit: double.parse(j['profit'].toString()),
      );
}

class ReportSummary {
  final String from;
  final String to;
  final int billCount;
  final double totalRevenue;
  final double totalTax;
  final double totalExpenses;
  final double netProfit;
  final Map<String, double> byPaymentMode;
  final List<DailyReport> daily;
  final List<MapEntry<String, double>> expensesByCategory;
  final List<MapEntry<String, double>> revenueByPaymentMode;

  ReportSummary({
    required this.from,
    required this.to,
    required this.billCount,
    required this.totalRevenue,
    required this.totalTax,
    required this.totalExpenses,
    required this.netProfit,
    required this.byPaymentMode,
    required this.daily,
    required this.expensesByCategory,
    required this.revenueByPaymentMode,
  });

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
      totalTax: double.parse(j['total_tax'].toString()),
      totalExpenses: double.parse(j['total_expenses'].toString()),
      netProfit: double.parse(j['net_profit'].toString()),
      byPaymentMode: bpm.map((k, v) => MapEntry(k, double.parse(v.toString()))),
      daily: (j['daily'] as List? ?? []).map((d) => DailyReport.fromJson(d)).toList(),
      expensesByCategory: expCat,
      revenueByPaymentMode: revMode,
    );
  }
}

class TableModel {
  final String id;
  final String businessId;
  final String tableNumber;
  final double floorX;
  final double floorY;
  final String status;
  final String? activeBillId;

  TableModel({
    required this.id,
    required this.businessId,
    required this.tableNumber,
    required this.floorX,
    required this.floorY,
    required this.status,
    this.activeBillId,
  });

  factory TableModel.fromJson(Map<String, dynamic> j) => TableModel(
        id: j['id'],
        businessId: j['business_id'],
        tableNumber: j['table_number'],
        floorX: double.parse(j['floor_x'].toString()),
        floorY: double.parse(j['floor_y'].toString()),
        status: j['status'],
        activeBillId: j['active_bill_id'],
      );
}
