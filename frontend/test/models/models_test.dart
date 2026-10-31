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

    test('BillItem.receiptPrice shows the rate before the line discount', () {
      BillItem line(double unit, double disc) => BillItem.fromJson({
            'item_name': 'Chilli', 'quantity': 2, 'unit_price': unit,
            'line_total': unit * 2, 'discount_amount': disc,
          });
      // 2 × 180 less 50 is stored as 155/unit; the receipt still says 180.
      expect(line(155, 50).receiptPrice, 180);
      expect(line(155, 50).unitPrice * 2, 310);
      // No discount (or an edited price, already in unit_price): unchanged.
      expect(line(150, 0).receiptPrice, 150);
    });

    test('item_no shows on billingName only when the shop turns it on', () {
      Item make(String? no) => Item.fromJson({
            'id': 'i', 'business_id': 'b', 'name': 'Masala Dosa',
            'item_no': no, 'is_active': 1,
          });
      expect(make('101').billingName(true), '(101) Masala Dosa');
      expect(make('101').copyWithVariants(const []).billingName(true),
          '(101) Masala Dosa');
      expect(make('101').billingName(false), 'Masala Dosa');
      expect(make(null).billingName(true), 'Masala Dosa');
      expect(make('').billingName(true), 'Masala Dosa');
    });

    test('parses major_category and carries it through copyWithVariants', () {
      final item = Item.fromJson({
        'id': 'item-1a',
        'business_id': 'biz-1',
        'name': 'Chilli Paneer',
        'barcode': null,
        'major_category': 'Chinese',
        'category': 'Chinese Starters',
        'price': 180.0,
        'tax_rate': null,
        'stock_quantity': null,
        'is_active': true,
      });
      expect(item.majorCategory, 'Chinese');
      expect(item.category, 'Chinese Starters');
      // copyWithVariants re-attaches sizes after a partial API response; a field
      // it forgets is a field the billing list silently loses.
      final sized = item.copyWithVariants([
        ItemVariant(
          id: 'v1',
          itemId: 'item-1a',
          label: 'half',
          price: 120,
          sortOrder: 0,
          isActive: true,
        ),
      ]);
      expect(sized.majorCategory, 'Chinese');
      expect(sized.category, 'Chinese Starters');
    });

    test('major_category is null for an item saved before majors existed', () {
      // The whole feature is additive: an old payload has no such key at all.
      final item = Item.fromJson({
        'id': 'item-1b',
        'business_id': 'biz-1',
        'name': 'Rice',
        'barcode': null,
        'category': 'Grains',
        'price': 50.0,
        'tax_rate': null,
        'stock_quantity': null,
        'is_active': true,
      });
      expect(item.majorCategory, isNull);
      expect(item.category, 'Grains');
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

    test('billed_by: raw name kept, tidied full name for receipts', () {
      final b = Bill.fromJson({...billJson, 'billed_by': '  Ramesh  Patil '});
      expect(b.billedBy, '  Ramesh  Patil ');
      expect(b.billedByName, 'Ramesh Patil');
      // Unknown (offline / older shapes) or blank: nothing to print.
      expect(Bill.fromJson(billJson).billedByName, isNull);
      expect(Bill.fromJson({...billJson, 'billed_by': '  '}).billedByName,
          isNull);
    });

    test('billDate is the finalize time; a held bill keeps its order time', () {
      // Held on the 7th, settled on the 12th: dated the 12th.
      final held = Bill.fromJson({
        ...billJson,
        'created_at': '2026-10-07T14:15:00.000Z',
        'finalized_at': '2026-10-12T06:40:00.000Z',
      });
      expect(held.billDate, DateTime.utc(2026, 10, 12, 6, 40));
      expect(held.createdAt, DateTime.utc(2026, 10, 7, 14, 15));
      expect(held.wasHeld, isTrue);

      // Billed straight away: both stamps in the same instant.
      final direct = Bill.fromJson({
        ...billJson,
        'finalized_at': billJson['created_at'],
      });
      expect(direct.wasHeld, isFalse);

      // A draft (or an older payload) has only its order time.
      final draft = Bill.fromJson(billJson);
      expect(draft.finalizedAt, isNull);
      expect(draft.billDate, draft.createdAt);
      expect(draft.wasHeld, isFalse);
    });

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

    // Split payments: ₹100 paid 60 cash + 40 on credit.
    test('a split bill lists its parts and owes only its credit part', () {
      final bill = Bill.fromJson({
        ...billJson,
        'payment_mode': 'split',
        'payment_status': 'unpaid',
        'credit_amount': '40.00',
        'payments': [
          {'mode': 'cash', 'amount': 60},
          {'mode': 'credit', 'amount': '40.00'},
        ],
      });
      expect(bill.isSplit, isTrue);
      expect(bill.amountDue, 40.0);
      expect(bill.tenderLabel((m) => m.toUpperCase()),
          'CASH ₹60.00 + CREDIT ₹40.00');
    });

    test('a whole-bill credit owes its rounded payable', () {
      final bill = Bill.fromJson({
        ...billJson,
        'payment_mode': 'credit',
        'payment_status': 'unpaid',
        'total': 99.6,
        'round_off': 0.4,
      });
      expect(bill.isSplit, isFalse);
      expect(bill.amountDue, closeTo(100.0, 1e-9));
      expect(bill.tenderLabel((m) => m), 'credit');
    });

    // Paying credit off in parts (migration 051).
    test('a credit bill owes its credit part less what has been paid on it',
        () {
      final bill = Bill.fromJson({
        ...billJson,
        'payment_mode': 'credit',
        'payment_status': 'unpaid',
        'credit_payments': [
          {'amount': 30, 'mode': 'cash', 'created_at': '2024-01-16T10:00:00Z',
           'paid_in_bill_number': 'INV-0012'},
          {'amount': '20.00', 'mode': 'upi', 'created_at': '2024-01-17T10:00:00Z'},
        ],
      });
      expect(bill.creditPaid, 50.0);
      expect(bill.amountDue, 50.0);
      expect(bill.creditPayments.first.paidInBillNumber, 'INV-0012');
      expect(bill.creditPayments.last.paidInBillNumber, isNull);
    });

    test('a bill that collected old dues totals them on top of itself', () {
      final bill = Bill.fromJson({
        ...billJson,
        'collected': [
          {'bill_id': 'old-1', 'bill_number': 'INV-0007', 'amount': 300},
          {'bill_id': 'old-2', 'bill_number': 'INV-0009', 'amount': '50.50'},
        ],
      });
      expect(bill.collectedTotal, 350.5);
      expect(bill.totalPaid, 450.5);
      expect(bill.collected.first.displayNumber, '0007');
    });

    test('payments also parse from the JSON string the offline queue stores',
        () {
      expect(
        BillPayment.listFrom('[{"mode":"upi","amount":25.5}]')
            .map((p) => '${p.mode}:${p.amount}'),
        ['upi:25.5'],
      );
      expect(BillPayment.listFrom('not json'), isEmpty);
      expect(BillPayment.listFrom(null), isEmpty);
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

    // ── Order-card price edit + line discount ──────────────────
    // The discount comes off the NET line; tax is charged on what is left.
    // Wire form mirrors applyLineOverrides in backend/src/routes/bills.js.

    test('price override + % discount, exclusive item with GST', () {
      final entry = CartEntry(
          item: makeItem(taxRate: 10.0),
          quantity: 2,
          priceOverride: 40,
          discountPct: 10);
      expect(entry.lineDiscount(true), 8.0); // 10% of 80
      expect(entry.lineNet(true), 72.0);
      expect(entry.lineTax(true), closeTo(7.2, 1e-9));
      expect(entry.lineTotal(true), closeTo(79.2, 1e-9));
      expect(entry.discountedNetPrice(true), 36.0); // what the server stores
      expect(entry.overridePayload(true),
          {'price_override': 40.0, 'discount_amount': 8.0});
    });

    test('% discount scales with quantity, ₹ discount does not', () {
      final pct = CartEntry(item: makeItem(), quantity: 1, discountPct: 10);
      final amt = CartEntry(item: makeItem(), quantity: 1, discountAmt: 5);
      expect(pct.copyWith(quantity: 3).lineDiscount(true), 15.0);
      expect(amt.copyWith(quantity: 3).lineDiscount(true), 5.0);
    });

    test('₹ discount is clamped to the line when quantity drops', () {
      final entry = CartEntry(item: makeItem(), quantity: 1, discountAmt: 80);
      expect(entry.lineDiscount(true), 50.0);
      expect(entry.lineNet(true), 0.0);
    });

    test('MRP item: override is gross; discount comes off the net', () {
      final entry = CartEntry(
          item: makeItem(taxRate: 10.0, inclusive: true),
          quantity: 1,
          priceOverride: 110,
          discountAmt: 10);
      expect(entry.netPrice(true), closeTo(100.0, 1e-9));
      expect(entry.lineNet(true), closeTo(90.0, 1e-9));
      expect(entry.lineTotal(true), closeTo(99.0, 1e-9));
      expect(entry.overridePayload(true)['price_override'],
          closeTo(100.0, 1e-9)); // net goes on the wire
    });

    test('catalog line sends no override fields', () {
      expect(CartEntry(item: makeItem(), quantity: 2).overridePayload(true),
          isEmpty);
    });

    test('copyWith clearOverrides resets price and discount', () {
      final entry = CartEntry(
          item: makeItem(), quantity: 1, priceOverride: 30, discountPct: 5);
      final cleared = entry.copyWith(clearOverrides: true);
      expect(cleared.effectivePrice, 50.0);
      expect(cleared.lineDiscount(true), 0.0);
    });

    test('copyWith keeps overrides unless told otherwise', () {
      final entry = CartEntry(
          item: makeItem(), quantity: 1, priceOverride: 30, discountAmt: 4);
      final more = entry.copyWith(quantity: 2);
      expect(more.priceOverride, 30);
      expect(more.discountAmt, 4);
      expect(more.lineNet(true), 56.0);
    });

    test('catalogPrice ignores the override; effectivePrice uses it', () {
      final entry =
          CartEntry(item: makeItem(), quantity: 1, priceOverride: 30);
      expect(entry.catalogPrice, 50.0);
      expect(entry.effectivePrice, 30.0);
    });

    test('% discount on a taxed line: tax on what is left', () {
      final entry = CartEntry(
          item: makeItem(taxRate: 18.0), quantity: 4, discountPct: 25);
      expect(entry.lineDiscount(true), 50.0); // 25% of 200
      expect(entry.lineTax(true), closeTo(27.0, 1e-9)); // 18% of 150
      expect(entry.lineTotal(true), closeTo(177.0, 1e-9));
    });

    test('100% off is a free line, never negative', () {
      final entry = CartEntry(
          item: makeItem(taxRate: 10.0), quantity: 2, discountPct: 150);
      expect(entry.lineDiscount(true), 100.0);
      expect(entry.lineNet(true), 0.0);
      expect(entry.lineTotal(true), 0.0);
    });

    test('a negative ₹ discount is treated as none', () {
      final entry = CartEntry(item: makeItem(), quantity: 1, discountAmt: -5);
      expect(entry.lineDiscount(true), 0.0);
      expect(entry.overridePayload(true), isEmpty);
    });

    test('lineDiscount rounds to paise like the server', () {
      // 1/3 of ₹10 = 3.333… → 3.33
      final entry = CartEntry(
          item: makeItem(), quantity: 1, priceOverride: 10, discountPct: 100 / 3);
      expect(entry.lineDiscount(true), 3.33);
    });

    test('discountedNetPrice at qty 0 falls back to the net rate (no NaN)', () {
      final entry = CartEntry(item: makeItem(), quantity: 0, discountAmt: 5);
      expect(entry.discountedNetPrice(true), 50.0);
    });

    test('discount-only line sends only discount_amount', () {
      final entry = CartEntry(item: makeItem(), quantity: 2, discountAmt: 7);
      expect(entry.overridePayload(true), {'discount_amount': 7.0});
    });

    test('billingDisplayName adds (No) before the name, size after', () {
      final item = Item.fromJson({
        'id': 'i', 'business_id': 'b', 'name': 'Biryani',
        'item_no': '12', 'is_active': 1,
      });
      final v = ItemVariant(id: 'v', itemId: 'i', label: 'Half', price: 120);
      final sized = CartEntry(item: item, variant: v, quantity: 1);
      expect(sized.billingDisplayName(true), '(12) Biryani (Half)');
      expect(sized.billingDisplayName(false), 'Biryani (Half)');
      // The bill itself keeps the plain name.
      expect(sized.displayName, 'Biryani (Half)');
    });
  });

  group('BillItem — line discount', () {
    test('fromJson reads discount_amount as number, string or absent', () {
      BillItem parse(Object? d) => BillItem.fromJson({
            'item_name': 'Rice', 'quantity': 1, 'unit_price': 45,
            'line_total': 45, 'discount_amount': d,
          });
      expect(parse(5).discountAmount, 5.0);
      expect(parse('5.50').discountAmount, 5.5); // mssql DECIMAL as text
      expect(parse(null).discountAmount, 0.0);
      expect(parse('junk').discountAmount, 0.0);
    });

    test('receiptName notes the discount; plain otherwise', () {
      final d = BillItem(id: '1', billId: 'b', itemName: 'Egg Biryani',
          quantity: 1, unitPrice: 180, lineTotal: 180, discountAmount: 20);
      expect(d.receiptName, 'Egg Biryani (Disc ₹20.00)');
      final plain = BillItem(id: '2', billId: 'b', itemName: 'Egg Biryani',
          quantity: 1, unitPrice: 200, lineTotal: 200);
      expect(plain.receiptName, 'Egg Biryani');
    });

    test('receiptPrice at qty 0 is the stored unit price', () {
      final z = BillItem(id: '1', billId: 'b', itemName: 'X',
          quantity: 0, unitPrice: 50, lineTotal: 0, discountAmount: 5);
      expect(z.receiptPrice, 50);
    });

    test('kitchen_status is parsed when present', () {
      final j = {'item_name': 'Dal', 'quantity': 1, 'unit_price': 30,
          'line_total': 30};
      expect(BillItem.fromJson({...j, 'kitchen_status': 'ready'}).kitchenStatus,
          'ready');
      expect(BillItem.fromJson(j).kitchenStatus, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // OnlineOrder
  // ─────────────────────────────────────────────────────────────
  group('OnlineOrder.fromJson', () {
    Map<String, dynamic> json({Map<String, dynamic> over = const {}}) => {
          'id': 'order-1',
          'order_number': 'ORD-0001',
          'customer_name': 'Ramesh',
          'customer_phone': '9876543210',
          'fulfilment': 'delivery',
          'address': '12 Beach Road',
          'note': 'Ring the bell',
          // The API sends money as strings from mssql DECIMALs.
          'subtotal': '200.00',
          'delivery_charge': '30.00',
          'total': '230.00',
          'amount_due': '46.00',
          'paid_amount': '46.00',
          'payment_txn_id': 'UPI123',
          'payment_status': 'claimed',
          'status': 'pending',
          'created_at': '2026-09-02T10:00:00.000Z',
          'items': [
            {
              'item_name': 'Chai',
              'quantity': '2.00',
              'unit_price': '100.0000',
              'line_total': '200.00',
            }
          ],
          ...over,
        };

    test('parses a delivery order with its lines', () {
      final o = OnlineOrder.fromJson(json());
      expect(o.orderNumber, 'ORD-0001');
      expect(o.isDelivery, isTrue);
      expect(o.address, '12 Beach Road');
      expect(o.total, 230.0);
      expect(o.deliveryCharge, 30.0);
      expect(o.items, hasLength(1));
      expect(o.items.first.itemName, 'Chai');
      expect(o.items.first.unitPrice, 100.0);
    });

    test('a pending order is pending', () {
      expect(OnlineOrder.fromJson(json()).isPending, isTrue);
      expect(
        OnlineOrder.fromJson(json(over: {'status': 'accepted'})).isPending,
        isFalse,
      );
    });

    test('canBill only when accepted with an unsettled draft bill', () {
      // Drives the Bill button. It must never appear on an order with no bill
      // to open, and must disappear once that bill is actually settled.
      expect(OnlineOrder.fromJson(json()).canBill, isFalse); // pending
      expect(
        OnlineOrder.fromJson(json(over: {
          'status': 'accepted',
          'bill_status': 'draft',
          'bill_id': 'bill-1',
        })).canBill,
        isTrue,
      );
      expect(
        OnlineOrder.fromJson(json(over: {
          'status': 'accepted',
          'bill_status': 'finalized',
          'bill_id': 'bill-1',
        })).canBill,
        isFalse,
      );
      // Accepted but bill_id missing — nothing to navigate to.
      expect(
        OnlineOrder.fromJson(json(over: {
          'status': 'accepted',
          'bill_status': 'draft',
        })).canBill,
        isFalse,
      );
      expect(
        OnlineOrder.fromJson(json(over: {'status': 'rejected'})).canBill,
        isFalse,
      );
    });

    test('isOpen tracks the BILL, not the acceptance', () {
      // Accepting only creates a draft bill — the shop is not done until that
      // bill is settled, which is what keeps the Online tab on screen.
      expect(OnlineOrder.fromJson(json()).isOpen, isTrue); // pending
      expect(
        OnlineOrder.fromJson(
                json(over: {'status': 'accepted', 'bill_status': 'draft'}))
            .isOpen,
        isTrue,
      );
      expect(
        OnlineOrder.fromJson(
                json(over: {'status': 'accepted', 'bill_status': 'finalized'}))
            .isOpen,
        isFalse,
      );
      expect(
        OnlineOrder.fromJson(json(over: {'status': 'rejected'})).isOpen,
        isFalse,
      );
    });

    test('needsPaymentCheck only when a claim carries a reference', () {
      // The whole point of the flag: it drives the "I have received this
      // payment" checkbox, which must never appear with nothing to verify.
      expect(OnlineOrder.fromJson(json()).needsPaymentCheck, isTrue);
      expect(
        OnlineOrder.fromJson(json(over: {'payment_status': 'verified'}))
            .needsPaymentCheck,
        isFalse,
      );
      expect(
        OnlineOrder.fromJson(
                json(over: {'payment_status': 'unpaid', 'payment_txn_id': null}))
            .needsPaymentCheck,
        isFalse,
      );
    });

    test('tolerates a pickup order with no address, note or items', () {
      final o = OnlineOrder.fromJson({
        'id': 'order-2',
        'order_number': 'ORD-0002',
        'customer_phone': '9876543210',
        'fulfilment': 'pickup',
        'total': 100,
        'created_at': '2026-09-02T10:00:00.000Z',
      });
      expect(o.isDelivery, isFalse);
      expect(o.address, isNull);
      expect(o.items, isEmpty);
      expect(o.subtotal, 0);
      expect(o.paymentStatus, 'unpaid');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Packs — "1 box = 15 bottle", display only
  // ─────────────────────────────────────────────────────────────
  group('packBreakdown', () {
    test('under one pack is null', () {
      expect(packBreakdown(14, 15), isNull);
      expect(packBreakdown(15, null), isNull);
      expect(packBreakdown(15, 1), isNull);
    });
    test('whole and partial packs', () {
      expect(packBreakdown(15, 15), (packs: 1, loose: 0.0));
      expect(packBreakdown(17, 15), (packs: 1, loose: 2.0));
      expect(packBreakdown(30, 15), (packs: 2, loose: 0.0));
      expect(packBreakdown(2.5, 0.5 * 2.5), (packs: 2, loose: 0.0));
    });
  });

  group('CartEntry pack', () {
    final item = Item.fromJson({
      'id': 'i1', 'business_id': 'b', 'name': 'Water', 'price': 20,
      'unit': 'bottle', 'pack_unit': 'box', 'pack_size': '15.00',
      'is_active': true,
      'variants': [
        {'id': 'v1', 'item_id': 'i1', 'label': '500ml', 'price': 10,
         'pack_unit': 'crate', 'pack_size': 24, 'is_active': true},
        {'id': 'v2', 'item_id': 'i1', 'label': '2L', 'price': 40,
         'is_active': true},
      ],
    });

    test('plain line uses the item pack; price is untouched', () {
      final e = CartEntry(item: item, quantity: 17);
      expect(e.packUnit, 'box');
      expect(e.packs, (packs: 1, loose: 2.0));
      expect(e.lineNet(false), 340);
    });

    test('a size uses its own pack, never the item''s', () {
      expect(CartEntry(item: item, variant: item.variants[0], quantity: 48).packs,
          (packs: 2, loose: 0.0));
      final noPack = CartEntry(item: item, variant: item.variants[1], quantity: 30);
      expect(noPack.packUnit, isNull);
      expect(noPack.packs, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // matchBarcode — what a scan on the billing screen resolves to
  // ─────────────────────────────────────────────────────────────
  group('matchBarcode', () {
    final plain = Item(
        id: 'i1', businessId: 'b', name: 'Soap', barcode: '890-123 4.5', isActive: true);
    // A sized item still carrying its old item-level code from before it had sizes.
    final shirt = Item(
      id: 'i2',
      businessId: 'b',
      name: 'Shirt',
      barcode: '555',
      isActive: true,
      variants: [
        ItemVariant(id: 'v1', itemId: 'i2', label: 'M', barcode: '111'),
        ItemVariant(id: 'v2', itemId: 'i2', label: 'L', barcode: '222'),
      ],
    );
    final items = [plain, shirt];

    test('size barcode resolves to that size', () {
      final hit = matchBarcode(items, '222')!;
      expect(hit.item.id, 'i2');
      expect(hit.variant!.id, 'v2');
    });

    test('item barcode resolves to the item with no size', () {
      final hit = matchBarcode(items, '555')!;
      expect(hit.item.id, 'i2');
      expect(hit.variant, isNull);
    });

    test('spaces, dashes and dots are ignored on both sides', () {
      expect(matchBarcode(items, '89012345')!.item.id, 'i1');
      expect(matchBarcode(items, ' 8901-2345 ')!.item.id, 'i1');
    });

    test('a size barcode wins over an item barcode with the same code', () {
      final clash = Item(id: 'i3', businessId: 'b', name: 'Old', barcode: '111', isActive: true);
      expect(matchBarcode([clash, shirt], '111')!.variant!.id, 'v1');
    });

    test('unknown or empty code is null', () {
      expect(matchBarcode(items, '999'), isNull);
      expect(matchBarcode(items, ' - '), isNull);
    });
  });
}
