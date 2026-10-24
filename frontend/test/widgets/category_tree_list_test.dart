import 'package:Vittam/l10n/app_localizations.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/widgets/category_tree_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Item _item(String name, {String? major, String? cat}) => Item(
    id: name,
    businessId: 'b',
    name: name,
    majorCategory: major,
    category: cat,
    price: 10,
    isActive: true);

/// Minimal host for the mixin: strip on top, tree list below.
class _Host extends StatefulWidget {
  final List<Item> items;
  final List<String> majors;
  const _Host(this.items, this.majors);
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with CategoryTreeNav<_Host> {
  @override
  void initState() {
    super.initState();
    initTreeNav();
  }

  @override
  void dispose() {
    disposeTreeNav();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats =
        widget.items.map((i) => i.category).whereType<String>().toSet().toList()..sort();
    final tree = buildTree(widget.items, cats, widget.majors,
        searching: false, twoColumns: false);
    final strip = buildTreeStrip(widget.majors, cats);
    return Column(children: [
      if (strip != null) strip,
      Expanded(
        child: CategoryTreeList(
          tree: tree,
          controller: treeScrollCtrl,
          twoColumns: false,
          onToggleMajor: toggleMajor,
          onToggleSection: toggleCategory,
          itemBuilder: (item, n) => Text('row:${item.name}'),
        ),
      ),
    ]);
  }
}

Future<void> _pump(WidgetTester tester, List<Item> items, List<String> majors) =>
    tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _Host(items, majors)),
    ));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final withMajors = [
    _item('Paneer Tikka', major: 'Veg', cat: 'Starters'),
    _item('Dal', major: 'Veg', cat: 'Mains'),
    _item('Chicken 65', major: 'NonVeg', cat: 'Fry'),
  ];

  testWidgets('majors: strip + cards, first category auto-opened, one open',
      (tester) async {
    await _pump(tester, withMajors, ['Veg', 'NonVeg']);
    await tester.pumpAndSettle();

    // Major chips in the strip AND major cards in the list.
    expect(find.text('Veg'), findsNWidgets(2));
    expect(find.text('NonVeg'), findsNWidgets(2));
    // First category under the first major is open; the rest are folded.
    expect(find.text('row:Dal'), findsOneWidget); // "Mains" sorts first
    expect(find.text('row:Paneer Tikka'), findsNothing);
    expect(find.text('row:Chicken 65'), findsNothing);

    // Opening another category folds the open one (one at a time).
    await tester.tap(find.text('Starters'));
    await tester.pumpAndSettle();
    expect(find.text('row:Paneer Tikka'), findsOneWidget);
    expect(find.text('row:Dal'), findsNothing);

    // Tapping a major card folds its whole block.
    await tester.tap(find.text('Veg').last);
    await tester.pumpAndSettle();
    expect(find.text('Starters'), findsNothing);
    expect(find.text('Fry'), findsOneWidget); // other major still open

    // Its strip chip opens it again (jump never folds).
    await tester.tap(find.text('Veg').first);
    await tester.pumpAndSettle();
    expect(find.text('Starters'), findsOneWidget);
  });

  testWidgets('no majors: every category open, category chip strip',
      (tester) async {
    await _pump(tester, [
      _item('Rice', cat: 'Grocery'),
      _item('Soap', cat: 'Personal'),
    ], const []);
    await tester.pumpAndSettle();
    expect(find.text('row:Rice'), findsOneWidget);
    expect(find.text('row:Soap'), findsOneWidget);
    // Category name appears as a chip and as its card.
    expect(find.text('Grocery'), findsNWidgets(2));
  });

  // A business that never set a category: just the items, no "Other".
  testWidgets('no categories at all: plain rows, no Other card or strip',
      (tester) async {
    await _pump(tester, [_item('Tea'), _item('Coffee')], const []);
    await tester.pumpAndSettle();
    expect(find.text('row:Tea'), findsOneWidget);
    expect(find.text('row:Coffee'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('one category set: the rest still go under Other',
      (tester) async {
    await _pump(
        tester, [_item('Tea', cat: 'Drinks'), _item('Samosa')], const []);
    await tester.pumpAndSettle();
    expect(find.text('Drinks'), findsNWidgets(2)); // chip + card
    expect(find.text('Other'), findsNWidgets(2));
  });

  test('a headerless section adds no header height', () {
    const s = TreeSection('', [], expanded: true, headerless: true);
    const next = TreeMajor('Veg', [], expanded: true);
    expect(
        CategoryTreeList.majorOffset(
            [const TreeMajor.flat([s]), next], 'Veg', false),
        0);
  });

  test('majorOffset sums the extents above the major', () {
    const s = TreeSection('Starters', [], expanded: false, major: 'Veg');
    final tree = [
      const TreeMajor('Veg', [s], expanded: true),
      const TreeMajor('NonVeg', [], expanded: true),
    ];
    expect(CategoryTreeList.majorOffset(tree, 'Veg', false), 0);
    expect(
        CategoryTreeList.majorOffset(tree, 'NonVeg', false),
        CategoryTreeList.majorHeaderExtent +
            CategoryTreeList.sectionHeaderExtent);
  });
}
