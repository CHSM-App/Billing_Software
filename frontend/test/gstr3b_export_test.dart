import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/services/gstr3b_export.dart';

/// One period's worth of server response, shaped exactly as
/// `GET /api/reports/gstr3b` returns it.
Map<String, dynamic> _report() => {
      'from': '2026-08-01',
      'to': '2026-08-31',
      'business': {'name': 'Vengurla Tech', 'gstin': '27ABCDE1234F1Z5', 'state': 'MH'},
      'table_3_1': {
        'taxable_value': 10000,
        'igst': 0,
        'cgst': 250.5,
        'sgst': 250.5,
        'cess': 0,
      },
      'table_4': {'igst': 40, 'cgst': 100, 'sgst': 100, 'cess': 0, 'total': 240},
      'table_6_1': {
        'liability': {'igst': 0, 'cgst': 250.5, 'sgst': 250.5, 'total': 501},
        'paid_through_itc': {'igst': 0, 'cgst': 120, 'sgst': 120, 'total': 240},
        'payable_in_cash': {'igst': 0, 'cgst': 130.5, 'sgst': 130.5, 'total': 261},
        'itc_balance_carried': 0,
      },
    };

String _csv(Map<String, dynamic> r) => utf8.decode(Gstr3bExport.buildCsv(r));

void main() {
  group('Gstr3bExport.buildCsv', () {
    test('writes the 6.1 figures the portal is filled from', () {
      final csv = _csv(_report());

      // Money is fixed to 2dp, never a bare int or a float artefact — these
      // are transcribed into a filing by hand.
      expect(csv, contains('Tax payable,0.00,250.50,250.50,501.00'));
      expect(csv, contains('Paid through ITC,0.00,120.00,120.00,240.00'));
      expect(csv, contains('Payable in cash,0.00,130.50,130.50,261.00'));
    });

    test('carries the identification a filing needs', () {
      final csv = _csv(_report());
      expect(csv, contains('27ABCDE1234F1Z5'));
      expect(csv, contains('2026-08-01'));
      expect(csv, contains('2026-08-31'));
    });

    test('starts with a UTF-8 BOM so Excel does not mangle the text', () {
      final bytes = Gstr3bExport.buildCsv(_report());
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    });

    test('quotes a field containing a comma instead of shifting columns', () {
      final r = _report();
      (r['business'] as Map)['name'] = 'Vengurla Tech, Sindhudurg';
      expect(_csv(r), contains('"Vengurla Tech, Sindhudurg"'));
    });

    test('missing tables export as 0.00 rather than throwing', () {
      // A nil period returns the same envelope with empty tables. The file must
      // still be produced — a crash here would look like "download is broken".
      final csv = _csv({'from': '2026-08-01', 'to': '2026-08-31'});
      expect(csv, contains('Payable in cash,0.00,0.00,0.00,0.00'));
    });

    test('names the tables it does not track, so a nil is never implied', () {
      expect(_csv(_report()), contains('Not tracked'));
    });
  });
}
