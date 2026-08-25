import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import '../utils/amount_words.dart';

/// Builds an A4/A5 GST tax-invoice PDF for a finalized bill, modeled on a
/// standard printed tax invoice: bordered header box, Bill-To, an items grid
/// with a derived per-line GST column, an amount-in-words + totals summary, and
/// an HSN-wise CGST/SGST table. The page format (A4 vs A5) is passed by the
/// caller; the same template is used for both.
///
/// GST columns/table render ONLY when [gstEnabled] and the bill carries tax
/// (`taxAmount > 0`); otherwise a plain invoice prints (matching the thermal
/// receipt behaviour). Per-line GST is derived as `lineTotal − qty*unitPrice`,
/// then scaled by `discountedNet / subtotal` because bill_items store the
/// pre-discount tax while the bill's tax_amount is charged on the discounted
/// net. The Amount column is the NET line value, so it ties to the Sub Total.
class InvoicePdf {
  // Cache the loaded Devanagari font so we don't re-read the asset per invoice.
  static pw.Font? _devanagari;

  static Future<pw.Font> _loadDevanagari() async {
    _devanagari ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'));
    return _devanagari!;
  }

  static Future<Uint8List> build({
    required Bill bill,
    required PdfPageFormat pageFormat,
    required String businessName,
    String? address,
    String? gstin,
    String? fssai,
    String? defaultSacCode,
    required bool gstEnabled,
    String? footerNote,
  }) =>
      buildMany(
        bills: [bill],
        pageFormat: pageFormat,
        businessName: businessName,
        address: address,
        gstin: gstin,
        fssai: fssai,
        defaultSacCode: defaultSacCode,
        gstEnabled: gstEnabled,
        footerNote: footerNote,
      );

  /// Builds one PDF document with a page per bill (each a full invoice). Used
  /// when several bills print together (e.g. a settled bill + its previous
  /// dues) so it's a single print dialog / document.
  static Future<Uint8List> buildMany({
    required List<Bill> bills,
    required PdfPageFormat pageFormat,
    required String businessName,
    String? address,
    String? gstin,
    String? fssai,
    String? defaultSacCode,
    required bool gstEnabled,
    String? footerNote,
  }) async {
    final devanagari = await _loadDevanagari();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      // Register the oblique faces so `fontStyle: italic` actually slants (the
      // brand line in the footer); without these the pdf package silently
      // renders italic text upright.
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
      fontFallback: [devanagari],
    );

    for (final bill in bills) {
      final showGst = gstEnabled && bill.taxAmount > 0;
      // Final payable = total - discount + round_off, less any tax that must be
      // ignored because GST is off. Without the correction an older bill whose
      // stored tax_amount predates the toggle would print a grand total higher
      // than the net payable the cashier was shown.
      final grandTotal =
          bill.grandTotal - (gstEnabled ? 0.0 : bill.taxAmount);
      final dateStr = DateFormat('dd-MM-yyyy').format(bill.createdAt.toLocal());

      // Use "Rs." rather than the ₹ glyph: the base PDF font (Helvetica) has no
      // Unicode ₹, and it matches the thermal receipt's currency style.
      String money(num v) => 'Rs.${v.toStringAsFixed(2)}';
      // bill_items store the PRE-discount line tax (line_total = qty×price + tax,
      // computed before the bill-level discount), while bill.taxAmount is the
      // discounted figure. Tax is charged on the discounted net, so each line's
      // tax is scaled by discountedNet/subtotal — without this the per-line GST
      // column and its Total would exceed the CGST/SGST in the summary box.
      final discountRatio = bill.subtotal > 0
          ? (bill.subtotal - bill.discountAmount) / bill.subtotal
          : 1.0;
      double lineTaxOf(BillItem i) =>
          (i.lineTotal - (i.quantity * i.unitPrice)) * discountRatio;
      String codeOf(BillItem i) => (i.hsnCode?.isNotEmpty ?? false)
          ? i.hsnCode!
          : (defaultSacCode ?? '');

      doc.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          theme: theme,
          // Reserve a slim band at the very bottom for the brand line; the rest
          // keeps the 24pt content margin. The band must fit the footer's own
          // height (font + line) or the pdf package clips it and it stops
          // aligning to the corner.
          margin: pw.EdgeInsets.fromLTRB(24, 24, 24, 4 * PdfPageFormat.mm),
          // "Powered by Vengurlatech" pinned to the bottom-right corner, italic.
          footer: (context) => pw.Align(
            alignment: pw.Alignment.bottomRight,
            child: pw.Text('Powered by Vengurlatech',
                style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey600,
                    fontStyle: pw.FontStyle.italic)),
          ),
          build: (context) => [
            pw.Center(
              // "Tax Invoice" is a GST term: it means the document carries a
              // tax breakdown a buyer can claim input credit against. With GST
              // off there are no GST columns and no CGST/SGST box, so calling
              // it that would misrepresent a plain sale bill.
              child: pw.Text(showGst ? 'Tax Invoice' : 'Invoice',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 8),
            _headerBox(businessName, address, gstin, fssai,
                bill.billNumber, dateStr),
            _billToBox(bill),
            _itemsTable(bill, showGst, codeOf, lineTaxOf, money),
            pw.SizedBox(height: 10),
            _summary(bill, grandTotal, showGst, money),
            if (showGst) ...[
              pw.SizedBox(height: 10),
              _hsnTable(bill, codeOf, lineTaxOf, money),
            ],
            pw.SizedBox(height: 24),
            _footer(businessName, footerNote),
          ],
        ),
      );
    }

    return doc.save();
  }

  // --- Header box: business (left) | Invoice No/Date (right) --------------
  static pw.Widget _headerBox(String name, String? address, String? gstin,
      String? fssai, String billNumber, String dateStr) {
    final left = <pw.Widget>[
      pw.Text(name,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
    ];
    if (address != null && address.trim().isNotEmpty) {
      left.add(pw.SizedBox(height: 3));
      left.add(pw.Text(address.replaceAll('\r\n', '\n'),
          style: const pw.TextStyle(fontSize: 9)));
    }
    if (gstin != null && gstin.isNotEmpty) {
      left.add(pw.SizedBox(height: 3));
      left.add(pw.Text('GSTIN: $gstin',
          style: const pw.TextStyle(fontSize: 9)));
    }
    if (fssai != null && fssai.isNotEmpty) {
      left.add(pw.Text('FSSAI: $fssai',
          style: const pw.TextStyle(fontSize: 9)));
    }

    // Use a Table for the header box. A Row with `crossAxisAlignment.stretch`
    // and a full-height divider Container collapses to zero height inside the
    // page's unbounded-height Column (a known pdf-package layout pitfall) and
    // silently drops all following content — a Table lays out reliably.
    return pw.Table(
      border: pw.TableBorder.all(width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start, children: left),
          ),
          pw.Column(children: [
            pw.Container(
              width: double.infinity,
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
              child: _kvCell('Invoice No.', billNumber),
            ),
            pw.Container(width: double.infinity, child: _kvCell('Date', dateStr)),
          ]),
        ]),
      ],
    );
  }

  static pw.Widget _kvCell(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(k, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text(v,
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  // --- Bill To --------------------------------------------------------------
  static pw.Widget _billToBox(Bill bill) {
    if ((bill.customerName == null || bill.customerName!.isEmpty) &&
        (bill.customerPhone == null || bill.customerPhone!.isEmpty) &&
        (bill.tableNumber == null || bill.tableNumber!.isEmpty)) {
      return pw.SizedBox(height: 8);
    }
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
          border: pw.Border(
              left: pw.BorderSide(width: 0.8),
              right: pw.BorderSide(width: 0.8),
              bottom: pw.BorderSide(width: 0.8))),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Bill To', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 2),
          if (bill.customerName != null && bill.customerName!.isNotEmpty)
            pw.Text(bill.customerName!,
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if (bill.customerPhone != null && bill.customerPhone!.isNotEmpty)
            pw.Text('Contact No.: ${bill.customerPhone}',
                style: const pw.TextStyle(fontSize: 9)),
          if (bill.tableNumber != null && bill.tableNumber!.isNotEmpty)
            pw.Text('Table: ${bill.tableNumber}',
                style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // --- Items table ----------------------------------------------------------
  static pw.Widget _itemsTable(
      Bill bill,
      bool showGst,
      String Function(BillItem) codeOf,
      double Function(BillItem) lineTaxOf,
      String Function(num) money) {
    final headStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final cellStyle = const pw.TextStyle(fontSize: 9);
    final anyHsn = showGst && bill.items.any((i) => codeOf(i).isNotEmpty);

    pw.Widget cell(String t, {pw.TextStyle? style, pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(t, style: style ?? cellStyle),
        );

    // Column widths — # | Item | [HSN] | Qty | Price | [GST] | Amount
    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(22),           // #
      1: const pw.FlexColumnWidth(4),             // Item
    };
    var col = 2;
    if (anyHsn) widths[col++] = const pw.FixedColumnWidth(52); // HSN/SAC
    widths[col++] = const pw.FixedColumnWidth(40);            // Qty
    widths[col++] = const pw.FlexColumnWidth(1.6);           // Price
    if (showGst) widths[col++] = const pw.FlexColumnWidth(1.8); // GST
    widths[col++] = const pw.FlexColumnWidth(1.8);           // Amount

    pw.TableRow headerRow() {
      final cells = <pw.Widget>[
        cell('#', style: headStyle, align: pw.Alignment.center),
        cell('Item name', style: headStyle),
      ];
      if (anyHsn) cells.add(cell('HSN/SAC', style: headStyle, align: pw.Alignment.center));
      cells.add(cell('Qty', style: headStyle, align: pw.Alignment.centerRight));
      cells.add(cell('Price/Unit', style: headStyle, align: pw.Alignment.centerRight));
      if (showGst) cells.add(cell('GST', style: headStyle, align: pw.Alignment.centerRight));
      cells.add(cell('Amount', style: headStyle, align: pw.Alignment.centerRight));
      return pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: cells);
    }

    pw.TableRow itemRow(int idx, BillItem i) {
      final cells = <pw.Widget>[
        cell('${idx + 1}', align: pw.Alignment.center),
        cell(i.itemName),
      ];
      if (anyHsn) cells.add(cell(codeOf(i), align: pw.Alignment.center));
      cells.add(cell(formatQty(i.quantity), align: pw.Alignment.centerRight));
      cells.add(cell(money(i.unitPrice), align: pw.Alignment.centerRight));
      if (showGst) {
        final rate = i.taxRate ?? 0;
        cells.add(cell(
            '${money(lineTaxOf(i))} (${_trimRate(rate)}%)',
            align: pw.Alignment.centerRight));
      }
      // Amount is the NET line value (qty × unit price, before tax), matching
      // the thermal receipt. Tax is shown once in its own column / the summary,
      // so a tax-inclusive amount here would double-count it and the Total row
      // would no longer equal the Sub Total in the summary box.
      cells.add(cell(money(i.quantity * i.unitPrice),
          align: pw.Alignment.centerRight));
      return pw.TableRow(children: cells);
    }

    // Total row: sum of GST(₹) and the NET Amount — the latter ties back to the
    // Sub Total in the summary box.
    final totalQty = bill.items.fold<double>(0, (s, i) => s + i.quantity);
    final totalGst = bill.items.fold<double>(0, (s, i) => s + lineTaxOf(i));
    final totalAmt =
        bill.items.fold<double>(0, (s, i) => s + i.quantity * i.unitPrice);

    pw.TableRow totalRow() {
      final cells = <pw.Widget>[
        cell(''),
        cell('Total', style: headStyle),
      ];
      if (anyHsn) cells.add(cell(''));
      cells.add(cell(formatQty(totalQty), style: headStyle, align: pw.Alignment.centerRight));
      cells.add(cell(''));
      if (showGst) cells.add(cell(money(totalGst), style: headStyle, align: pw.Alignment.centerRight));
      cells.add(cell(money(totalAmt), style: headStyle, align: pw.Alignment.centerRight));
      return pw.TableRow(children: cells);
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: widths,
      children: [
        headerRow(),
        for (var idx = 0; idx < bill.items.length; idx++)
          itemRow(idx, bill.items[idx]),
        totalRow(),
      ],
    );
  }

  // --- Summary: amount-in-words + totals ------------------------------------
  static pw.Widget _summary(
      Bill bill, double grandTotal, bool showGst, String Function(num) money) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Invoice Amount in Words',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text(amountToWords(grandTotal),
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Payment mode',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text(_titleCase(bill.paymentMode),
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
            child: pw.Column(
              children: [
                // Order: Sub Total, Discount, then CGST/SGST (each half the tax),
                // Round Off, Grand Total. Discount precedes tax because tax is on
                // the discounted net. GST off → no tax rows at all, even if the
                // bill still stores a tax_amount from when the toggle was on.
                _totRow('Sub Total', money(bill.subtotal)),
                if (bill.discountAmount > 0)
                  _totRow('Discount', '- ${money(bill.discountAmount)}'),
                if (showGst) ...[
                  // Split in paise, odd paisa to CGST, so CGST + SGST adds back
                  // to exactly taxAmount. money(taxAmount / 2) twice loses or
                  // gains 0.01 on any odd-paise tax and the invoice stops
                  // footing. Mirrors _gstHalves() in printer_service_native.dart.
                  _totRow('CGST',
                      money((((bill.taxAmount * 100).round() + 1) ~/ 2) / 100)),
                  _totRow('SGST',
                      money(((bill.taxAmount * 100).round() ~/ 2) / 100)),
                ],
                if (bill.roundOff != 0)
                  _totRow('Round Off',
                      '${bill.roundOff < 0 ? '- ' : '+ '}${money(bill.roundOff.abs())}'),
                pw.Container(height: 0.6, color: PdfColors.black),
                _totRow('Grand Total', money(grandTotal), bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _totRow(String k, String v, {bool bold = false}) {
    final style = pw.TextStyle(
        fontSize: bold ? 11 : 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(k, style: style), pw.Text(v, style: style)],
      ),
    );
  }

  // --- HSN-wise CGST/SGST table --------------------------------------------
  static pw.Widget _hsnTable(
      Bill bill,
      String Function(BillItem) codeOf,
      double Function(BillItem) lineTaxOf,
      String Function(num) money) {
    // Group by HSN code: taxable = Σ qty*unitPrice, tax = Σ lineTax, rate = taxRate.
    //
    // A bill-level discount reduces the taxable value and the tax charged on it.
    // We spread it proportionally across HSN groups (by their share of the net
    // subtotal) so this detailed breakdown reconciles to the bill's stored
    // taxable/tax and grand total. `netSubtotal` is the pre-discount taxable
    // base; `discountFactor` scales every group's taxable + tax down uniformly.
    final netSubtotal = bill.items
        .fold<double>(0, (s, i) => s + i.quantity * i.unitPrice);
    final discountFactor = netSubtotal > 0
        ? (netSubtotal - bill.discountAmount) / netSubtotal
        : 1.0;
    final groups = <String, _HsnAgg>{};
    for (final i in bill.items) {
      final code = codeOf(i);
      final taxable = i.quantity * i.unitPrice * discountFactor;
      final tax = lineTaxOf(i) * discountFactor;
      final g = groups.putIfAbsent(code, () => _HsnAgg(rate: i.taxRate ?? 0));
      g.taxable += taxable;
      g.tax += tax;
    }

    final headStyle = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    final cellStyle = const pw.TextStyle(fontSize: 8.5);
    pw.Widget c(String t, {pw.TextStyle? style, pw.Alignment align = pw.Alignment.centerRight}) =>
        pw.Container(
            alignment: align,
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Text(t, style: style ?? cellStyle));

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          c('HSN/SAC', style: headStyle, align: pw.Alignment.centerLeft),
          c('Taxable amount', style: headStyle),
          c('CGST Rate', style: headStyle),
          c('CGST Amt', style: headStyle),
          c('SGST Rate', style: headStyle),
          c('SGST Amt', style: headStyle),
          c('Total Tax', style: headStyle),
        ],
      ),
    ];

    var totTaxable = 0.0, totTax = 0.0;
    groups.forEach((code, g) {
      totTaxable += g.taxable;
      totTax += g.tax;
      final half = g.rate / 2;
      rows.add(pw.TableRow(children: [
        c(code, align: pw.Alignment.centerLeft),
        c(money(g.taxable)),
        c('${_trimRate(half)}%'),
        c(money(g.tax / 2)),
        c('${_trimRate(half)}%'),
        c(money(g.tax / 2)),
        c(money(g.tax)),
      ]));
    });

    rows.add(pw.TableRow(children: [
      c('Total', style: headStyle, align: pw.Alignment.centerLeft),
      c(money(totTaxable), style: headStyle),
      c(''),
      c(money(totTax / 2), style: headStyle),
      c(''),
      c(money(totTax / 2), style: headStyle),
      c(money(totTax), style: headStyle),
    ]));

    return pw.Table(border: pw.TableBorder.all(width: 0.6), children: rows);
  }

  // --- Footer ---------------------------------------------------------------
  static pw.Widget _footer(String businessName, String? note) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Terms and conditions',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  (note != null && note.trim().isNotEmpty)
                      ? note
                      : 'Thanks for doing business with us!',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        pw.Text('For: $businessName',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  // --- helpers --------------------------------------------------------------
  /// Rate without trailing ".0" (e.g. 9, 2.5).
  static String _trimRate(num r) {
    if (r == r.roundToDouble()) return r.toInt().toString();
    return r.toString();
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _HsnAgg {
  final double rate;
  double taxable = 0;
  double tax = 0;
  _HsnAgg({required this.rate});
}
