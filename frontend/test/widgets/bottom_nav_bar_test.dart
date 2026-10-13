import 'package:Vittam/theme/app_theme.dart';
import 'package:Vittam/widgets/bottom_nav_bar.dart';
import 'package:Vittam/widgets/nav_item.dart';
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

    // Thumb lands on Billing and slides all the way across to Profile, in
    // small steps the way a real finger reports them.
    final g = await tester.startGesture(tester.getCenter(find.text('Billing')));
    for (var i = 0; i < 11; i++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(picked, [2]);
    // A tick per tab crossed (Items, Profile), then a bump for the pick.
    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);
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
}
