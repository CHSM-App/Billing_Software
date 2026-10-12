import 'dart:io';

import 'package:Vittam/models/models.dart';
import 'package:Vittam/services/printer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The /credit/settle reply's `settlement`, as the backend sends it.
final _json = {
  'id': '11111111-2222-3333-4444-555555555555',
  'receipt_token': 'Ab3xK9Ab3xK9Ab3x',
  'created_at': '2026-10-12T11:05:00.000Z',
  'mode': 'cash',
  'total': 2920,
  'customer_name': 'Ramesh Patil',
  'customer_phone': '9876543210',
  'lines': [
    {'bill_number': 'INV-0099', 'bill_date': '2026-10-02T10:00:00.000Z',
     'bill_total': 1420, 'paid': 1420, 'due': 0},
    {'bill_number': 'INV-0098', 'bill_date': '2026-09-28T10:00:00.000Z',
     'bill_total': 950, 'paid': 950, 'due': 0},
    // Part-paid: still owes 250 after this payment. Strings, as mssql may send.
    {'bill_number': 'INV-0097', 'bill_date': '2026-09-21T10:00:00.000Z',
     'bill_total': '800.00', 'paid': '550.00', 'due': '250.00'},
  ],
};

void main() {
  test('CreditSettlement.fromJson reads every line, a part-paid one owing', () {
    final s = CreditSettlement.fromJson(_json);
    expect(s.total, 2920);
    expect(s.lines, hasLength(3));
    expect(s.lines.first.displayNumber, '0099');
    final part = s.lines.last;
    expect([part.billTotal, part.paid, part.due], [800, 550, 250]);
    expect(s.lines.where((l) => l.due > 0), hasLength(1));
  });

  // Renders the thermal Payment Receipt at both roll widths. Asserts only that
  // it renders; the PNGs land in build/ for a human to look at.
  testWidgets('thermal Payment Receipt renders at 80mm and 58mm', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final s = CreditSettlement.fromJson(_json);
    for (final dots in [576, 384]) {
      final png = await tester.runAsync(() => PrinterService.instance
          .buildSettlementPreviewPng(s,
              businessName: 'Hotel Ramtirth',
              businessAddress: 'Market Road, Kudal 416520',
              businessPhone: '9763535333',
              paperDots: dots));
      expect(png, isNotNull);
      expect(png!.length, greaterThan(1000));
      final out = File('build/settlement_receipt_$dots.png');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(png);
    }
  });
}
