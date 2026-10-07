import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/services/customer_export.dart';
import 'package:Vittam/services/xlsx_writer.dart';

/// Unzips [bytes] and returns each part's text by path.
Map<String, String> _parts(List<int> bytes) => {
      for (final f in ZipDecoder().decodeBytes(bytes))
        f.name: utf8.decode(f.content as List<int>),
    };

void main() {
  test('xlsx has every part Excel needs and escapes text safely', () {
    final parts = _parts(buildXlsx(sheetName: 'A/B: test', rows: [
      ['Name', 'Spend'],
      ['Tom & <Jerry> ₹ राम\u0001', 12.5],
      ['Count', 3],
    ]));

    expect(parts.keys, containsAll([
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'xl/styles.xml',
      'xl/worksheets/sheet1.xml',
    ]));
    final sheet = parts['xl/worksheets/sheet1.xml']!;
    // Header bold, frozen.
    expect(sheet, contains('<c r="A1" t="inlineStr" s="1"><is><t>Name</t>'));
    expect(sheet, contains('state="frozen"'));
    // Escaped, Unicode intact, illegal control char dropped.
    expect(sheet, contains('Tom &amp; &lt;Jerry&gt; ₹ राम</t>'));
    // double → money-formatted number; int → plain number.
    expect(sheet, contains('<c r="B2" s="2"><v>12.5</v></c>'));
    expect(sheet, contains('<c r="B3"><v>3</v></c>'));
    // Sheet name stripped of characters Excel rejects.
    expect(parts['xl/workbook.xml'], contains('name="A B  test"'));
  });

  test('customer list columns', () {
    final c = Customer(
      id: '1', name: 'Ramesh', phone: '9876543210', optedOut: true,
      billCount: 12, totalSpend: 4520, lastVisit: DateTime(2026, 10, 5),
    );
    final sheet = _parts(CustomerExport.customersXlsx([c]))['xl/worksheets/sheet1.xml']!;
    for (final h in ['Name', 'Phone', 'Bills', 'Total spend', 'Last visit', 'Offers']) {
      expect(sheet, contains('<t>$h</t>'));
    }
    expect(sheet, contains('<c r="C2"><v>12</v></c>'));
    expect(sheet, contains('<c r="D2" s="2"><v>4520.0</v></c>'));
    expect(sheet, contains('05 Oct 2026'));
    expect(sheet, contains('Stopped'));
  });

  test('customer bills columns: items summary and grand total', () {
    final bill = Bill.fromJson({
      'id': 'b1', 'bill_number': 'INV-42', 'subtotal': 60, 'tax_amount': 3,
      'discount_amount': 5, 'total': 63, 'round_off': 0.5,
      'payment_mode': 'upi', 'payment_status': 'paid',
      'created_at': '2026-10-05T14:15:00Z',
      'items': [
        {'item_name': 'Tea', 'quantity': 2, 'unit_price': 10, 'line_total': 20},
        {'item_name': 'Samosa', 'quantity': 1.5, 'unit_price': 20, 'line_total': 30},
      ],
    });
    final c = Customer(id: '1', name: null, phone: '9876543210',
        optedOut: false, billCount: 1, totalSpend: 58.5);
    final sheet =
        _parts(CustomerExport.billsXlsx(c, [bill]))['xl/worksheets/sheet1.xml']!;
    expect(sheet, contains('<t>Payment status</t>'));
    expect(sheet, contains('Tea ×2, Samosa ×1.5'));
    // grandTotal = total − discount + round-off = 58.5
    expect(sheet, contains('<c r="G2" s="2"><v>58.5</v></c>'));
    expect(sheet, contains('UPI'));
    expect(sheet, contains('Paid'));
  });

  test('PDFs build for both exports', () async {
    final c = Customer(id: '1', name: 'Ramesh', phone: '9876543210',
        optedOut: false, billCount: 1, totalSpend: 63);
    final bill = Bill.fromJson({
      'id': 'b1', 'bill_number': 'INV-42', 'subtotal': 60, 'tax_amount': 3,
      'total': 63, 'payment_mode': 'cash', 'created_at': '2026-10-05T14:15:00Z',
      'items': [
        {'item_name': 'Tea', 'quantity': 2, 'unit_price': 30, 'line_total': 60},
      ],
    });
    for (final pdf in [
      await CustomerExport.customersPdf([c], businessName: 'Shop'),
      await CustomerExport.billsPdf(c, [bill], businessName: 'Shop'),
    ]) {
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    }
  });
}
