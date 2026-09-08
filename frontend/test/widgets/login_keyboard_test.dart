import 'package:Vittam/l10n/app_localizations.dart';
import 'package:Vittam/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The PIN field must end up ABOVE the on-screen keyboard.
///
/// It did not: the login Scaffold set `resizeToAvoidBottomInset: false`, so the
/// body kept full height and the form's scroll viewport still ran to the bottom
/// of the screen — behind the keyboard. Flutter measures "is the focused field
/// visible?" against that viewport, decided it already was, and never scrolled,
/// leaving the field unreachable under the keys.
///
/// Guarded here because nothing about it is visible to the analyzer, and it
/// only reproduces with a keyboard actually taking up part of the screen.
void main() {
  const keyboardHeight = 300.0;

  Future<void> pumpLogin(WidgetTester tester,
      {required double bottomInset}) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            // Stands in for the keyboard being up.
            data: MediaQueryData(
              size: const Size(390, 844),
              viewInsets: EdgeInsets.only(bottom: bottomInset),
            ),
            child: const LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the PIN field scrolls clear of the keyboard when focused',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpLogin(tester, bottomInset: keyboardHeight);

    // Two text fields on this form: phone, then PIN.
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.tap(fields.at(1));
    await tester.pumpAndSettle();

    final pinBottom = tester.getRect(fields.at(1)).bottom;
    expect(
      pinBottom,
      lessThanOrEqualTo(844 - keyboardHeight),
      reason: 'the PIN field is under the keyboard — the form did not scroll',
    );
  });
}
