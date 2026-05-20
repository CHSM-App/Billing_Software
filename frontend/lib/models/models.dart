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
