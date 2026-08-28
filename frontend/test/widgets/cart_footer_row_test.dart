import 'package:Vittam/theme/app_theme.dart';
import 'package:Vittam/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cart panel is a cross-axis-STRETCHED column, so its children get an
/// unbounded horizontal slot unless something pins them. The outlined-button
/// theme sets `minimumSize: Size(double.infinity, 52)`, which turns any
/// unbounded slot into an infinite width demand — and that blanks the whole
/// panel, not just the button. These tests run against the real theme.
Widget _panel(Widget footer) => MaterialApp(
      theme: buildAppTheme('en'),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            const Spacer(),
            Padding(padding: const EdgeInsets.all(16), child: footer),
          ],
        ),
      ),
    );

Widget _iconAction({VoidCallback? onPressed, String caption = 'Hold'}) =>
    IconAction(
      icon: Icons.pause_circle_outline,
      caption: caption,
      color: AppColors.warning,
      onPressed: onPressed ?? () {},
    );

Widget _settle({
  VoidCallback? onPressed,
  VoidCallback? onLongPress,
  String outcome = 'and print',
}) =>
    SettleButton(
      amountLabel: 'Settle Rs.150.00',
      outcomeLabel: outcome,
      onPressed: onPressed ?? () {},
      onLongPress: onLongPress,
    );

Widget _fullRow({VoidCallback? onLongPress}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iconAction(),
        const SizedBox(width: 8),
        _iconAction(caption: 'Settle'),
        const SizedBox(width: 8),
        Expanded(child: _settle(onLongPress: onLongPress)),
      ],
    );

void main() {
  group('cart footer action row', () {
    testWidgets('lays out in a stretched unbounded column', (tester) async {
      await tester.pumpWidget(_panel(_fullRow()));

      expect(tester.takeException(), isNull);
      expect(find.text('Settle Rs.150.00'), findsOneWidget);
      expect(find.text('and print'), findsOneWidget);
      // Both icon captions render; 'Settle' appears on the tile AND inside the
      // main button's amount label, hence the tile caption is found separately.
      expect(find.text('Hold'), findsOneWidget);
    });

    testWidgets('IconAction stays square despite the infinite-width theme',
        (tester) async {
      await tester.pumpWidget(_panel(_fullRow()));

      final size = tester.getSize(find.byType(OutlinedButton).first);
      expect(size.width, 56, reason: 'the theme would stretch it otherwise');
      expect(size.height, 56);
    });

    testWidgets('the outcome caption tracks the printer', (tester) async {
      await tester.pumpWidget(_panel(_settle(outcome: 'no receipt')));
      expect(find.text('no receipt'), findsOneWidget);
      expect(find.text('and print'), findsNothing);
    });

    testWidgets('long press settles without a receipt', (tester) async {
      var taps = 0, longs = 0;
      await tester.pumpWidget(_panel(_settle(
        onPressed: () => taps++,
        onLongPress: () => longs++,
      )));

      await tester.tap(find.byType(SettleButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(longs, 0);

      await tester.longPress(find.byType(SettleButton));
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'a long press must not also fire the tap');
      expect(longs, 1);
    });

    testWidgets('a disabled settle button ignores both gestures',
        (tester) async {
      var longs = 0;
      await tester.pumpWidget(_panel(SettleButton(
        amountLabel: 'Settle Rs.0.00',
        outcomeLabel: 'and print',
        onPressed: null,
        onLongPress: () => longs++,
      )));

      await tester.longPress(find.byType(SettleButton));
      await tester.pumpAndSettle();
      expect(longs, 0, reason: 'an empty cart must not settle');
    });

    testWidgets('captain sees only a full-width park button', (tester) async {
      await tester.pumpWidget(_panel(Row(children: [
        Expanded(
          child: SecondaryButton(
              text: 'Save Order',
              icon: Icons.pause_circle_outline,
              onPressed: () {}),
        ),
      ])));

      expect(tester.takeException(), isNull);
      expect(find.text('Save Order'), findsOneWidget);
      expect(find.byType(SettleButton), findsNothing);
    });
  });
}
