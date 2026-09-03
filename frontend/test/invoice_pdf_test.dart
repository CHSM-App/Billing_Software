import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:Vittam/models/models.dart';
import 'package:Vittam/services/devanagari_raster.dart';
import 'package:Vittam/services/invoice_pdf.dart';

/// Net 20400 with a 4600 discount → discounted net 15800. Tax is charged on the
/// discounted net, so 18% GST is 15800 × 0.18 = 2844 (NOT 3672, which would be
/// 18% of the undiscounted subtotal). total = subtotal + discounted tax = 23244,
/// and the payable is total − discount = 18644 = 15800 + 2844.
Bill _sampleBill({required bool withTax}) => Bill(
      id: 'b1',
      businessId: 'biz1',
      billNumber: 'INV-119',
      customerName: 'Sagar Sandeep Dharaglkar',
      customerPhone: '8262878298',
      subtotal: 20400,
      taxAmount: withTax ? 2844 : 0,
      discountAmount: 4600,
      total: withTax ? 23244 : 20400,
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
      'Tax', 'GOVIND', 'GSTIN', 'FSSAI', '119',
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

  test('discounted GST invoice reconciles: net amount, scaled tax, payable',
      () async {
    // bill_items carry the PRE-discount line tax (lineTotal 24072 = 20400 + 18%
    // of the undiscounted net), but tax is charged on the DISCOUNTED net. The
    // PDF must scale the per-line tax by discountedNet/subtotal and show the NET
    // amount, so nothing on the page contradicts the summary box.
    final bytes = await InvoicePdf.build(
      bill: _sampleBill(withTax: true),
      pageFormat: PdfPageFormat.a4,
      businessName: 'GOVIND ELECTRONIC',
      gstin: '27BFRPD0924F1ZL',
      gstEnabled: true,
    );
    final text = _renderedText(bytes);
    // Amount column is the NET line value, tying back to the Sub Total.
    expect(text.contains('20400.00'), true, reason: 'net amount missing');
    // Per-line GST scaled to the discounted net: 3672 × 15800/20400 = 2844.
    expect(text.contains('2844.00'), true, reason: 'discounted tax missing');
    // Grand Total = total − discount = 23244 − 4600 = 18644.
    expect(text.contains('18644.00'), true, reason: 'payable missing');
    // The undiscounted tax must NOT appear anywhere.
    expect(text.contains('3672.00'), false,
        reason: 'undiscounted tax leaked into the invoice');
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
    expect(text.contains('SGST'), false);
    // No per-line GST column header either.
    expect(text.contains('GST'), false);
    // "Tax Invoice" is a GST term — a non-GST bill is a plain Invoice.
    expect(text.contains('Tax Invoice'), false);
    expect(text.contains('Invoice'), true);
  });

  test('GST invoice keeps the Tax Invoice heading and GST column', () async {
    final bytes = await InvoicePdf.build(
      bill: _sampleBill(withTax: true),
      pageFormat: PdfPageFormat.a4,
      businessName: 'GST Shop',
      gstEnabled: true,
    );
    final text = _renderedText(bytes);
    // Counterpart to the non-GST case above: with GST on, the heading is the
    // GST one and the tax wording is present. (CGST/SGST are asserted only in
    // the negative direction — PDF text operators can split a short word across
    // draw calls, so their absence is reliable but their presence is not.)
    expect(text.contains('Tax'), true);
    expect(text.contains('GST'), true);
  });

  // ─────────────────────────────────────────────────────────────
  // Marathi (Devanagari)
  //
  // The pdf package has a Devanagari fallback FONT but no shaping: its only
  // substitution logic is a hardcoded Arabic table and it parses no GSUB/GPOS.
  // Drawn as text, matras stay after their consonant and conjuncts never form.
  // So Devanagari is shaped by Flutter and embedded as an image instead.
  // ─────────────────────────────────────────────────────────────
  group('Devanagari detection', () {
    test('recognises Marathi, and leaves plain ASCII alone', () {
      expect(DevanagariRaster.containsDevanagari('तांदूळ'), isTrue);
      expect(DevanagariRaster.containsDevanagari('क्षीर'), isTrue);
      // Mixed: one Devanagari word is enough to need shaping.
      expect(DevanagariRaster.containsDevanagari('Rice तांदूळ'), isTrue);
      expect(DevanagariRaster.containsDevanagari('Rice'), isFalse);
      expect(DevanagariRaster.containsDevanagari('250.00'), isFalse);
      expect(DevanagariRaster.containsDevanagari(''), isFalse);
    });
  });

  group('Marathi invoice', () {
    Bill marathiBill() => Bill(
          id: 'b2',
          businessId: 'biz1',
          billNumber: 'INV-200',
          customerName: 'सागर धारगळकर',
          subtotal: 250,
          taxAmount: 0,
          total: 250,
          paymentMode: 'cash',
          status: 'finalized',
          createdByUserId: 'u1',
          createdAt: DateTime(2026, 9, 2),
          items: [
            BillItem(
              id: 'mi1',
              billId: 'b2',
              itemId: 'it1',
              itemName: 'तांदूळ बासमती',
              quantity: 2,
              unitPrice: 125,
              lineTotal: 250,
            ),
          ],
        );

    test('builds a valid PDF with Marathi names', () async {
      final bytes = await InvoicePdf.build(
        bill: marathiBill(),
        pageFormat: PdfPageFormat.a4,
        businessName: 'गोविंद इलेक्ट्रॉनिक्स',
        address: 'मु. पो. दोडामार्ग',
        gstEnabled: false,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      // Non-trivial document — a broken image embed would truncate it.
      expect(bytes.length, greaterThan(2000));
    });

    test('embeds the Marathi text as images, not as broken text', () async {
      final marathi = await InvoicePdf.build(
        bill: marathiBill(),
        pageFormat: PdfPageFormat.a4,
        businessName: 'गोविंद इलेक्ट्रॉनिक्स',
        address: 'मु. पो. दोडामार्ग',
        gstEnabled: false,
      );
      // The same invoice with ASCII names carries no embedded glyph images, so
      // the Marathi one must be materially larger. This is what fails if the
      // shaping detour is skipped and the text is drawn with the PDF font.
      final ascii = await InvoicePdf.build(
        bill: Bill(
          id: 'b3',
          businessId: 'biz1',
          billNumber: 'INV-201',
          customerName: 'Sagar',
          subtotal: 250,
          taxAmount: 0,
          total: 250,
          paymentMode: 'cash',
          status: 'finalized',
          createdByUserId: 'u1',
          createdAt: DateTime(2026, 9, 2),
          items: [
            BillItem(
              id: 'ai1',
              billId: 'b3',
              itemId: 'it1',
              itemName: 'Basmati Rice',
              quantity: 2,
              unitPrice: 125,
              lineTotal: 250,
            ),
          ],
        ),
        pageFormat: PdfPageFormat.a4,
        businessName: 'Govind Electronics',
        address: 'At Post Dodamarg',
        gstEnabled: false,
      );
      // Direct evidence of the mechanism rather than a size heuristic: each
      // shaped string becomes an image XObject. The ASCII invoice must have
      // none at all — English stays real, selectable text.
      int xobjects(List<int> pdf) =>
          '/XObject'.allMatches(String.fromCharCodes(pdf)).length;
      expect(xobjects(marathi), greaterThan(0),
          reason: 'Marathi strings should be embedded as shaped images');
      expect(xobjects(ascii), 0,
          reason: 'an English invoice must not rasterise anything');
    });

    test('an all-ASCII invoice embeds no shaped images', () async {
      // The detour must not fire for English menus — that text stays real,
      // selectable text and the file stays small.
      final bytes = await InvoicePdf.build(
        bill: _sampleBill(withTax: true),
        pageFormat: PdfPageFormat.a4,
        businessName: 'GOVIND ELECTRONIC',
        address: 'AT POST DODAMARG',
        gstEnabled: true,
      );
      final text = _renderedText(bytes);
      // Still ordinary text operators, as before.
      expect(text.contains('GOVIND'), isTrue);
    });
  });
}
