import 'package:Vittam/theme/app_theme.dart';
import 'package:Vittam/widgets/bottom_nav_bar.dart';
import 'package:Vittam/widgets/nav_item.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The floating glass bar: taps still route to the right tab, the blur is
/// really there, and the red badge count still shows.
void main() {
  testWidgets('taps select a tab; blur and badge render', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme('en'),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AppBottomNavBar(
            items: const [
              NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
                  'Billing', SizedBox()),
              NavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Items',
                  SizedBox(),
                  badge: 3),
              NavItem(Icons.person_outline, Icons.person, 'Profile',
                  SizedBox()),
            ],
            selectedIndex: 0,
            onDestinationSelected: tapped.add,
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Items'));
    expect(tapped, [1]);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('dragging the highlight selects the tab under the thumb',
      (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 300,
            child: AppBottomNavBar(
              items: const [
                NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
                    'Billing', SizedBox()),
                NavItem(Icons.inventory_2_outlined, Icons.inventory_2,
                    'Items', SizedBox()),
                NavItem(Icons.person_outline, Icons.person, 'Profile',
                    SizedBox()),
              ],
              selectedIndex: 0,
              onDestinationSelected: picked.add,
            ),
          ),
        ),
      ),
    ));

    final haptics = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    Rect pill() => tester.getRect(find.byKey(const ValueKey('navHighlight')));
    final rest = pill();

    // Thumb lands on Billing and slides all the way across to Profile, in
    // small steps the way a real finger reports them.
    final g = await tester.startGesture(tester.getCenter(find.text('Billing')));
    for (var i = 0; i < 11; i++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    // Held under the thumb it is the big clear lens, spilling past the bar.
    await tester.pump(const Duration(milliseconds: 200));
    expect(pill().height, greaterThan(rest.height + 8));
    await g.up();
    await tester.pumpAndSettle();
    expect(picked, [2]);
    expect(pill().height, closeTo(rest.height, 0.5)); // shrinks on release
    // A tick per tab crossed (Items, Profile), then a bump for the pick.
    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  // iOS: the glass lens rides on the moving pill. Android: no lens (it lagged
  // on low-powered phones) but the pill still slides, stretches and settles,
  // and the bar still breathes.
  testWidgets('highlight swells while sliding (lens on iOS only), settles',
      (tester) async {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    Widget bar(int sel) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 308, // 300 inside the 4px padding → 100 per slot
                child: AppBottomNavBar(
                  items: const [
                    NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
                        'Billing', SizedBox()),
                    NavItem(Icons.inventory_2_outlined, Icons.inventory_2,
                        'Items', SizedBox()),
                    NavItem(Icons.person_outline, Icons.person, 'Profile',
                        SizedBox()),
                  ],
                  selectedIndex: sel,
                  onDestinationSelected: (_) {},
                ),
              ),
            ),
          ),
        );
    Rect pill() => tester.getRect(find.byKey(const ValueKey('navHighlight')));

    await tester.pumpWidget(bar(0));
    final rest = pill();
    Rect glass() => tester.getRect(find.byType(BackdropFilter));
    final restBar = glass();
    await tester.pumpWidget(bar(2));
    await tester.pump(const Duration(milliseconds: 60));
    final moving = pill();
    // Swollen: wider, and taller than the capsule (spills past its edges).
    expect(moving.width, greaterThan(rest.width));
    expect(moving.height, greaterThan(rest.height + 8));
    // A real magnifying lens rides on top while it moves, on iOS only.
    expect(find.byType(RawMagnifier), ios ? findsOneWidget : findsNothing);
    // The whole bar breathes a little bigger with it.
    expect(glass().width, greaterThan(restBar.width + 3));
    await tester.pumpAndSettle();
    // Back to a plain slot, two slots over.
    expect(pill().width, closeTo(rest.width, 0.5));
    expect(pill().height, closeTo(rest.height, 0.5));
    expect(pill().left, closeTo(rest.left + 2 * rest.width, 0.5));
    expect(glass(), restBar);
    expect(find.byType(RawMagnifier), findsNothing); // gone at rest
  },
      variant: const TargetPlatformVariant(
          {TargetPlatform.iOS, TargetPlatform.android}));

  testWidgets('pressing the selected tab squishes the lens, release settles it',
      (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AppBottomNavBar(
            items: const [
              NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
                  'Billing', SizedBox()),
              NavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Items',
                  SizedBox()),
            ],
            selectedIndex: 0,
            onDestinationSelected: picked.add,
          ),
        ),
      ),
    ));
    Rect pill() => tester.getRect(find.byKey(const ValueKey('navHighlight')));
    final rest = pill();

    final g = await tester.startGesture(tester.getCenter(find.text('Billing')));
    await tester.pump(); // first frame starts the animation's clock
    await tester.pump(const Duration(milliseconds: 200));
    // A subtle swell: bigger than at rest, well short of the full drag lens.
    expect(pill().height, greaterThan(rest.height + 4));
    expect(pill().height, lessThan(rest.height + 12));
    await g.up();
    await tester.pumpAndSettle();
    expect(pill().size, rest.size);
    expect(picked, [0]); // the tap still went through
  });

  testWidgets('a plain tap mid-slide still selects only the tapped tab',
      (tester) async {
    final picked = <int>[];
    Widget bar(int sel) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: AppBottomNavBar(
                items: const [
                  NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
                      'Billing', SizedBox()),
                  NavItem(Icons.inventory_2_outlined, Icons.inventory_2,
                      'Items', SizedBox()),
                  NavItem(Icons.person_outline, Icons.person, 'Profile',
                      SizedBox()),
                ],
                selectedIndex: sel,
                onDestinationSelected: picked.add,
              ),
            ),
          ),
        );
    await tester.pumpWidget(bar(0));
    await tester.pumpWidget(bar(2)); // highlight starts sliding to Profile
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Items')); // quick second tap mid-slide
    await tester.pumpAndSettle();
    expect(picked, [1]);
  });

  // Phone widths from the smallest supported (320) to just under the shell's
  // 720px rail cutoff; every tab count the shell can build (2 for kitchen,
  // up to 5 for a restaurant owner); normal and largest accessibility text;
  // Android and iOS with their own safe areas and pixel densities. The bar
  // must never overflow, keep 48px+ touch targets and its 56px height, and
  // lay out identically on both platforms.
  testWidgets('responsive: widths, tab counts, text scale, iOS == Android',
      (tester) async {
    addTearDown(tester.view.reset);
    const all = [
      NavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Billing',
          SizedBox()),
      NavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Items',
          SizedBox(),
          badge: 12),
      NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
          'Orders', SizedBox(),
          badge: 108),
      NavItem(Icons.restaurant_menu_outlined, Icons.restaurant_menu, 'Kitchen',
          SizedBox(),
          badge: 3),
      NavItem(Icons.person_outline, Icons.person, 'Profile', SizedBox()),
    ];
    final platforms = {
      // platform: (pixel ratio, bottom safe area)
      TargetPlatform.android: (2.625, 24.0), // gesture-nav inset
      TargetPlatform.iOS: (3.0, 34.0), // home indicator
    };
    for (final width in [320.0, 360.0, 393.0, 412.0, 430.0, 719.0]) {
      for (final count in [2, 4, 5]) {
        for (final scale in [1.0, 2.0]) {
          final rects = <TargetPlatform, Rect>{};
          for (final MapEntry(key: platform, value: (dpr, inset))
              in platforms.entries) {
            tester.view.devicePixelRatio = dpr;
            tester.view.physicalSize = Size(width, 800) * dpr;
            tester.view.padding = FakeViewPadding(bottom: inset * dpr);
            await tester.pumpWidget(MaterialApp(
              theme: ThemeData(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              // Wrapped the way MainShell._buildBottomNav wraps it.
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: AppBottomNavBar(
                          items: all.take(count).toList(),
                          selectedIndex: count - 1,
                          onDestinationSelected: (_) {},
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ));
            final where = '$platform w=$width tabs=$count text=$scale';
            expect(tester.takeException(), isNull, reason: where);
            final bar = tester.getRect(find.byType(BackdropFilter));
            expect(bar.height, AppBottomNavBar.height, reason: where);
            expect(bar.left, greaterThanOrEqualTo(16), reason: where);
            expect(bar.right, lessThanOrEqualTo(width - 16), reason: where);
            // Clear of the home indicator / gesture bar.
            expect(bar.bottom, lessThanOrEqualTo(800 - inset - 8),
                reason: where);
            // Each tab is a touch target of at least 48x48.
            expect((bar.width - 8) / count, greaterThanOrEqualTo(48),
                reason: where);
            rects[platform] = bar;
          }
          final a = rects[TargetPlatform.android]!;
          final i = rects[TargetPlatform.iOS]!;
          // Same width and height; iOS sits 10px higher only because its
          // home-indicator inset is 34 vs 24.
          expect(i.size, a.size, reason: 'w=$width tabs=$count text=$scale');
          expect(a.top - i.top, closeTo(10, 0.01));
        }
      }
    }
  });
}
