import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:Vittam/models/models.dart';
import 'package:Vittam/services/invoice_pdf.dart';

Bill _sampleBill({required bool withTax}) => Bill(
      id: 'b1',
      businessId: 'biz1',
      billNumber: 'INV-119',
      customerName: 'Sagar Sandeep Dharaglkar',
      customerPhone: '8262878298',
      subtotal: 20400,
      taxAmount: withTax ? 3672 : 0,
      discountAmount: 4600,
      total: withTax ? 24072 : 20400,
      paymentMode: 'cash',
      status: 'finalized',
      createdByUserId: 'u1',
      createdAt: DateTime(2026, 4, 27),
      items: [
        BillItem(
          id: 'i1',
          billId: 'b1',
          itemName: 'WHIRLPOOL DOUBLE DOOR FREEZ',
          quantity: 1,
          unitPrice: 20400,
          taxRate: withTax ? 18 : null,
          hsnCode: '8418',
          lineTotal: withTax ? 24072 : 20400,
        ),
      ],
    );

/// Inflate every FlateDecode stream and flatten the drawn text (each `(...)`
/// group in the content stream is a run of glyphs). Lets tests assert the PDF
/// actually RENDERS content rather than just being non-empty — a blank page
/// (the earlier layout bug) would fail these.
String _renderedText(List<int> raw) {
  final sb = StringBuffer();
  for (int i = 0; i < raw.length - 9; i++) {
    if (raw[i] == 0x73 && raw[i + 1] == 0x74 && raw[i + 2] == 0x72 &&
        raw[i + 3] == 0x65 && raw[i + 4] == 0x61 && raw[i + 5] == 0x6d) {
      var s = i + 6;
      if (raw[s] == 0x0d) s++;
      if (raw[s] == 0x0a) s++;
      int e = s;
      while (e < raw.length - 9) {
        if (raw[e] == 0x65 && raw[e + 1] == 0x6e && raw[e + 2] == 0x64 &&
            raw[e + 3] == 0x73 && raw[e + 4] == 0x74 && raw[e + 5] == 0x72) {
          break;
        }
        e++;
      }
      try {
        sb.write(latin1.decode(zlib.decode(raw.sublist(s, e)), allowInvalid: true));
      } catch (_) {}
      i = e;
    }
  }
  final content = sb.toString();
  return RegExp(r'\(([^)]*)\)')
      .allMatches(content)
      .map((m) => m.group(1))
      .join();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A4 GST invoice renders all sections', () async {
    final bytes = await InvoicePdf.build(
      bill: _sampleBill(withTax: true),
      pageFormat: PdfPageFormat.a4,
      businessName: 'GOVIND ELECTRONIC',
      address: 'AT POST DODAMARG',
      gstin: '27BFRPD0924F1ZL',
      fssai: '11519026000034',
      gstEnabled: true,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final text = _renderedText(bytes);
    for (final needle in [
      'Tax', 'GOVIND', 'GSTIN', 'FSSAI', 'INV-119',
      '8418', 'Sagar', 'GST', 'Grand', 'Rupees',
    ]) {
      expect(text.contains(needle), true, reason: 'PDF missing "$needle"');
    }
  });

  test('A5 invoice renders content', () async {
    final bytes = await InvoicePdf.build(
      bill: _sampleBill(withTax: true),
      pageFormat: PdfPageFormat.a5,
      businessName: 'GOVIND ELECTRONIC',
      gstEnabled: true,
    );
    final text = _renderedText(bytes);
    expect(text.contains('GOVIND'), true);
    expect(text.contains('Grand'), true);
  });

  test('non-GST invoice omits GST columns/table', () async {
    final bytes = await InvoicePdf.build(
      bill: _sampleBill(withTax: false),
      pageFormat: PdfPageFormat.a4,
      businessName: 'Retail Shop',
      gstEnabled: false,
    );
    final text = _renderedText(bytes);
    expect(text.contains('Retail'), true);
    expect(text.contains('Grand'), true);
    // No CGST/SGST HSN table when GST is off.
    expect(text.contains('CGST'), false);
  });
}
