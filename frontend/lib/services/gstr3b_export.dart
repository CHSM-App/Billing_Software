import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the downloadable artefacts for the GSTR-3B summary return.
///
/// Mirrors [Gstr1Export] in shape and money rules — the figures come straight
/// from the server (`/api/reports/gstr3b`) and are never re-derived here, so a
/// downloaded file and the on-screen report can never disagree.
///
/// SCOPE NOTE: the app records no zero-rated, exempt or nil-rated supplies, no
/// imports, no ISD credit and no ITC reversals. Tables 3.1(b)–(e), 3.2, 4(B)
/// and 5 are therefore emitted as "not tracked" rather than as zeroes — a zero
/// in a filing reads as a checked nil, and none of these were ever checked.
class Gstr3bExport {
  /// Escape one CSV field: quote when it contains a comma, quote or newline,
  /// and double any embedded quotes.
  static String _csvField(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _row(List<Object?> cells) => cells.map(_csvField).join(',');

  static String _money(Object? v) => _num(v).toStringAsFixed(2);

  static double _num(Object? v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  static Map<String, dynamic> _map(Object? v) =>
      Map<String, dynamic>.from((v as Map?) ?? const {});

  /// CSV laid out in the numbered tables of the GSTR-3B portal form, so the
  /// figures can be transcribed cell by cell without re-deriving anything.
  ///
  /// Returned as UTF-8 **with a BOM** — Excel otherwise reads the file as the
  /// system codepage and mangles the rupee sign and any Devanagari text.
  static Uint8List buildCsv(Map<String, dynamic> report) {
    final b = StringBuffer();
    final business = _map(report['business']);
    final t31 = _map(report['table_3_1']);
    final t4 = _map(report['table_4']);
    final t61 = _map(report['table_6_1']);
    final liab = _map(t61['liability']);
    final viaItc = _map(t61['paid_through_itc']);
    final cash = _map(t61['payable_in_cash']);

    b.writeln(_row(['GSTR-3B Summary']));
    b.writeln(_row(['Business', business['name'] ?? '']));
    b.writeln(_row(['GSTIN', business['gstin'] ?? '']));
    b.writeln(_row(['State', business['state'] ?? '']));
    b.writeln(_row(['Period From', report['from'] ?? '']));
    b.writeln(_row(['Period To', report['to'] ?? '']));
    b.writeln();

    // --- 3.1(a) -------------------------------------------------------------
    b.writeln(_row(['3.1(a) Outward taxable supplies (other than zero rated)']));
    b.writeln(_row(['Taxable Value', 'IGST', 'CGST', 'SGST', 'Cess']));
    b.writeln(_row([
      _money(t31['taxable_value']),
      _money(t31['igst']),
      _money(t31['cgst']),
      _money(t31['sgst']),
      _money(t31['cess']),
    ]));
    b.writeln();

    // --- 4(A)(5) ------------------------------------------------------------
    b.writeln(_row(['4(A)(5) Eligible ITC — All other ITC']));
    b.writeln(_row(['IGST', 'CGST', 'SGST', 'Cess', 'Total']));
    b.writeln(_row([
      _money(t4['igst']),
      _money(t4['cgst']),
      _money(t4['sgst']),
      _money(t4['cess']),
      _money(t4['total']),
    ]));
    b.writeln();

    // --- 6.1 ----------------------------------------------------------------
    b.writeln(_row(['6.1 Payment of tax']));
    b.writeln(_row(['', 'IGST', 'CGST', 'SGST', 'Total']));
    for (final e in [
      ('Tax payable', liab),
      ('Paid through ITC', viaItc),
      ('Payable in cash', cash),
    ]) {
      b.writeln(_row([
        e.$1,
        _money(e.$2['igst']),
        _money(e.$2['cgst']),
        _money(e.$2['sgst']),
        _money(e.$2['total']),
      ]));
    }
    b.writeln();
    b.writeln(_row(
        ['ITC balance carried forward', _money(t61['itc_balance_carried'])]));
    b.writeln();

    // --- Not tracked --------------------------------------------------------
    // Spelled out rather than omitted: a filer reading only this file must not
    // assume the missing tables were checked and found nil.
    b.writeln(_row(['Not tracked by this app — enter on the portal if they apply']));
    b.writeln(_row([
      '3.1(b)-(e), 3.2, 4(B), 5: zero-rated, exempt and nil-rated supplies, '
          'imports, ISD credit and ITC reversals'
    ]));

    return Uint8List.fromList(utf8.encode('﻿$b'));
  }

  static Future<Uint8List> buildPdf(Map<String, dynamic> report) async {
    final doc = pw.Document();
    final business = _map(report['business']);
    final t31 = _map(report['table_3_1']);
    final t4 = _map(report['table_4']);
    final t61 = _map(report['table_6_1']);
    final liab = _map(t61['liability']);
    final viaItc = _map(t61['paid_through_itc']);
    final cash = _map(t61['payable_in_cash']);

    final head = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    const cell = pw.TextStyle(fontSize: 9);

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 110,
                child: pw.Text(k, style: const pw.TextStyle(fontSize: 9))),
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

    /// A numbered-table block: caption, header row, then body rows. Every
    /// column but the first is money and reads right-aligned.
    pw.Widget table(String caption, List<String> headers,
            List<List<String>> rows) =>
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(caption, style: head),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey600),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  for (var i = 0; i < headers.length; i++)
                    cellText(headers[i], bold: true, right: i > 0),
                ],
              ),
              for (final r in rows)
                pw.TableRow(children: [
                  for (var i = 0; i < r.length; i++)
                    cellText(r[i], right: i > 0),
                ]),
            ],
          ),
        ]);

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
            child: pw.Text('GSTR-3B SUMMARY',
                style:
                    pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 10),
          kv('Business', (business['name'] ?? '').toString()),
          kv('GSTIN', (business['gstin'] ?? '').toString()),
          kv('Period', '${report['from']}  to  ${report['to']}'),
          pw.SizedBox(height: 10),

          // The headline figure — what actually has to be paid this month.
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _stat('Tax Payable', _money(liab['total'])),
                _stat('Paid via ITC', _money(viaItc['total'])),
                _stat('Payable in Cash', _money(cash['total'])),
                _stat('ITC Carried', _money(t61['itc_balance_carried'])),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          table(
            '3.1(a)  Outward taxable supplies (other than zero rated)',
            ['Taxable Value', 'IGST', 'CGST', 'SGST', 'Cess'],
            [
              [
                _money(t31['taxable_value']),
                _money(t31['igst']),
                _money(t31['cgst']),
                _money(t31['sgst']),
                _money(t31['cess']),
              ]
            ],
          ),
          pw.SizedBox(height: 14),

          table(
            '4(A)(5)  Eligible ITC — All other ITC',
            ['IGST', 'CGST', 'SGST', 'Cess', 'Total'],
            [
              [
                _money(t4['igst']),
                _money(t4['cgst']),
                _money(t4['sgst']),
                _money(t4['cess']),
                _money(t4['total']),
              ]
            ],
          ),
          pw.SizedBox(height: 14),

          table(
            '6.1  Payment of tax',
            ['', 'IGST', 'CGST', 'SGST', 'Total'],
            [
              for (final e in [
                ('Tax payable', liab),
                ('Paid through ITC', viaItc),
                ('Payable in cash', cash),
              ])
                [
                  e.$1,
                  _money(e.$2['igst']),
                  _money(e.$2['cgst']),
                  _money(e.$2['sgst']),
                  _money(e.$2['total']),
                ]
            ],
          ),
          pw.SizedBox(height: 14),

          pw.Text(
            'Not tracked by this app: zero-rated, exempt and nil-rated '
            'supplies, imports, ISD credit and ITC reversals. Tables '
            '3.1(b)-(e), 3.2, 4(B) and 5 are left blank rather than filled '
            'with zeroes — enter them on the portal if they apply to you. '
            'Intra-state supply is assumed, so outward tax splits CGST + SGST.',
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
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      );
}
