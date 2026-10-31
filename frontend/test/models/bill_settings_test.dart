import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/services/bill_settings.dart';

void main() {
  test('no settings (older backend / never synced) = the bill as before', () {
    final s = BillSettings.fromJson(null);
    expect(s.showCashier && s.showGstin && s.showTerms && s.showCustomer, isTrue);
    expect(s.showBank, isFalse);
    expect(s.bankLines, isEmpty);
  });

  test('bank lines need show_bank and an account number', () {
    final bank = {'account_no': '1234567890', 'bank_name': 'SBI', 'branch': 'Vengurla', 'ifsc': 'SBIN0001234'};
    expect(BillSettings.fromJson({'bank': bank}).bankLines, isEmpty);
    expect(BillSettings.fromJson({'show_bank': true, 'bank': {'ifsc': 'SBIN0001234'}}).bankLines, isEmpty);
    expect(BillSettings.fromJson({'show_bank': true, 'bank': bank}).bankLines,
        ['A/c No: 1234567890', 'Bank: SBI, Vengurla', 'IFSC: SBIN0001234']);
  });

  test('toJson round-trips; wrong types fall back to defaults', () {
    final s = BillSettings.fromJson({'show_cashier': false, 'show_gstin': 'no'});
    expect(s.showCashier, isFalse);
    expect(s.showGstin, isTrue);
    expect(BillSettings.fromJson(s.toJson()).toJson(), s.toJson());
  });

  test('shop note prints only when switched on', () {
    expect(const BillSettings(note: 'Free delivery').noteText, '');
    expect(BillSettings.fromJson({'show_note': true, 'note': ' Free delivery '}).noteText, 'Free delivery');
  });

  test('UPI QR link: amount owed, nothing for a quotation or when off', () {
    Bill bill({String status = 'finalized', String pay = 'paid'}) => Bill(
        id: 'b', businessId: 'z', billNumber: 'INV-16', subtotal: 1250,
        taxAmount: 0, discountAmount: 0, total: 1250, paymentMode: 'cash',
        status: status, paymentStatus: pay, createdByUserId: 'u',
        createdAt: DateTime(2026, 10, 28), items: const []);
    const on = BillSettings(showUpiQr: true, upiId: 'teli@okhdfcbank');
    expect(on.upiLink(bill(), 'M/S Teli', 1250),
        'upi://pay?pa=teli@okhdfcbank&pn=M%2FS%20Teli&am=1250.00&cu=INR');
    expect(on.upiLink(bill(status: 'quotation'), 'Teli', 1250), isNull);
    expect(const BillSettings(upiId: 'teli@okhdfcbank')
        .upiLink(bill(), 'Teli', 1250), isNull);
    expect(BillSettings.fromJson(on.toJson()).upiId, 'teli@okhdfcbank');
  });

  test('unit after the quantity only when show_units is on', () {
    catalogUnits = {'rice': 'kg'};
    final item = BillItem(
        id: 'i', billId: 'b', itemId: 'rice', itemName: 'Rice',
        quantity: 2, unitPrice: 50, lineTotal: 100);
    expect(const BillSettings().qty(item, '2'), '2');
    expect(BillSettings.fromJson({'show_units': true}).qty(item, '2'), '2 kg');
    catalogUnits = const {};
  });

  test('alternate number prints after the main one', () {
    final s = BillSettings.fromJson({'alt_phone': '02366-262626'});
    expect(s.shopPhones('9876500000'), '9876500000\n02366-262626');
    expect(s.shopPhones(null), '02366-262626');
    expect(const BillSettings().shopPhones('9876500000'), '9876500000');
    expect(const BillSettings().shopPhones(''), isNull);
  });
}
