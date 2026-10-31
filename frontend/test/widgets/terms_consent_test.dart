import 'package:Vittam/l10n/app_localizations.dart';
import 'package:Vittam/widgets/terms_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late bool accepted;

  Future<void> pump(WidgetTester tester) {
    accepted = false;
    return tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TermsConsent(onChanged: (v) => accepted = v)),
    ));
  }

  bool? box(WidgetTester tester) =>
      tester.widget<Checkbox>(find.byType(Checkbox)).value;

  testWidgets('one checkbox, starting unticked', (tester) async {
    await pump(tester);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(box(tester), isFalse);
  });

  testWidgets('ticking it accepts; unticking takes it back', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(box(tester), isTrue);
    expect(accepted, isTrue);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(box(tester), isFalse);
    expect(accepted, isFalse);
  });

  testWidgets('the sentence names all three documents', (tester) async {
    await pump(tester);
    final text = tester.widget<RichText>(find.byType(RichText).last).text.toPlainText();
    expect(text, contains('Terms of Service'));
    expect(text, contains('Acceptable Use Policy'));
    expect(text, contains('Privacy Policy'));
  });
}
