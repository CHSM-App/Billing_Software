import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import 'invoice_pdf.dart' show ShapedText;
import 'xlsx_writer.dart';

/// Excel and PDF exports for the Customers screen: the customer list, and one
/// customer's bills. Both formats share the same rows, so they always carry
/// the same columns. In Excel the amounts are real numbers and sum.
// ponytail: dates are written as display text, so Excel sorts them A→Z, not
// by time. Write date serials + a date numFmt if owners need date sorting.
class CustomerExport {
  static const xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const pdfMime = 'application/pdf';

  static final _dateFmt = DateFormat('dd MMM yyyy');
  static final _dateTimeFmt = DateFormat('dd MMM yyyy, h:mm a');
  static final _moneyFmt = NumberFormat('#,##0.00');

  // ---- Rows (header first) -------------------------------------------------

  static List<List<Object?>> _customerRows(List<Customer> customers) => [
        ['Name', 'Phone', 'Bills', 'Total spend', 'Last visit', 'Offers'],
        for (final c in customers)
          [
            c.name?.trim() ?? '',
            c.phone,
            c.billCount,
            c.totalSpend,
            c.lastVisit == null ? '' : _dateFmt.format(c.lastVisit!.toLocal()),
            c.optedOut ? 'Stopped' : 'Allowed',
          ],
      ];

  static List<List<Object?>> _billRows(List<Bill> bills) => [
        [
          'Bill no', 'Date & time', 'Items', 'Subtotal', 'Tax', 'Discount',
          'Total', 'Payment mode', 'Payment status',
        ],
        for (final b in bills)
          [
            b.billNumber,
            _dateTimeFmt.format(b.createdAt.toLocal()),
            b.items.map((i) => '${i.itemName} ×${_qty(i.quantity)}').join(', '),
            b.subtotal,
            b.taxAmount,
            b.discountAmount,
            // Same figure the bill row on screen shows.
            b.grandTotal,
            b.paymentMode.toUpperCase(),
            _capitalize(b.paymentStatus),
          ],
      ];

  // ---- Excel ---------------------------------------------------------------

  static Uint8List customersXlsx(List<Customer> customers) => buildXlsx(
        sheetName: 'Customers',
        colWidths: const [26, 15, 8, 14, 14, 10],
        rows: _customerRows(customers),
      );

  static Uint8List billsXlsx(Customer customer, List<Bill> bills) => buildXlsx(
        sheetName: customer.displayName,
        colWidths: const [14, 22, 40, 11, 10, 10, 11, 13, 14],
        rows: _billRows(bills),
      );

  // ---- PDF -----------------------------------------------------------------

  static Future<Uint8List> customersPdf(List<Customer> customers,
          {required String businessName}) =>
      _pdf(
        businessName: businessName,
        title: 'Customers',
        subtitle: '${customers.length} customers · Total spend '
            '${_moneyFmt.format(customers.fold<double>(0, (s, c) => s + c.totalSpend))}',
        rows: _customerRows(customers),
        widths: const [180, 80, 45, 80, 80, 60],
        landscape: false,
      );

  static Future<Uint8List> billsPdf(Customer customer, List<Bill> bills,
          {required String businessName}) =>
      _pdf(
        businessName: businessName,
        title: customer.displayName,
        subtitle: '${customer.phone} · ${bills.length} bills · Total '
            '${_moneyFmt.format(bills.fold<double>(0, (s, b) => s + b.grandTotal))}',
        rows: _billRows(bills),
        widths: const [70, 100, 250, 60, 50, 55, 60, 60, 60],
        landscape: true,
      );

  static const _fs = 8.5;

  /// A4 table of [rows] (header repeated on every page) under a small title
  /// block. [widths] are fixed column widths in points and must fit the page.
  static Future<Uint8List> _pdf({
    required String businessName,
    required String title,
    required String subtitle,
    required List<List<Object?>> rows,
    required List<double> widths,
    required bool landscape,
  }) async {
    // Marathi names/items: shape them into images up front (the pdf package
    // cannot shape Devanagari — see ShapedText), at the width of their column.
    final shaped = ShapedText();
    await shaped.add(businessName, fontSize: 14, bold: true, maxWidth: 500);
    await shaped.add(title, fontSize: 11, bold: true, maxWidth: 500);
    for (final row in rows.skip(1)) {
      for (var i = 0; i < row.length; i++) {
        final v = row[i];
        if (v is String) await shaped.add(v, fontSize: _fs, maxWidth: widths[i] - 8);
      }
    }

    const grey = PdfColors.grey700;
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: grey)),
      ),
      build: (_) => [
        shaped.widget(businessName,
            fontSize: 14,
            bold: true,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        shaped.widget(title,
            fontSize: 11,
            bold: true,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: grey)),
        pw.Text('Generated ${_dateTimeFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: grey)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            for (var i = 0; i < widths.length; i++)
              i: pw.FixedColumnWidth(widths[i]),
          },
          children: [
            for (var r = 0; r < rows.length; r++)
              pw.TableRow(
                repeat: r == 0,
                decoration: r == 0
                    ? const pw.BoxDecoration(color: PdfColors.grey200)
                    : null,
                children: [
                  for (final v in rows[r])
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4, vertical: 3),
                      child: _cell(v, header: r == 0, shaped: shaped),
                    ),
                ],
              ),
          ],
        ),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _cell(Object? v,
      {required bool header, required ShapedText shaped}) {
    if (header) {
      return pw.Text('$v',
          style: pw.TextStyle(fontSize: _fs, fontWeight: pw.FontWeight.bold));
    }
    if (v is num) {
      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(v is int ? '$v' : _moneyFmt.format(v),
            style: const pw.TextStyle(fontSize: _fs)),
      );
    }
    return shaped.widget('${v ?? ''}',
        fontSize: _fs, style: const pw.TextStyle(fontSize: _fs));
  }

  // ---- Helpers -------------------------------------------------------------

  /// `2.0` → `2`, `1.5` → `1.5`.
  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// File-name-safe version of [s] (customer names can hold / : etc.).
  static String fileSafe(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}
