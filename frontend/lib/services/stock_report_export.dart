import 'dart:typed_data';

import 'customer_export.dart';
import 'xlsx_writer.dart';

/// Excel / PDF rows for the Opening-Closing stock and Item profit reports.
/// Both formats share the same rows; in Excel the figures are real numbers.
class StockReportExport {
  static const xlsxMime = CustomerExport.xlsxMime;
  static const pdfMime = CustomerExport.pdfMime;

  static double _n(Object? v) => v == null ? 0 : double.tryParse('$v') ?? 0;
  static double? _nn(Object? v) => v == null ? null : double.tryParse('$v');

  // ---- Stock ---------------------------------------------------------------

  /// Sold is net of voided bills (a cancelled bill is not a sale), so
  /// Closing = Opening + Purchased − Sold holds. [unit] adds the Unit column
  /// (Excel only; the PDF leaves it out).
  static List<List<Object?>> stockRows(List<Map<String, dynamic>> rows,
          {bool unit = true}) =>
      [
        ['Item', if (unit) 'Unit', 'Opening', 'Purchased', 'Sold', 'Closing'],
        for (final r in rows)
          [
            r['name'] ?? '',
            if (unit) r['unit'] ?? '',
            _n(r['opening']),
            _n(r['purchased']),
            _n(r['sold']) - _n(r['returned']),
            _n(r['closing']),
          ],
      ];

  static Uint8List stockXlsx(List<Map<String, dynamic>> rows) => buildXlsx(
        sheetName: 'Stock',
        colWidths: const [30, 8, 11, 11, 11, 11],
        rows: stockRows(rows),
      );

  static Future<Uint8List> stockPdf(List<Map<String, dynamic>> rows,
          {required String businessName, required String period}) =>
      CustomerExport.tablePdf(
        businessName: businessName,
        title: 'Opening & closing stock',
        subtitle: period,
        rows: stockRows(rows, unit: false),
        leftAlignNumbers: true,
        widths: const [211, 70, 70, 70, 70],
      );

  // ---- One item, day by day ------------------------------------------------

  static List<List<Object?>> dailyRows(List<Map<String, dynamic>> days) => [
        ['Date', 'Opening', 'Purchased', 'Sold', 'Closing'],
        for (final d in days)
          [d['date'] ?? '', _n(d['opening']), _n(d['purchased']), _n(d['sold']), _n(d['closing'])],
      ];

  static Uint8List dailyXlsx(List<Map<String, dynamic>> days, {required String item}) =>
      buildXlsx(
        sheetName: item,
        colWidths: const [14, 11, 11, 11, 11],
        rows: dailyRows(days),
      );

  static Future<Uint8List> dailyPdf(List<Map<String, dynamic>> days,
          {required String businessName, required String item, required String period}) =>
      CustomerExport.tablePdf(
        businessName: businessName,
        title: '$item - daily stock',
        subtitle: period,
        rows: dailyRows(days),
        leftAlignNumbers: true,
        widths: const [110, 70, 70, 70, 70],
      );

  // ---- Profit --------------------------------------------------------------

  static List<List<Object?>> profitRows(List<Map<String, dynamic>> rows) => [
        [
          'Item', 'Qty sold', 'Net sales', 'Avg buy', 'Avg sell', 'Profit / unit',
          'Profit', 'Margin %', 'Qty, cost missing',
        ],
        for (final r in rows)
          [
            r['name'] ?? '',
            _n(r['qty']),
            _n(r['sales']),
            _nn(r['avg_cost']) ?? '',
            _nn(r['avg_sell']) ?? '',
            (_nn(r['avg_sell']) != null && _nn(r['avg_cost']) != null)
                ? _nn(r['avg_sell'])! - _nn(r['avg_cost'])!
                : '',
            _n(r['profit']),
            _nn(r['margin_pct']) ?? '',
            _n(r['qty_no_cost']),
          ],
      ];

  static Uint8List profitXlsx(List<Map<String, dynamic>> rows) => buildXlsx(
        sheetName: 'Item profit',
        colWidths: const [30, 10, 13, 11, 11, 12, 13, 10, 14],
        rows: profitRows(rows),
      );

  static Future<Uint8List> profitPdf(List<Map<String, dynamic>> rows,
          {required String businessName,
          required String period,
          required double totalProfit}) =>
      CustomerExport.tablePdf(
        businessName: businessName,
        title: 'Item-wise net profit',
        subtitle: '$period · Total profit ${totalProfit.toStringAsFixed(2)}',
        rows: profitRows(rows),
        leftAlignNumbers: true,
        widths: const [130, 40, 58, 48, 48, 50, 58, 42, 50],
        landscape: true,
      );
}
