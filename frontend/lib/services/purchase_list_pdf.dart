import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One line on a purchase (reorder) list: an item name plus the quantity to
/// buy.
class PurchaseListLine {
  final String name;
  final double quantity;
  final String unit;

  PurchaseListLine({
    required this.name,
    required this.quantity,
    required this.unit,
  });
}

/// Builds a simple A4 PDF of items to purchase, for handing to a vendor or
/// keeping as a shopping list. Deliberately plain — no GST/pricing math, since
/// a purchase list precedes the vendor bill rather than replacing it.
class PurchaseListPdf {
  static Future<Uint8List> build(List<PurchaseListLine> lines) async {
    final doc = pw.Document();
    final head = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    const cell = pw.TextStyle(fontSize: 9);

    pw.Widget cellText(String t, {bool bold = false, bool right = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(t,
              style: bold ? head : cell,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
        );

    String fmtQty(double q) => q % 1 == 0
        ? q.toInt().toString()
        : q.toStringAsFixed(2);

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
            child: pw.Text('PURCHASE LIST',
                style:
                    pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  cellText('Item', bold: true),
                  cellText('Qty to purchase', bold: true, right: true),
                ],
              ),
              for (final l in lines)
                pw.TableRow(children: [
                  cellText(l.name),
                  cellText('${fmtQty(l.quantity)} ${l.unit}', right: true),
                ]),
              if (lines.isEmpty)
                pw.TableRow(children: [
                  cellText('—'),
                  cellText('—', right: true),
                ]),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }
}
