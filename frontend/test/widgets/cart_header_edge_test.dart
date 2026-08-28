import 'package:Vittam/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cart header ends in two icon actions that must sit flush against the
/// row's right edge.
///
/// The trap this guards: a `Flexible` title and a `Spacer` compete for the same
/// slack, and the Flexible wins — leaving the trailing icons stranded in the
/// middle of the row no matter what the padding says. The fix is one Expanded
/// around title+count and NO Spacer.
Widget _header({required bool withSpacerBug}) {
  const tile = SizedBox(width: 36, height: 36);
  final title = Text('Order',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700));

  return MaterialApp(
    theme: buildAppTheme('en'),
    home: Scaffold(
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 0, 8),
          child: Row(key: const Key('row'), children: [
            Container(width: 36, height: 36, color: AppColors.primary),
            const SizedBox(width: 12),
            if (withSpacerBug) ...[
              Flexible(child: title),
              const Spacer(),
            ] else
              Expanded(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: title),
                ]),
              ),
            const ColoredBox(color: Colors.blue, child: tile),
            const SizedBox(width: 6),
            const ColoredBox(
                key: Key('delete'), color: Colors.red, child: tile),
          ]),
        ),
      ]),
    ),
  );
}

double _gap(WidgetTester tester) {
  final row = tester.getRect(find.byKey(const Key('row')));
  final del = tester.getRect(find.byKey(const Key('delete')));
  return row.right - del.right;
}

void main() {
  group('cart header trailing icons', () {
    testWidgets('sit flush against the right edge', (tester) async {
      await tester.pumpWidget(_header(withSpacerBug: false));
      await tester.pumpAndSettle();

      expect(_gap(tester), 0,
          reason: 'the delete icon must touch the row edge');
    });

    testWidgets('Flexible + Spacer strands them (regression)', (tester) async {
      await tester.pumpWidget(_header(withSpacerBug: true));
      await tester.pumpAndSettle();

      // Documents WHY the layout is shaped the way it is. If this ever reads 0,
      // Flutter changed how Flexible and Spacer share slack and the Expanded
      // wrapper above is no longer load-bearing.
      expect(_gap(tester), greaterThan(0));
    });
  });
}
