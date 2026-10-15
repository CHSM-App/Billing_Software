import 'package:Vittam/l10n/app_localizations.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/providers/items_provider.dart';
import 'package:Vittam/screens/home_screen.dart';
import 'package:Vittam/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone cart sheet on the Billing page: a long order gets the same
/// "Scroll down" button as the side panel, jumping to the Settle row, and the
/// sheet's last row stays clear of the phone's gesture / 3-button bar.
void main() {
  // Opens HomeScreen on a draft of [lines] items, which opens the cart sheet
  // on a phone-sized screen with a [navInset] system bar at the bottom.
  Future<void> openSheet(WidgetTester tester, int lines,
      {double navInset = 0}) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: navInset);
    addTearDown(tester.view.reset);
    final bill = Bill(
      id: 'd1',
      businessId: 'b',
      billNumber: 'INV-1',
      subtotal: 0,
      taxAmount: 0,
      total: 0,
      paymentMode: 'cash',
      status: 'draft',
      createdByUserId: 'u',
      createdAt: DateTime(2026, 10, 15),
      items: [
        for (var i = 0; i < lines; i++)
          BillItem(
              id: 'l$i',
              billId: 'd1',
              itemId: 'it$i',
              itemName: 'Item $i',
              quantity: 1,
              unitPrice: 10,
              lineTotal: 10),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [itemsProvider.overrideWith(() => _Items(lines))],
      child: MaterialApp(
        theme: buildAppTheme('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
            activeBillId: 'd1',
            activeBillFuture: Future.value(bill),
            openCart: true),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(BottomSheet), findsOneWidget);
  }

  final button = find.byIcon(Icons.keyboard_double_arrow_down);
  double buttonOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find
          .ancestor(of: button, matching: find.byType(AnimatedOpacity))
          .first)
      .opacity;
  ScrollPosition sheetScroll(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
              of: find.byType(BottomSheet), matching: find.byType(Scrollable))
          .first)
      .position;

  testWidgets('long order: Scroll down shows, jumps to the end, then hides',
      (tester) async {
    await openSheet(tester, 25);
    expect(buttonOpacity(tester), 1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final pos = sheetScroll(tester);
    expect(pos.pixels, pos.maxScrollExtent);
    expect(buttonOpacity(tester), 0);
  });

  testWidgets('short order: no Scroll down button', (tester) async {
    await openSheet(tester, 2);
    expect(buttonOpacity(tester), 0);
  });

  testWidgets('last row clears the system navigation bar', (tester) async {
    await openSheet(tester, 25, navInset: 24);
    final scroll = tester.widget<SingleChildScrollView>(find
        .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(SingleChildScrollView))
        .first);
    expect(scroll.padding, const EdgeInsets.only(bottom: 24));
  });
}

class _Items extends ItemsNotifier {
  _Items(this.count);
  final int count;

  @override
  Future<List<Item>> build() async => [
        for (var i = 0; i < count; i++)
          Item(
              id: 'it$i',
              businessId: 'b',
              name: 'Item $i',
              price: 10,
              isActive: true),
      ];
}
