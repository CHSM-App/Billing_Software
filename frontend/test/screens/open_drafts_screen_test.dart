import 'package:Vittam/l10n/app_localizations.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/providers.dart';
import 'package:Vittam/providers/open_drafts_provider.dart';
import 'package:Vittam/screens/open_drafts_screen.dart';
import 'package:Vittam/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Bill _draft(String id, DateTime at, List<String?> statuses) => Bill(
      id: id,
      businessId: 'biz',
      billNumber: 'INV-$id',
      customerName: 'Guest $id',
      subtotal: 0,
      taxAmount: 0,
      total: 0,
      paymentMode: 'cash',
      status: 'draft',
      createdByUserId: 'u',
      createdAt: at,
      items: [
        for (var i = 0; i < statuses.length; i++)
          BillItem(
            id: '$id-$i',
            billId: id,
            itemName: 'Dish $i',
            quantity: 1,
            unitPrice: 0,
            lineTotal: 0,
            kitchenStatus: statuses[i],
          ),
      ],
    );

void main() {
  final drafts = [
    _draft('new', DateTime(2026, 10, 14, 18), ['ready', 'pending']),
    _draft('old', DateTime(2026, 10, 14, 9), ['delivered', null]),
    _draft('mid', DateTime(2026, 10, 14, 12), ['ready']),
  ];

  test('oldest order first, numbered from 1', () {
    final t = OpenDraftsScreen.tickets(drafts, '', false);
    expect(t.map((x) => x.bill.id), ['old', 'mid', 'new']);
    expect(t.map((x) => x.seq), [1, 2, 3]);
  });

  test('ready filter keeps only ready dishes and their queue numbers', () {
    final t = OpenDraftsScreen.tickets(drafts, '', true);
    expect(t.map((x) => x.bill.id), ['mid', 'new']);
    expect(t.map((x) => x.seq), [2, 3]);
    expect(t.last.items.map((i) => i.id), ['new-0']);
  });

  test('search still filters', () {
    expect(OpenDraftsScreen.tickets(drafts, 'guest mid', false).single.seq, 2);
  });

  // Phone: unfolding one bill folds the one that was open. Wide screens keep
  // every card open side by side, each folding on its own.
  group('unfolding bills', () {
    Future<void> pump(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          openDraftsProvider.overrideWith(() => _FakeDrafts(drafts)),
          userRoleProvider.overrideWithValue('owner'),
        ],
        child: MaterialApp(
          theme: buildAppTheme('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OpenDraftsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    // 'old' has Dish 0 + Dish 1, 'mid' has only Dish 0: so Dish 1 on screen
    // means 'old' is unfolded.
    testWidgets('phone: only one bill open at a time', (tester) async {
      await pump(tester, 390);
      expect(find.text('Dish 0'), findsNothing); // all folded to start

      await tester.tap(find.text('Guest old'));
      await tester.pumpAndSettle();
      expect(find.text('Dish 1'), findsOneWidget); // old open

      await tester.tap(find.text('Guest mid'));
      await tester.pumpAndSettle();
      expect(find.text('Dish 1'), findsNothing); // old folded by itself
      expect(find.text('Dish 0'), findsOneWidget); // only mid's dish

      await tester.tap(find.text('Guest mid'));
      await tester.pumpAndSettle();
      expect(find.text('Dish 0'), findsNothing); // tapping it again folds it
    });

    testWidgets('wide: cards open together and fold independently',
        (tester) async {
      await pump(tester, 1600);
      expect(find.text('Dish 1'), findsNWidgets(2)); // old and new both open
      await tester.tap(find.text('Guest old'));
      await tester.pumpAndSettle();
      expect(find.text('Dish 1'), findsOneWidget); // only old folded
    });
  });
}

class _FakeDrafts extends OpenDraftsNotifier {
  _FakeDrafts(this.drafts);
  final List<Bill> drafts;

  @override
  Future<List<Bill>> build() async => drafts;
}
