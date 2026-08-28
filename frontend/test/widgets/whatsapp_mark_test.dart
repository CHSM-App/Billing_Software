import 'package:Vittam/widgets/whatsapp_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mark is hand-authored path data, which fails silently: a stray control
/// point yields a blank, smeared or flooded glyph and no widget-tree assertion
/// notices. A golden pins the actual pixels.
///
/// `toImage()` is deliberately NOT used here — it needs a real GPU surface and
/// hangs forever under the headless test binding.
void main() {
  group('WhatsAppMark', () {
    testWidgets('renders the mark', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: WhatsAppMark(size: 96, color: Color(0xFF25D366)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(WhatsAppMark),
        matchesGoldenFile('goldens/whatsapp_mark.png'),
      );
    });

    testWidgets('honours size', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: WhatsAppMark(size: 32))),
      ));

      expect(tester.getSize(find.byType(WhatsAppMark)), const Size(32, 32));
    });

    testWidgets('defaults to the brand colour', (tester) async {
      expect(whatsAppGreen, const Color(0xFF25D366));

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: WhatsAppMark())),
      ));

      expect(tester.widget<WhatsAppMark>(find.byType(WhatsAppMark)).color,
          whatsAppGreen);
      expect(tester.takeException(), isNull);
    });
  });
}
