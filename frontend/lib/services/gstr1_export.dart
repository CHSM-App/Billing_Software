import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the downloadable artefacts for the GSTR-1 report.
///
/// SCOPE NOTE: bills carry no buyer GSTIN, so every sale is B2C. The return
/// therefore consists of a consolidated rate-wise B2CS section and an HSN
/// summary — there is deliberately no invoice-wise B2B section, because
/// emitting one would require buyer GSTINs this system does not capture.
///
/// The figures come straight from the server (`/api/reports/gstr1`), which
/// mirrors the printed receipt's money rules, so the return reconciles with
/// what customers were actually charged.
class Gstr1Export {
  /// Escape one CSV field: quote when it contains a comma, quote or newline,
  /// and double any embedded quotes. Without this an item description with a
  /// comma would silently shift every later column.
  static String _csvField(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _row(List<Object?> cells) => cells.map(_csvField).join(',');

  static String _money(Object? v) => (_num(v)).toStringAsFixed(2);

  static double _num(Object? v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  /// CSV laid out in the sections of the GSTR-1 offline utility, so the figures
  /// can be transcribed or imported without re-deriving anything.
  ///
  /// Returned as UTF-8 **with a BOM** — Excel otherwise reads the file as the
  /// system codepage and mangles the rupee sign and any Devanagari text.
  static Uint8List buildCsv(Map<String, dynamic> report) {
    final b = StringBuffer();
    final business = Map<String, dynamic>.from(report['business'] ?? {});
    final totals = Map<String, dynamic>.from(report['totals'] ?? {});

    b.writeln(_row(['GSTR-1 Summary']));
    b.writeln(_row(['Business', business['name'] ?? '']));
    b.writeln(_row(['GSTIN', business['gstin'] ?? '']));
    b.writeln(_row(['Period From', report['from'] ?? '']));
    b.writeln(_row(['Period To', report['to'] ?? '']));
    b.writeln(_row(['Invoices', totals['bill_count'] ?? 0]));
    b.writeln(_row(['Invoice Value', _money(totals['invoice_value'])]));
    b.writeln(_row(['Total Taxable Value', _money(totals['taxable_value'])]));
    b.writeln(_row(['Total CGST', _money(totals['cgst'])]));
    b.writeln(_row(['Total SGST', _money(totals['sgst'])]));
    b.writeln();

    // --- B2CS ---------------------------------------------------------------
    // All supplies are B2C (no buyer GSTIN is captured), reported consolidated
    // by rate rather than invoice-wise.
    b.writeln(_row(['B2CS - Consolidated B2C Supplies']));
    b.writeln(_row([
      'Type',
      'Place Of Supply',
      'Rate',
      'Taxable Value',
      'CGST',
      'SGST',
      'Total Tax',
    ]));
    for (final r in (report['b2cs'] as List? ?? [])) {
      final m = Map<String, dynamic>.from(r as Map);
      b.writeln(_row([
        'OE', // Other than E-commerce
        business['state'] ?? '',
        _num(m['rate']).toStringAsFixed(2),
        _money(m['taxable_value']),
        _money(m['cgst']),
        _money(m['sgst']),
        _money(m['total_tax']),
      ]));
    }
    b.writeln();

    // --- HSN summary --------------------------------------------------------
    b.writeln(_row(['HSN - Summary Of Outward Supplies']));
    b.writeln(_row([
      'HSN/SAC',
      'UQC',
      'Total Quantity',
      'Rate',
      'Taxable Value',
      'CGST',
      'SGST',
      'Total Tax',
    ]));
    for (final r in (report['hsn'] as List? ?? [])) {
      final m = Map<String, dynamic>.from(r as Map);
      b.writeln(_row([
        m['hsn'] ?? '',
        // UQC is not tracked per item; NOS (numbers) is the safe default for a
        // counter sale and is what the utility expects when unspecified.
        'NOS',
        _num(m['quantity']).toStringAsFixed(2),
        _num(m['rate']).toStringAsFixed(2),
        _money(m['taxable_value']),
        _money(m['cgst']),
        _money(m['sgst']),
        _money(m['total_tax']),
      ]));
    }

    // BOM + UTF-8 so Excel opens it in the right encoding.
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
  }

  /// A4 PDF of the same figures, for records and for handing to an accountant.
  static Future<Uint8List> buildPdf(Map<String, dynamic> report) async {
    final doc = pw.Document();
    final business = Map<String, dynamic>.from(report['business'] ?? {});
    final totals = Map<String, dynamic>.from(report['totals'] ?? {});
    final b2cs = (report['b2cs'] as List? ?? []);
    final hsn = (report['hsn'] as List? ?? []);

    final head = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    const cell = pw.TextStyle(fontSize: 9);

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 110, child: pw.Text(k, style: const pw.TextStyle(fontSize: 9))),
            pw.Text(v, style: head),
          ]),
        );

    pw.Widget cellText(String t, {bool bold = false, bool right = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(t,
              style: bold ? head : cell,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
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
            child: pw.Text('GSTR-1 SUMMARY',
                style:
                    pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 10),
          kv('Business', (business['name'] ?? '').toString()),
          kv('GSTIN', (business['gstin'] ?? '').toString()),
          kv('Period', '${report['from']}  to  ${report['to']}'),
          pw.SizedBox(height: 10),

          // Period totals
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _stat('Invoices', '${totals['bill_count'] ?? 0}'),
                _stat('Invoice Value', _money(totals['invoice_value'])),
                _stat('Taxable Value', _money(totals['taxable_value'])),
                _stat('CGST', _money(totals['cgst'])),
                _stat('SGST', _money(totals['sgst'])),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          pw.Text('B2CS — Consolidated B2C Supplies', style: head),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1.5),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  cellText('Rate %', bold: true),
                  cellText('Taxable Value', bold: true, right: true),
                  cellText('CGST', bold: true, right: true),
                  cellText('SGST', bold: true, right: true),
                  cellText('Total Tax', bold: true, right: true),
                ],
              ),
              for (final r in b2cs)
                pw.TableRow(children: [
                  cellText(_num((r as Map)['rate']).toStringAsFixed(2)),
                  cellText(_money(r['taxable_value']), right: true),
                  cellText(_money(r['cgst']), right: true),
                  cellText(_money(r['sgst']), right: true),
                  cellText(_money(r['total_tax']), right: true),
                ]),
              if (b2cs.isEmpty)
                pw.TableRow(children: [
                  cellText('—'),
                  cellText('—', right: true),
                  cellText('—', right: true),
                  cellText('—', right: true),
                  cellText('—', right: true),
                ]),
            ],
          ),
          pw.SizedBox(height: 14),

          pw.Text('HSN — Summary Of Outward Supplies', style: head),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.8),
              1: pw.FlexColumnWidth(0.8),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(1.6),
              5: pw.FlexColumnWidth(1.3),
              6: pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  cellText('HSN/SAC', bold: true),
                  cellText('UQC', bold: true),
                  cellText('Qty', bold: true, right: true),
                  cellText('Rate %', bold: true, right: true),
                  cellText('Taxable Value', bold: true, right: true),
                  cellText('CGST', bold: true, right: true),
                  cellText('SGST', bold: true, right: true),
                ],
              ),
              for (final r in hsn)
                pw.TableRow(children: [
                  cellText(((r as Map)['hsn'] ?? '').toString()),
                  cellText('NOS'),
                  cellText(_num(r['quantity']).toStringAsFixed(2), right: true),
                  cellText(_num(r['rate']).toStringAsFixed(2), right: true),
                  cellText(_money(r['taxable_value']), right: true),
                  cellText(_money(r['cgst']), right: true),
                  cellText(_money(r['sgst']), right: true),
                ]),
              if (hsn.isEmpty)
                pw.TableRow(children: [
                  cellText('—'),
                  cellText('—'),
                  cellText('—', right: true),
                  cellText('—', right: true),
                  cellText('—', right: true),
                  cellText('—', right: true),
                  cellText('—', right: true),
                ]),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'All supplies are reported as B2C (consolidated). Intra-state '
            'supply assumed: tax is split as CGST + SGST.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _stat(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      );
}
