import 'package:Vittam/models/cart_entry.dart';
import 'package:Vittam/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
// import 'package:Vittam/models/models.dart';
// import 'package:/models/cart_entry.dart';

void main() {
  // ─────────────────────────────────────────────────────────────
  // User
  // ─────────────────────────────────────────────────────────────
  group('User.fromJson', () {
    test('parses all fields', () {
      final user = User.fromJson({
        'id': 'user-1',
        'name': 'Alice',
        'phone': '9876543210',
        'role': 'owner',
      });
      expect(user.id, 'user-1');
      expect(user.name, 'Alice');
      expect(user.phone, '9876543210');
      expect(user.role, 'owner');
    });

    test('parses cashier role', () {
      final user = User.fromJson({
        'id': 'user-2',
        'name': 'Bob',
        'phone': '9876543211',
        'role': 'cashier',
      });
      expect(user.role, 'cashier');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Business
  // ─────────────────────────────────────────────────────────────
  group('Business.fromJson', () {
    test('parses all fields', () {
      final biz = Business.fromJson({
        'id': 'biz-1',
        'name': 'My Shop',
        'business_type': 'retail',
        'address': '123 Main St',
        'inventory_enabled': true,
        'has_barcode_scanner': false,
      });
      expect(biz.id, 'biz-1');
      expect(biz.name, 'My Shop');
      expect(biz.businessType, 'retail');
      expect(biz.address, '123 Main St');
      expect(biz.inventoryEnabled, isTrue);
      expect(biz.hasBarcodeScanner, isFalse);
    });

    test('address can be null', () {
      final biz = Business.fromJson({
        'id': 'biz-2',
        'name': 'Shop',
        'business_type': 'restaurant',
        'address': null,
        'inventory_enabled': false,
        'has_barcode_scanner': false,
      });
      expect(biz.address, isNull);
    });

    test('inventory_enabled defaults false for non-true values', () {
      final biz = Business.fromJson({
        'id': 'biz-3',
        'name': 'Shop',
        'business_type': 'retail',
        'address': null,
        'inventory_enabled': null,
        'has_barcode_scanner': null,
      });
      expect(biz.inventoryEnabled, isFalse);
      expect(biz.hasBarcodeScanner, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Item
  // ─────────────────────────────────────────────────────────────
  group('Item.fromJson', () {
    test('parses all fields', () {
      final item = Item.fromJson({
        'id': 'item-1',
        'business_id': 'biz-1',
        'name': 'Rice',
        'barcode': '12345',
        'category': 'Grains',
        'price': 50.0,
        'tax_rate': 5.0,
        'stock_quantity': 100,
        'is_active': true,
      });
      expect(item.id, 'item-1');
      expect(item.name, 'Rice');
      expect(item.price, 50.0);
      expect(item.taxRate, 5.0);
      expect(item.stockQuantity, 100.0);
      expect(item.isActive, isTrue);
    });

    test('parses is_active = 1 as true', () {
      final item = Item.fromJson({
        'id': 'item-2',
        'business_id': 'biz-1',
        'name': 'Dal',
        'barcode': null,
        'category': null,
        'price': '30',
        'tax_rate': null,
        'stock_quantity': null,
        'is_active': 1,
      });
      expect(item.isActive, isTrue);
    });

    test('parses price as string', () {
      final item = Item.fromJson({
        'id': 'item-3',
        'business_id': 'biz-1',
        'name': 'Oil',
        'barcode': null,
        'category': null,
        'price': '120.50',
        'tax_rate': null,
        'stock_quantity': null,
        'is_active': true,
      });
      expect(item.price, 120.50);
    });

    test('optional fields can be null', () {
      final item = Item.fromJson({
        'id': 'item-4',
        'business_id': 'biz-1',
        'name': 'Sugar',
        'barcode': null,
        'category': null,
        'price': 40,
        'tax_rate': null,
        'stock_quantity': null,
        'is_active': false,
      });
      expect(item.barcode, isNull);
      expect(item.category, isNull);
      expect(item.taxRate, isNull);
      expect(item.stockQuantity, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // BillItem
  // ─────────────────────────────────────────────────────────────
  group('BillItem.fromJson', () {
    test('parses all fields', () {
      final bi = BillItem.fromJson({
        'id': 'bi-1',
        'bill_id': 'bill-1',
        'item_id': 'item-1',
        'item_name': 'Rice',
        'quantity': 2,
        'unit_price': 50.0,
        'tax_rate': null,
        'line_total': 100.0,
      });
      expect(bi.itemName, 'Rice');
      expect(bi.quantity, 2.0);
      expect(bi.unitPrice, 50.0);
      expect(bi.lineTotal, 100.0);
      expect(bi.taxRate, isNull);
    });

    test('parses numeric strings', () {
      final bi = BillItem.fromJson({
        'id': 'bi-2',
        'bill_id': 'bill-1',
        'item_id': null,
        'item_name': 'Custom',
        'quantity': '3',
        'unit_price': '25.50',
        'tax_rate': '5',
        'line_total': '80.33',
      });
      expect(bi.quantity, 3.0);
      expect(bi.unitPrice, 25.50);
      expect(bi.taxRate, 5.0);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Bill
  // ─────────────────────────────────────────────────────────────
  group('Bill.fromJson', () {
    final Map<String, dynamic> billJson = {
      'id': 'bill-1',
      'business_id': 'biz-1',
      'bill_number': 'INV-0001',
      'table_id': null,
      'customer_name': 'Alice',
      'customer_phone': '9876543210',
      'subtotal': 100.0,
      'tax_amount': 0.0,
      'total': 100.0,
      'payment_mode': 'cash',
      'status': 'finalized',
      'created_by_user_id': 'user-1',
      'created_at': '2024-01-15T10:00:00.000Z',
      'items': [],
    };

    test('displayNumber drops the bill prefix', () {
      expect(Bill.fromJson(billJson).displayNumber, '0001');
      expect(
        Bill.fromJson({...billJson, 'bill_number': 'INV-a7f4-0001'})
            .displayNumber,
        'a7f4-0001',
      );
      expect(Bill.fromJson({...billJson, 'bill_number': 'PREVIEW'})
          .displayNumber, 'PREVIEW');
    });

    test('parses all fields', () {
      final bill = Bill.fromJson(billJson);
      expect(bill.id, 'bill-1');
      expect(bill.billNumber, 'INV-0001');
      expect(bill.customerName, 'Alice');
      expect(bill.total, 100.0);
      expect(bill.paymentMode, 'cash');
      expect(bill.status, 'finalized');
      expect(bill.items, isEmpty);
    });

    test('parses createdAt as DateTime', () {
      final bill = Bill.fromJson(billJson);
      expect(bill.createdAt, isA<DateTime>());
      expect(bill.createdAt.year, 2024);
    });

    test('parses items list', () {
      final json = {
        ...billJson,
        'items': [
          {
            'id': 'bi-1',
            'bill_id': 'bill-1',
            'item_id': 'item-1',
            'item_name': 'Rice',
            'quantity': 2,
            'unit_price': 50,
            'tax_rate': null,
            'line_total': 100,
          }
        ],
      };
      final bill = Bill.fromJson(json);
      expect(bill.items.length, 1);
      expect(bill.items.first.itemName, 'Rice');
    });

    test('optional fields can be null', () {
      final json = {...billJson, 'customer_name': null, 'customer_phone': null, 'table_id': null};
      final bill = Bill.fromJson(json);
      expect(bill.customerName, isNull);
      expect(bill.customerPhone, isNull);
      expect(bill.tableId, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Expense
  // ─────────────────────────────────────────────────────────────
  group('Expense.fromJson', () {
    test('parses all fields', () {
      final e = Expense.fromJson({
        'id': 'exp-1',
        'category': 'Rent',
        'description': 'Monthly',
        'amount': 5000,
        'payment_mode': 'cash',
        'expense_date': '2024-01-15',
        'created_at': '2024-01-15T10:00:00.000Z',
        'created_by_name': 'Owner',
      });
      expect(e.category, 'Rent');
      expect(e.amount, 5000.0);
      expect(e.description, 'Monthly');
      expect(e.createdByName, 'Owner');
    });

    test('description and createdByName can be null', () {
      final e = Expense.fromJson({
        'id': 'exp-2',
        'category': 'Utilities',
        'description': null,
        'amount': '1200',
        'payment_mode': 'upi',
        'expense_date': '2024-01-20',
        'created_at': '2024-01-20T10:00:00.000Z',
        'created_by_name': null,
      });
      expect(e.description, isNull);
      expect(e.createdByName, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // TableModel
  // ─────────────────────────────────────────────────────────────
  group('TableModel.fromJson', () {
    test('parses all fields', () {
      final t = TableModel.fromJson({
        'id': 'table-1',
        'business_id': 'biz-1',
        'table_number': 'T1',
        'floor_x': 10.0,
        'floor_y': 20.0,
        'status': 'empty',
        'active_bill_id': null,
      });
      expect(t.tableNumber, 'T1');
      expect(t.floorX, 10.0);
      expect(t.floorY, 20.0);
      expect(t.status, 'empty');
      expect(t.activeBillId, isNull);
    });

    test('parses active_bill_id when present', () {
      final t = TableModel.fromJson({
        'id': 'table-2',
        'business_id': 'biz-1',
        'table_number': 'T2',
        'floor_x': 0,
        'floor_y': 0,
        'status': 'occupied',
        'active_bill_id': 'bill-99',
      });
      expect(t.activeBillId, 'bill-99');
      expect(t.status, 'occupied');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // DailyReport
  // ─────────────────────────────────────────────────────────────
  group('DailyReport.fromJson', () {
    test('parses all numeric fields', () {
      final r = DailyReport.fromJson({
        'day': '2024-01-15',
        'revenue': '1500.50',
        'expenses': '200',
        'profit': '1300.50',
      });
      expect(r.day, '2024-01-15');
      expect(r.revenue, 1500.50);
      expect(r.expenses, 200.0);
      expect(r.profit, 1300.50);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // CartEntry
  // ─────────────────────────────────────────────────────────────
  group('CartEntry', () {
    Item makeItem({double? taxRate, bool inclusive = false}) => Item(
          id: 'item-1',
          businessId: 'biz-1',
          name: 'Rice',
          price: 50.0,
          taxRate: taxRate,
          priceInclusiveTax: inclusive,
          isActive: true,
        );

    test('lineTotal without tax = price * quantity', () {
      final entry = CartEntry(item: makeItem(), quantity: 3);
      expect(entry.lineTotal(true), 150.0);
    });

    test('lineTotal with tax = price * quantity * (1 + tax/100)', () {
      final entry = CartEntry(item: makeItem(taxRate: 10.0), quantity: 2);
      // 50 * 2 * 1.10 = 110
      expect(entry.lineTotal(true), closeTo(110.0, 0.001));
    });

    test('lineTotal with 0 tax = price * quantity', () {
      final entry = CartEntry(item: makeItem(taxRate: 0.0), quantity: 4);
      expect(entry.lineTotal(true), 200.0);
    });

    // ── Tax-inclusive (MRP) pricing ────────────────────────────
    // An exclusive price is the net rate and tax goes on top; an inclusive
    // price is the gross the customer pays and the net is backed out of it.

    test('exclusive price: netPrice is the stored price, gross adds tax', () {
      final entry = CartEntry(item: makeItem(taxRate: 10.0), quantity: 1);
      expect(entry.netPrice(true), 50.0);
      expect(entry.grossPrice(true), closeTo(55.0, 0.001));
    });

    test('inclusive price: tax is stripped out to get the net rate', () {
      final entry = CartEntry(
          item: makeItem(taxRate: 10.0, inclusive: true), quantity: 1);
      // 50 inclusive of 10% is 45.4545… net + 4.5454… tax.
      expect(entry.netPrice(true), closeTo(45.4545, 0.001));
      expect(entry.lineTax(true), closeTo(4.5455, 0.001));
    });

    test('inclusive price: the customer still pays exactly the MRP', () {
      final entry = CartEntry(
          item: makeItem(taxRate: 10.0, inclusive: true), quantity: 3);
      // The whole point: 3 x 50 MRP rings up at 150, not 165.
      expect(entry.grossPrice(true), closeTo(50.0, 1e-9));
      expect(entry.lineTotal(true), closeTo(150.0, 1e-9));
      expect(entry.lineNet(true) + entry.lineTax(true), closeTo(150.0, 1e-9));
    });

    test('inclusive price bills lower than the same figure as exclusive', () {
      final incl = CartEntry(
          item: makeItem(taxRate: 18.0, inclusive: true), quantity: 1);
      final excl = CartEntry(item: makeItem(taxRate: 18.0), quantity: 1);
      expect(incl.lineTotal(true), lessThan(excl.lineTotal(true)));
    });

    test('GST off: an inclusive price is charged as-is, unsplit', () {
      final entry = CartEntry(
          item: makeItem(taxRate: 10.0, inclusive: true), quantity: 2);
      // No tax to extract, so the MRP is the whole amount and tax is 0.
      expect(entry.netPrice(false), 50.0);
      expect(entry.lineTax(false), 0.0);
      expect(entry.lineTotal(false), 100.0);
    });

    test('inclusive flag is inert when the item carries no tax rate', () {
      final entry =
          CartEntry(item: makeItem(inclusive: true), quantity: 2);
      expect(entry.netPrice(true), 50.0);
      expect(entry.lineTotal(true), 100.0);
    });

    test('copyWith changes quantity', () {
      final entry = CartEntry(item: makeItem(), quantity: 2);
      final updated = entry.copyWith(quantity: 5);
      expect(updated.quantity, 5);
      expect(updated.item.name, 'Rice');
    });

    test('copyWith without args returns same values', () {
      final item = makeItem();
      final entry = CartEntry(item: item, quantity: 3);
      final copy = entry.copyWith();
      expect(copy.quantity, 3);
      expect(copy.item.id, 'item-1');
    });
  });
}
