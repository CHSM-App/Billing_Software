import 'dart:io';
import 'dart:ui' as ui;

import 'package:Vittam/theme/app_theme.dart';
import 'package:Vittam/widgets/category_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// DEV TOOL, not a test — run it by hand to LOOK at the billing screen's
/// major → sub-category tree instead of inferring the layout from the code:
///
///     flutter test test/widgets/category_tree_render.dart
///
/// It writes test/.render/category_tree.png. Nothing here asserts on pixels.
///
/// The filename deliberately lacks the `_test` suffix so `flutter test` does
/// NOT collect it: the run writes the PNG correctly and then hangs at teardown
/// until the 10-minute timeout, which would fail the whole suite. Passing the
/// path explicitly still runs it. The hang is somewhere in teardown after the
/// image is written — disabling GoogleFonts' runtime fetching (below) was
/// necessary but not sufficient, and it was not worth chasing further for a
/// tool whose artifact is already correct by the time it stalls.
///
/// Text renders in a fallback font, so glyphs and text widths are NOT what the
/// app shows — geometry, spacing, borders and radii are.
void main() {
  testWidgets('renders the category tree to a PNG for visual review',
      (tester) async {
    // AppFont.style goes through GoogleFonts, which tries to FETCH the font
    // over HTTP when it isn't bundled — in a test that blocks until the
    // 10-minute timeout kills the run. Off means it falls back to the default
    // font: glyphs differ from the real app, but every position and size here
    // is what ships.
    GoogleFonts.config.allowRuntimeFetching = false;

    // Tall enough that the WHOLE sample fits the viewport — a RepaintBoundary
    // only captures what is on screen, so anything below the fold silently
    // never makes it into the PNG.
    tester.view.physicalSize = const Size(720, 3400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final repaintKey = GlobalKey();

    // Two adjacent majors, each with the hue its position would give it, so
    // the render shows the colour actually changing from one block to the next.
    final bar = CategoryAccents.of(0);
    final bev = CategoryAccents.of(1);
    // A menu with no major level has nothing to derive a hue from, so it keeps
    // the app's default — matching _MajorSection.flat.
    const flat = AppColors.primary;

    // Mirrors the mockup: an open major with several shut sub-categories, one
    // open sub-category with item rows under it, then a second major.
    Widget sub(String name, int items, Color accent,
            {bool open = false, bool isLast = false, bool nested = true}) =>
        SubCategoryCard(
          label: name,
          countLabel: '$items items',
          open: open,
          nested: nested,
          isLast: isLast,
          onTap: () {},
          height: 46,
          railGutter: 11,
          accent: accent,
        );

    // [railed] false mirrors a business that never adopted major categories:
    // same box and inset, no tree line.
    Widget itemRow(String name, String price, Color accent,
            {bool isLast = false, bool railed = true}) =>
        SizedBox(
          height: 41,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (railed)
                  TreeRail(
                      width: 11, color: CategoryAccents.railTint(accent)),
                Expanded(
                  child: ItemRowFrame(
                    isLast: isLast,
                    accent: accent,
                    child: Column(
                      children: [
                Expanded(
              // Opaque background across the full width, exactly as the real
              // _ExcelItemRow paints. Without it the harness could not show
              // that a background-painted frame border gets covered up.
              child: ColoredBox(
                color: AppColors.surface,
                child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 10),
                child: Row(children: [
                  Expanded(
                      child: Text(name,
                          style: const TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 72,
                    child: Text(price,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.remove,
                              size: 16, color: AppColors.textSecondary),
                        ),
                        const Expanded(
                            child: Center(
                                child: Text('0',
                                    style: TextStyle(fontSize: 13)))),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.add,
                              size: 16, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              ),
            ),
                        // Cell rule inside the box: edge to edge, so it meets
                        // the side borders. Suppressed on the last row, where
                        // the frame's own bottom edge closes the box.
                        if (!isLast)
                          const Divider(
                              height: 1,
                              thickness: 1,
                              indent: 0,
                              endIndent: 0,
                              color: AppColors.border),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    final app = MaterialApp(
      theme: buildAppTheme('en'),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: RepaintBoundary(
          key: repaintKey,
          child: ListView(
            padding: const EdgeInsets.only(top: 8),
            children: [
              MajorCategoryCard(
                  label: 'Bar',
                  open: true,
                  onTap: () {},
                  height: 50,
                  accent: bar),
              sub('Beer', 8, bar),
              sub('Cocktails', 8, bar),
              sub('Gin & Brandy', 4, bar),
              sub('Rum', 3, bar),
              sub('Vodka', 3, bar, open: true),
              itemRow('Absolut', '₹200.00', bar),
              itemRow('Magic Moments', '₹170.00', bar),
              itemRow('Smirnoff', '₹200.00', bar, isLast: true),
              sub('Whisky', 9, bar),
              sub('Wine', 4, bar, isLast: true),
              MajorCategoryCard(
                  label: 'Beverages',
                  open: true,
                  onTap: () {},
                  height: 50,
                  accent: bev),
              sub('Mocktails', 5, bev),
              sub('Soft Drinks', 6, bev),
              sub('Tea & Coffee', 4, bev),
              sub('Water & Soda', 3, bev, isLast: true),

              // A business with NO major categories: no major card, no rail,
              // but the same cards, box and inset as everything above.
              const SizedBox(height: 24),
              sub('Snacks', 2, flat, nested: false),
              sub('Other', 2, flat, nested: false, open: true),
              itemRow('Banana Chips', '₹20.00', flat, railed: false),
              itemRow('Soyabean Oil Pack 1L', '₹220.00', flat,
                  railed: false, isLast: true),
              sub('Spices', 1, flat, nested: false),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app);
    // Explicit pumps, NOT pumpAndSettle: the cards animate their tint on an
    // AnimatedContainer that pumpAndSettle waits on forever here. Two frames
    // past the fold duration is enough for everything to reach its end state.
    await tester.pump();
    await tester.pump(CategoryTreeMotion.duration + const Duration(seconds: 1));

    // ONE capture per run. A second toImage after resizing the view never
    // returned — the run stalls there and the second PNG is never written — so
    // to check another width, change `physicalSize` above and run again rather
    // than trying to shoot twice.
    final boundary =
        repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('test/.render')..createSync(recursive: true);
    File('${dir.path}/category_tree.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());

    expect(find.text('Bar'), findsOneWidget);
    expect(find.text('Vodka'), findsOneWidget);
  });
}
