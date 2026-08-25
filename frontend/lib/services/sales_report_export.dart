import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';

/// Builds the downloadable sales report (CSV + PDF) for a reporting period.
///
/// Figures come from two server calls the Reports screen already makes or can
/// make cheaply: `/api/reports/summary` (period totals, daily split, payment
/// split, top items) and `/api/bills?from&to` (the invoice-wise list). Only
/// finalized bills are listed so the invoice section reconciles with the
/// summary totals, which count finalized bills only.
class SalesReportExport {
  static final _dateFmt = DateFormat('dd MMM yyyy');
  static final _dateTimeFmt = DateFormat('dd MMM yyyy, h:mm a');

  static String _csvField(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _row(List<Object?> cells) => cells.map(_csvField).join(',');

  static double _num(Object? v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  static String _money(Object? v) => _num(v).toStringAsFixed(2);

  static String _fmtDay(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : _dateFmt.format(d);
  }

  static String _fmtWhen(Object? iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    return d == null ? (iso?.toString() ?? '') : _dateTimeFmt.format(d.toLocal());
  }

  /// Net amount collected on a bill — the same rule the summary endpoint uses
  /// (total − discount + round-off), so per-invoice rows sum to the total.
  static double _net(Map<String, dynamic> b) =>
      _num(b['total']) - _num(b['discount_amount']) + _num(b['round_off']);

  /// Effective payment mode: a settled credit bill reports the mode it was
  /// actually collected in, matching the summary's payment split.
  static String _mode(Map<String, dynamic> b) {
    final mode = (b['payment_mode'] ?? '').toString();
    if (mode == 'credit' &&
        b['payment_status'] == 'paid' &&
        (b['settled_payment_mode'] ?? '').toString().isNotEmpty) {
      return b['settled_payment_mode'].toString();
    }
    return mode;
  }

  static List<Map<String, dynamic>> _finalized(List<dynamic> bills) => bills
      .map((e) => Map<String, dynamic>.from(e as Map))
      .where((b) => (b['status'] ?? 'finalized') == 'finalized')
      .toList();

  /// CSV in sections: period totals, payment split, daily sales, top items,
  /// then one row per invoice. UTF-8 **with a BOM** so Excel keeps the rupee
  /// sign and any Devanagari text intact.
  static Uint8List buildCsv({
    required ReportSummary summary,
    required List<dynamic> bills,
    required String businessName,
  }) {
    final b = StringBuffer();
    final rows = _finalized(bills);

    b.writeln(_row(['Sales Report']));
    b.writeln(_row(['Business', businessName]));
    b.writeln(_row(['Period From', _fmtDay(summary.from)]));
    b.writeln(_row(['Period To', _fmtDay(summary.to)]));
    b.writeln(_row(['Bills', summary.billCount]));
    b.writeln(_row(['Net Sales', _money(summary.netSales)]));
    b.writeln(_row(['Discount Given', _money(summary.totalDiscount)]));
    b.writeln(_row(['Tax Collected', _money(summary.totalTax)]));
    b.writeln(_row(['Average Bill', _money(summary.avgBill)]));
    b.writeln(_row(['Expenses', _money(summary.totalExpenses)]));
    b.writeln(_row(['Net Profit', _money(summary.netProfit)]));
    b.writeln();

    b.writeln(_row(['Payment Split']));
    b.writeln(_row(['Mode', 'Amount']));
    for (final e in summary.byPaymentMode.entries) {
      if (e.value == 0) continue;
      b.writeln(_row([e.key.toUpperCase(), _money(e.value)]));
    }
    b.writeln();

    b.writeln(_row(['Daily Sales']));
    b.writeln(_row(['Date', 'Sales', 'Expenses', 'Profit']));
    for (final d in summary.daily) {
      b.writeln(_row(
          [_fmtDay(d.day), _money(d.revenue), _money(d.expenses), _money(d.profit)]));
    }
    b.writeln();

    if (summary.topItems.isNotEmpty) {
      b.writeln(_row(['Top Items']));
      b.writeln(_row(['Item', 'Qty Sold', 'Revenue']));
      for (final t in summary.topItems) {
        b.writeln(_row([t.itemName, t.qtySold, _money(t.revenue)]));
      }
      b.writeln();
    }

    b.writeln(_row(['Invoices']));
    b.writeln(_row([
      'Bill No',
      'Date',
      'Customer',
      'Phone',
      'Subtotal',
      'Tax',
      'Discount',
      'Round Off',
      'Net Amount',
      'Payment Mode',
      'Payment Status',
    ]));
    for (final r in rows) {
      b.writeln(_row([
        r['bill_number'],
        _fmtWhen(r['created_at']),
        r['customer_name'],
        r['customer_phone'],
        _money(r['subtotal']),
        _money(r['tax_amount']),
        _money(r['discount_amount']),
        _money(r['round_off']),
        _money(_net(r)),
        _mode(r).toUpperCase(),
        (r['payment_status'] ?? 'paid').toString(),
      ]));
    }

    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
  }

  static Future<Uint8List> buildPdf({
    required ReportSummary summary,
    required List<dynamic> bills,
    required String businessName,
  }) async {
    final doc = pw.Document();
    final rows = _finalized(bills);

    final head = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    const cell = pw.TextStyle(fontSize: 8.5);

    pw.Widget cellText(String t, {bool bold = false, bool right = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(t,
              style: bold ? head : cell,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
        );

    pw.TableRow headerRow(List<String> cols, Set<int> rightCols) => pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            for (var i = 0; i < cols.length; i++)
              cellText(cols[i], bold: true, right: rightCols.contains(i)),
          ],
        );

    pw.Widget section(String title) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Text(title, style: head),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (c) => pw.Align(
          alignment: pw.Alignment.bottomRight,
          child: pw.Text('Page ${c.pageNumber} of ${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text('SALES REPORT',
                style:
                    pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text(businessName,
                  style: const pw.TextStyle(fontSize: 11))),
          pw.Center(
            child: pw.Text(
                'Period: ${_fmtDay(summary.from)}  to  ${_fmtDay(summary.to)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.SizedBox(height: 12),

          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _stat('Bills', '${summary.billCount}'),
                _stat('Net Sales', _money(summary.netSales)),
                _stat('Discount', _money(summary.totalDiscount)),
                _stat('Tax', _money(summary.totalTax)),
                _stat('Avg Bill', _money(summary.avgBill)),
                _stat('Expenses', _money(summary.totalExpenses)),
                _stat('Net Profit', _money(summary.netProfit)),
              ],
            ),
          ),

          section('Payment Split'),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1)},
            children: [
              headerRow(['Mode', 'Amount'], {1}),
              for (final e in summary.byPaymentMode.entries)
                if (e.value != 0)
                  pw.TableRow(children: [
                    cellText(e.key.toUpperCase()),
                    cellText(_money(e.value), right: true),
                  ]),
            ],
          ),

          section('Daily Sales'),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.2),
            },
            children: [
              headerRow(['Date', 'Sales', 'Expenses', 'Profit'], {1, 2, 3}),
              for (final d in summary.daily)
                pw.TableRow(children: [
                  cellText(_fmtDay(d.day)),
                  cellText(_money(d.revenue), right: true),
                  cellText(_money(d.expenses), right: true),
                  cellText(_money(d.profit), right: true),
                ]),
            ],
          ),

          if (summary.topItems.isNotEmpty) ...[
            section('Top Items'),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.3),
              },
              children: [
                headerRow(['Item', 'Qty', 'Revenue'], {1, 2}),
                for (final t in summary.topItems)
                  pw.TableRow(children: [
                    cellText(t.itemName),
                    cellText(_qty(t.qtySold), right: true),
                    cellText(_money(t.revenue), right: true),
                  ]),
              ],
            ),
          ],

          section('Invoices (${rows.length})'),
          if (rows.isEmpty)
            pw.Text('No bills in this period.', style: cell)
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.3),
                1: pw.FlexColumnWidth(1.9),
                2: pw.FlexColumnWidth(1.8),
                3: pw.FlexColumnWidth(1),
                4: pw.FlexColumnWidth(1),
                5: pw.FlexColumnWidth(1.1),
                6: pw.FlexColumnWidth(1),
              },
              children: [
                headerRow([
                  'Bill No',
                  'Date',
                  'Customer',
                  'Tax',
                  'Discount',
                  'Net',
                  'Mode'
                ], {3, 4, 5}),
                for (final r in rows)
                  pw.TableRow(children: [
                    cellText((r['bill_number'] ?? '').toString()),
                    cellText(_fmtWhen(r['created_at'])),
                    cellText((r['customer_name'] ?? '').toString()),
                    cellText(_money(r['tax_amount']), right: true),
                    cellText(_money(r['discount_amount']), right: true),
                    cellText(_money(_net(r)), right: true),
                    cellText(_mode(r).toUpperCase()),
                  ]),
              ],
            ),
        ],
      ),
    );

    return doc.save();
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

  static pw.Widget _stat(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        ],
      );
}
