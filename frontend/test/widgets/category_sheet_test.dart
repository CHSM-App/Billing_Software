import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/widgets/category_sheet.dart';

/// Fixed-size boxes stand in for chips so the row maths is exact.
Widget _box(int i, {double width = 100}) => SizedBox(
      key: ValueKey('box$i'),
      width: width,
      height: 30,
      child: Text('$i'),
    );

Future<void> _pumpFlow(WidgetTester tester, List<Widget> children,
    {double viewportWidth = 400}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: TwoRowChipFlow(
            viewportWidth: viewportWidth,
            horizontalGap: 10,
            verticalGap: 6,
            children: children,
          ),
        ),
      ),
    ),
  ));
}

Rect _rect(WidgetTester tester, int i) =>
    tester.getRect(find.byKey(ValueKey('box$i')));

void main() {
  group('TwoRowChipFlow', () {
    testWidgets('keeps one row while everything fits, stretched edge to edge',
        (tester) async {
      // 3 × 100 + 2 × 10 = 320 ≤ 400 → one row; the 80 px left over is
      // shared out so the row spans the full 400 (each chip 126.67 wide).
      await _pumpFlow(tester, [for (var i = 0; i < 3; i++) _box(i)]);
      final flow = tester.getSize(find.byType(TwoRowChipFlow));
      expect(flow, const Size(400, 30));
      for (var i = 0; i < 3; i++) {
        final r = _rect(tester, i);
        expect(r.top, 0);
        expect(r.width, closeTo(400 / 3 - 20 / 3, 0.01));
        expect(r.left, closeTo(i * (r.width + 10), 0.01));
      }
      expect(_rect(tester, 2).right, closeTo(400, 0.01));
    });

    testWidgets('fills a two-row grid column by column when one row overflows',
        (tester) async {
      // 6 × 100 + 5 × 10 = 650 > 400 → 3 columns of 2 (320 wide) stretched
      // to the full 400.
      await _pumpFlow(tester, [for (var i = 0; i < 6; i++) _box(i)]);
      final flow = tester.getSize(find.byType(TwoRowChipFlow));
      expect(flow, const Size(400, 66)); // 30 + 6 + 30
      final colWidth = (400 - 2 * 10) / 3;
      for (var i = 0; i < 6; i++) {
        final r = _rect(tester, i);
        expect(r.top, i.isEven ? 0 : 36);
        expect(r.width, closeTo(colWidth, 0.01));
        expect(r.left, closeTo((i ~/ 2) * (colWidth + 10), 0.01));
      }
      expect(_rect(tester, 5).right, closeTo(400, 0.01));
    });

    testWidgets('does not stretch when the viewport width is unbounded',
        (tester) async {
      await _pumpFlow(tester, [for (var i = 0; i < 3; i++) _box(i)],
          viewportWidth: double.infinity);
      expect(tester.getSize(find.byType(TwoRowChipFlow)), const Size(320, 30));
    });

    testWidgets('never uses more than two rows, overflowing sideways instead',
        (tester) async {
      // 20 × 100 + 19 × 10 = 2090 → 10 columns of 2 (1090 wide) that scroll.
      await _pumpFlow(tester, [for (var i = 0; i < 20; i++) _box(i)]);
      final flow = tester.getSize(find.byType(TwoRowChipFlow));
      expect(flow, const Size(1090, 66));
      expect(_rect(tester, 18).top, 0);
      expect(_rect(tester, 18).left, 990);
      expect(_rect(tester, 19).top, 36);
      expect(_rect(tester, 19).left, 990);
    });

    testWidgets('stretches both chips of a column to the wider one',
        (tester) async {
      // Widths 300, 100 | 100, 100 | 100 (total 730 > 400): column 1 is 300
      // wide and chip 1 is widened to fill it, so the gap after it is the
      // same 10 px as everywhere else; the odd chip sits on top.
      await _pumpFlow(tester, [
        _box(0, width: 300),
        _box(1),
        _box(2),
        _box(3),
        _box(4),
      ]);
      expect(tester.getSize(find.byType(TwoRowChipFlow)), const Size(520, 66));
      expect(_rect(tester, 0), const Rect.fromLTWH(0, 0, 300, 30));
      expect(_rect(tester, 1), const Rect.fromLTWH(0, 36, 300, 30));
      expect(_rect(tester, 2), const Rect.fromLTWH(310, 0, 100, 30));
      expect(_rect(tester, 3), const Rect.fromLTWH(310, 36, 100, 30));
      expect(_rect(tester, 4), const Rect.fromLTWH(420, 0, 100, 30));
    });

    testWidgets('a single oversized child still lays out on one row',
        (tester) async {
      await _pumpFlow(tester, [_box(0, width: 900)]);
      expect(tester.getSize(find.byType(TwoRowChipFlow)), const Size(900, 30));
    });

    testWidgets('renders nothing without children', (tester) async {
      await _pumpFlow(tester, const []);
      expect(tester.getSize(find.byType(TwoRowChipFlow)), Size.zero);
    });
  });

  group('CategoryChipStrip', () {
    testWidgets('lights the active chip and reports taps', (tester) async {
      String? tapped;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CategoryChipStrip(
                categories: const ['Tea', 'Snacks', ''],
                active: 'Snacks',
                labelOf: (c) => c.isEmpty ? 'Other' : c,
                onTap: (c) => tapped = c,
                controller: controller,
                chipKeys: {},
              ),
            ],
          ),
        ),
      ));

      expect(find.text('Other'), findsOneWidget);
      final snacks =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Snacks'));
      final tea =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Tea'));
      expect(snacks.selected, isTrue);
      expect(tea.selected, isFalse);

      await tester.tap(find.text('Tea'));
      expect(tapped, 'Tea');
    });

    testWidgets('grows to two rows when the categories overflow the width',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget strip(List<String> cats) => MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 300,
                    child: CategoryChipStrip(
                      categories: cats,
                      active: '',
                      labelOf: (c) => c,
                      onTap: (_) {},
                      controller: controller,
                      chipKeys: {},
                    ),
                  ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(strip(const ['A', 'B']));
      final oneRow = tester.getSize(find.byType(CategoryChipStrip)).height;

      await tester.pumpWidget(strip([
        for (var i = 0; i < 12; i++) 'Category number $i',
      ]));
      final twoRows = tester.getSize(find.byType(CategoryChipStrip)).height;
      expect(twoRows, greaterThan(oneRow));
      // Both rows scroll together: the strip's single horizontal scrollable
      // is wider than its viewport.
      expect(controller.position.maxScrollExtent, greaterThan(0));

      // Still exactly two rows: chips sit on only two distinct y positions.
      final rects = [
        for (final e in find.byType(FilterChip).evaluate())
          tester.getRect(find.byWidget(e.widget))
      ];
      expect({for (final r in rects) r.top.round()}.length, 2);

      // Chips sharing a column are the same width (the narrower one is
      // stretched), so every gap in the grid is identical.
      final byColumn = <int, List<Rect>>{};
      for (final r in rects) {
        byColumn.putIfAbsent(r.left.round(), () => []).add(r);
      }
      expect(byColumn.length, (rects.length + 1) ~/ 2);
      for (final column in byColumn.values) {
        expect(column.map((r) => r.width.round()).toSet().length, 1);
      }
      // …and the stretched chip still centres its label.
      final first = rects.first;
      final firstLabel = tester.getRect(find.text('Category number 0'));
      expect(firstLabel.center.dx, closeTo(first.center.dx, 1));
    });

    testWidgets('spans the screen edge to edge when it does not scroll',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 360,
                child: CategoryChipStrip(
                  categories: const ['Tea', 'Snacks', 'Meals', 'Drinks'],
                  active: '',
                  labelOf: (c) => c,
                  onTap: (_) {},
                  controller: controller,
                  chipKeys: {},
                ),
              ),
            ],
          ),
        ),
      ));
      final chips = [
        for (final e in find.byType(FilterChip).evaluate())
          tester.getRect(find.byWidget(e.widget))
      ];
      // 12 px inset on both sides, matching the sheet's rows; the chips fill
      // everything in between.
      final stripLeft = tester.getRect(find.byType(CategoryChipStrip)).left;
      expect(chips.map((r) => r.left).reduce(math.min), stripLeft + 12);
      expect(chips.map((r) => r.right).reduce(math.max),
          closeTo(stripLeft + 360 - 12, 0.01));
      expect(controller.position.maxScrollExtent, 0);
    });
  });
}
