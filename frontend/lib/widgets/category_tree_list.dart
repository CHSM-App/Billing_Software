import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'category_sheet.dart';

// ponytail: this is a copy of the billing screen's major → category tree
// (home_screen.dart _ExcelItemTable + its jump/scroll-spy logic), minus the
// cart and the in-place size rows. Only the Items page uses it for now; once
// the billing WIP lands, billing should switch to this file and drop its copy.

/// One category's items in the tree.
class TreeSection {
  /// Raw category string; empty for items with no category ("Other").
  final String category;

  /// Major this section sits under; null when the menu has no major level.
  /// The same category can appear under several majors, so [key] — not
  /// [category] — identifies a section.
  final String? major;
  final List<Item> items;
  final bool expanded;
  final Color accent;

  const TreeSection(this.category, this.items,
      {required this.expanded, this.major, this.accent = AppColors.primary});

  String get key => sectionKey(major, category);

  /// Unique across the tree even when two majors share a category name.
  static String sectionKey(String? major, String category) =>
      major == null ? category : '$major\u0000$category';
}

/// One major and its sections. A menu without majors is one [TreeMajor.flat]:
/// no bar of its own, always open.
class TreeMajor {
  /// Null for the flat case; '' is the "Other" bucket for items with no major.
  final String? major;
  final List<TreeSection> subs;
  final bool expanded;
  final Color accent;

  const TreeMajor(this.major, this.subs,
      {required this.expanded, this.accent = AppColors.primary});
  const TreeMajor.flat(this.subs)
      : major = null,
        expanded = true,
        accent = AppColors.primary;

  int get itemCount => subs.fold(0, (n, s) => n + s.items.length);
}

/// Where one section's card and rows sit, in list-local scroll offsets.
class TreeSpan {
  final String key;
  final double start;
  final double end;
  final bool expanded;
  const TreeSpan(this.key, this.start, this.end, this.expanded);
}

/// The billing-style item list: major cards, sub-category cards hung off a
/// tree rail, and item rows boxed inside their open category. Every entry has
/// a fixed extent so jumps and the scroll-spy are exact arithmetic.
class CategoryTreeList extends StatefulWidget {
  final List<TreeMajor> tree;
  final ScrollController controller;
  final bool twoColumns;
  final void Function(String major) onToggleMajor;
  final void Function(String sectionKey) onToggleSection;

  /// One item cell; [number] is its running position in the whole list.
  final Widget Function(Item item, int number) itemBuilder;

  const CategoryTreeList({
    super.key,
    required this.tree,
    required this.controller,
    required this.twoColumns,
    required this.onToggleMajor,
    required this.onToggleSection,
    required this.itemBuilder,
  });

  // Same extents as the billing table.
  static const double sectionHeaderExtent = 46;
  static const double majorHeaderExtent = 50;
  static const double rowExtent = 41; // 40 row + 1 divider
  // Room for a floating action button over the last rows.
  static const double bottomPadding = 96;
  static const double railGutter = 11;

  static int _cols(bool twoColumns) => twoColumns ? 2 : 1;

  static int _rowsIn(TreeSection s, bool twoColumns) {
    if (!s.expanded) return 0;
    final c = _cols(twoColumns);
    return (s.items.length + c - 1) ~/ c;
  }

  static double _sectionHeight(TreeSection s, bool twoColumns) =>
      sectionHeaderExtent + _rowsIn(s, twoColumns) * rowExtent;

  /// Span of every section currently in the list. Sections under a folded
  /// major are not in the list, so they are absent here too.
  static List<TreeSpan> sectionSpans(List<TreeMajor> tree, bool twoColumns) {
    final out = <TreeSpan>[];
    var offset = 0.0;
    for (final m in tree) {
      if (m.major != null) offset += majorHeaderExtent;
      if (!m.expanded) continue;
      for (final s in m.subs) {
        final start = offset;
        offset += _sectionHeight(s, twoColumns);
        out.add(TreeSpan(s.key, start, offset, s.expanded));
      }
    }
    return out;
  }

  /// Which major's block contains [offset]; null for a flat menu.
  static String? majorAtOffset(
      List<TreeMajor> tree, double offset, bool twoColumns) {
    String? current;
    var y = 0.0;
    for (final m in tree) {
      if (m.major == null) continue;
      if (y > offset) break;
      current = m.major;
      y += majorHeaderExtent;
      if (!m.expanded) continue;
      for (final s in m.subs) {
        y += _sectionHeight(s, twoColumns);
      }
    }
    return current;
  }

  /// Offset that puts [major]'s card at the top, or null if it is not listed.
  static double? majorOffset(
      List<TreeMajor> tree, String major, bool twoColumns) {
    var offset = 0.0;
    for (final m in tree) {
      if (m.major == major) return offset;
      if (m.major != null) offset += majorHeaderExtent;
      if (!m.expanded) continue;
      for (final s in m.subs) {
        offset += _sectionHeight(s, twoColumns);
      }
    }
    return null;
  }

  /// maxScrollExtent once every fold animation has settled.
  static double settledMaxScroll(List<TreeMajor> tree, bool twoColumns,
      {required double viewportHeight}) {
    var h = 0.0;
    for (final m in tree) {
      if (m.major != null) h += majorHeaderExtent;
      if (!m.expanded) continue;
      for (final s in m.subs) {
        h += _sectionHeight(s, twoColumns);
      }
    }
    return (h + bottomPadding - viewportHeight).clamp(0.0, double.infinity);
  }

  @override
  State<CategoryTreeList> createState() => _CategoryTreeListState();
}

/// A list entry: a major card, a section card, or one row of item cells.
class _Entry {
  final TreeMajor? major;
  final TreeSection? section;
  final bool isLastSub;
  final List<Item> items;
  final int firstNumber;
  final bool isLastRow;
  final Color accent;

  const _Entry.major(TreeMajor this.major)
      : section = null,
        isLastSub = false,
        items = const [],
        firstNumber = 0,
        isLastRow = false,
        accent = AppColors.primary;
  const _Entry.section(TreeSection this.section, {required this.isLastSub})
      : major = null,
        items = const [],
        firstNumber = 0,
        isLastRow = false,
        accent = AppColors.primary;
  const _Entry.row(this.items, this.firstNumber,
      {required this.isLastRow, required this.accent})
      : major = null,
        section = null,
        isLastSub = false;
}

/// One group's fold animation, eased the same way in both directions.
class _Fold {
  final AnimationController _ctrl;
  late final CurvedAnimation _eased;

  _Fold(TickerProvider vsync,
      {required bool open, required VoidCallback onTick})
      : _ctrl = AnimationController(
          vsync: vsync,
          duration: CategoryTreeMotion.duration,
          value: open ? 1 : 0,
        ) {
    _eased = CurvedAnimation(
      parent: _ctrl,
      curve: CategoryTreeMotion.curve,
      reverseCurve: CategoryTreeMotion.curve,
    );
    _ctrl.addListener(onTick);
  }

  double get value => _eased.value;
  void animateTo({required bool open}) =>
      open ? _ctrl.forward() : _ctrl.reverse();
  void dispose() {
    _eased.dispose();
    _ctrl.dispose();
  }
}

class _CategoryTreeListState extends State<CategoryTreeList>
    with TickerProviderStateMixin {
  final Map<String, _Fold> _majorFold = {};
  final Map<String, _Fold> _sectionFold = {};

  static Set<String> _openMajors(List<TreeMajor> tree) => {
        for (final m in tree)
          if (m.major != null && m.expanded) m.major!
      };

  static Set<String> _openSections(List<TreeMajor> tree) => {
        for (final m in tree)
          for (final s in m.subs)
            if (s.expanded) s.key,
      };

  @override
  void didUpdateWidget(CategoryTreeList old) {
    super.didUpdateWidget(old);
    _diff(_majorFold, _openMajors(old.tree), _openMajors(widget.tree));
    _diff(_sectionFold, _openSections(old.tree), _openSections(widget.tree));
  }

  void _diff(Map<String, _Fold> folds, Set<String> was, Set<String> now) {
    for (final key in {...was, ...now}) {
      final open = now.contains(key);
      if (was.contains(key) == open) continue;
      folds
          .putIfAbsent(key,
              () => _Fold(this, open: !open, onTick: () => setState(() {})))
          .animateTo(open: open);
    }
  }

  double _progress(Map<String, _Fold> folds, String key, bool open) =>
      folds[key]?.value ?? (open ? 1 : 0);

  @override
  void dispose() {
    for (final f in [..._majorFold.values, ..._sectionFold.values]) {
      f.dispose();
    }
    super.dispose();
  }

  /// Entries to show now, each with its current (possibly mid-fold) extent.
  /// Numbers follow the final state so they never shift mid-animation.
  List<(_Entry, double)> _entries() {
    final out = <(_Entry, double)>[];
    final cols = CategoryTreeList._cols(widget.twoColumns);
    var number = 1;
    for (final m in widget.tree) {
      if (m.major != null) {
        out.add((_Entry.major(m), CategoryTreeList.majorHeaderExtent));
      }
      final mp =
          m.major == null ? 1.0 : _progress(_majorFold, m.major!, m.expanded);
      if (mp <= 0) {
        number += m.itemCount;
        continue;
      }
      for (final s in m.subs) {
        out.add((
          _Entry.section(s, isLastSub: m.subs.last.key == s.key),
          CategoryTreeList.sectionHeaderExtent * mp,
        ));
        final sp = mp * _progress(_sectionFold, s.key, s.expanded);
        if (sp > 0) {
          for (var i = 0; i < s.items.length; i += cols) {
            final end = (i + cols).clamp(0, s.items.length);
            out.add((
              _Entry.row(s.items.sublist(i, end), number + i,
                  isLastRow: end == s.items.length, accent: s.accent),
              CategoryTreeList.rowExtent * sp,
            ));
          }
        }
        number += s.items.length;
      }
    }
    return out;
  }

  /// Squash + fade a partially open entry around its own centre.
  Widget _folded(Widget child, double extent, double full) {
    if (extent >= full) return child;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        minHeight: full,
        maxHeight: full,
        child: Opacity(opacity: (extent / full).clamp(0.0, 1.0), child: child),
      ),
    );
  }

  String _label(String raw) =>
      raw.isEmpty ? context.l10n.billingCategoryOther : raw;

  Widget _entry(_Entry e, double extent) {
    if (e.major != null) {
      final m = e.major!;
      return MajorCategoryCard(
        label: _label(m.major!),
        open: m.expanded,
        onTap: () => widget.onToggleMajor(m.major!),
        height: CategoryTreeList.majorHeaderExtent,
        accent: m.accent,
      );
    }
    if (e.section != null) {
      final s = e.section!;
      return _folded(
        SubCategoryCard(
          label: _label(s.category),
          countLabel: context.l10n.billingCategoryItemCount(s.items.length),
          open: s.expanded,
          nested: s.major != null,
          isLast: e.isLastSub,
          onTap: () => widget.onToggleSection(s.key),
          height: CategoryTreeList.sectionHeaderExtent,
          railGutter: CategoryTreeList.railGutter,
          accent: s.accent,
        ),
        extent,
        CategoryTreeList.sectionHeaderExtent,
      );
    }

    final cells = [
      for (var i = 0; i < e.items.length; i++)
        widget.itemBuilder(e.items[i], e.firstNumber + i),
    ];
    final row = !widget.twoColumns
        ? cells.first
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cells.first),
              Container(width: 1, color: AppColors.border),
              Expanded(child: cells.length > 1 ? cells[1] : const SizedBox()),
            ],
          );
    final framed = ItemRowFrame(
      isLast: e.isLastRow,
      accent: e.accent,
      child: Column(children: [
        Expanded(child: row),
        // The frame's own bottom edge closes the last row.
        if (!e.isLastRow)
          const Divider(height: 1, thickness: 1, color: AppColors.border),
      ]),
    );
    // Only a menu with majors has the tree rail running past the rows.
    final railed = widget.tree.isNotEmpty && widget.tree.first.major != null;
    return _folded(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: railed
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TreeRail(
                      width: CategoryTreeList.railGutter,
                      color: CategoryAccents.railTint(e.accent)),
                  Expanded(child: framed),
                ],
              )
            : framed,
      ),
      extent,
      CategoryTreeList.rowExtent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return CustomScrollView(
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding:
              const EdgeInsets.only(bottom: CategoryTreeList.bottomPadding),
          sliver: SliverVariedExtentList(
            itemExtentBuilder: (i, _) =>
                i >= entries.length ? null : entries[i].$2,
            delegate: SliverChildBuilderDelegate(
              (_, i) => _entry(entries[i].$1, entries[i].$2),
              childCount: entries.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// Open/closed state, chip strips and scroll-spy for a [CategoryTreeList] —
/// the billing screen's behaviour:
/// * with majors: every major starts open and folds independently; inside
///   them one category is open at a time; a major chip strip on top jumps to
///   a major (opening it if folded) and follows manual scrolling;
/// * without majors: every category starts open and folds independently, and
///   a category chip strip jumps to them;
/// * the very first category is spread open on first load; a search opens
///   every matching section.
///
/// Call [initTreeNav] in initState, [disposeTreeNav] in dispose, [buildTree]
/// in build, and give the list [treeScrollCtrl].
mixin CategoryTreeNav<T extends StatefulWidget> on State<T> {
  final ScrollController treeScrollCtrl = ScrollController();
  final ValueNotifier<String?> _activeMajor = ValueNotifier(null);
  final ValueNotifier<String?> _activeCategory = ValueNotifier(null);
  final ScrollController _majorStripCtrl = ScrollController();
  final ScrollController _catStripCtrl = ScrollController();
  final Map<String, GlobalKey> _majorChipKeys = {};
  final Map<String, GlobalKey> _catChipKeys = {};

  // Majors are tracked as FOLDED (all open by default); with majors, only one
  // category is open; without majors, categories are tracked as folded.
  final Set<String> _collapsedMajors = {};
  final Set<String> _expandedCategories = {};
  final Set<String> _collapsedCategories = {};

  List<TreeMajor> _tree = const [];
  bool _twoColumns = false;
  bool _jumping = false;
  bool _autoOpenedFirst = false;

  bool get _flatMenu => _tree.isEmpty || _tree.first.major == null;

  void initTreeNav() => treeScrollCtrl.addListener(_syncToScroll);

  void disposeTreeNav() {
    treeScrollCtrl.dispose();
    _activeMajor.dispose();
    _activeCategory.dispose();
    _majorStripCtrl.dispose();
    _catStripCtrl.dispose();
  }

  List<TreeSection> _groupByCategory(List<Item> items, List<String> cats,
      String? major, bool searching, Color accent) {
    final byCat = <String, List<Item>>{};
    for (final item in items) {
      byCat.putIfAbsent(item.category?.trim() ?? '', () => []).add(item);
    }
    final ordered = <String>[
      ...cats.where(byCat.containsKey),
      ...byCat.keys.where((c) => c.isNotEmpty && !cats.contains(c)),
      if (byCat.containsKey('')) '',
    ];
    return [
      for (final cat in ordered)
        TreeSection(
          cat,
          byCat[cat]!,
          major: major,
          accent: accent,
          expanded: searching ||
              (major == null
                  ? !_collapsedCategories.contains(cat)
                  : _expandedCategories
                      .contains(TreeSection.sectionKey(major, cat))),
        ),
    ];
  }

  List<TreeMajor> _group(List<Item> items, List<String> cats,
      List<String> majors, bool searching) {
    if (majors.isEmpty) {
      return [
        TreeMajor.flat(
            _groupByCategory(items, cats, null, searching, AppColors.primary))
      ];
    }
    final byMajor = <String, List<Item>>{};
    for (final item in items) {
      byMajor.putIfAbsent(item.majorCategory?.trim() ?? '', () => []).add(item);
    }
    final ordered = <String>[
      ...majors.where(byMajor.containsKey),
      ...byMajor.keys.where((m) => m.isNotEmpty && !majors.contains(m)),
      if (byMajor.containsKey('')) '',
    ];
    return [
      for (final (i, m) in ordered.indexed)
        TreeMajor(
          m,
          _groupByCategory(
              byMajor[m]!, cats, m, searching, CategoryAccents.of(i)),
          expanded: searching || !_collapsedMajors.contains(m),
          accent: CategoryAccents.of(i),
        ),
    ];
  }

  /// Groups [items] for the list and remembers the result for jumps and the
  /// scroll-spy. [majors] in display order; empty for a menu without majors.
  List<TreeMajor> buildTree(
      List<Item> items, List<String> cats, List<String> majors,
      {required bool searching, required bool twoColumns}) {
    // The lit major can disappear (its last item deleted or re-filed).
    final lit = _activeMajor.value;
    if (lit != null && !majors.contains(lit)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _activeMajor.value = null;
      });
    }

    var tree = _group(items, cats, majors, searching);

    // First load: spread the first category open (majors are open already).
    final first = tree.where((m) => m.subs.isNotEmpty).firstOrNull;
    if (!_autoOpenedFirst && first != null && !searching) {
      _autoOpenedFirst = true;
      final key = first.subs.first.key;
      _expandedCategories
        ..clear()
        ..add(key);
      tree = _group(items, cats, majors, searching);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setActiveCategory(key);
      });
    }

    List<String?> keys(List<TreeMajor> t) => [
          for (final m in t) ...[m.major, for (final s in m.subs) s.key]
        ];
    final now = keys(tree), was = keys(_tree);
    final changed = now.length != was.length ||
        Iterable.generate(now.length).any((k) => now[k] != was[k]);
    _tree = tree;
    _twoColumns = twoColumns;
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToScroll());
    }
    return tree;
  }

  /// Make sure [category] (under [major]) is open — e.g. after saving an item
  /// so the owner sees its row rather than a folded card.
  void revealSection(String? major, String category) {
    final m = (major ?? '').trim();
    final hasMajors = !_flatMenu;
    final key = TreeSection.sectionKey(hasMajors ? m : null, category.trim());
    setState(() {
      if (hasMajors) _collapsedMajors.remove(m);
      _collapsedCategories.remove(key);
      _expandedCategories
        ..clear()
        ..add(key);
    });
  }

  /// Major card tap: fold it shut, or open it and scroll it to the top.
  Future<void> toggleMajor(String major) async {
    final wasOpen = !_collapsedMajors.contains(major);
    setState(() =>
        wasOpen ? _collapsedMajors.add(major) : _collapsedMajors.remove(major));
    _activeMajor.value = wasOpen ? null : major;
    if (wasOpen) return;
    _revealChip(_majorStripCtrl, _majorChipKeys, major);
    await _nextFrame();
    if (!mounted) return;
    final offset = CategoryTreeList.majorOffset(_tree, major, _twoColumns);
    if (offset != null) await _animateTo(offset);
  }

  /// Major chip tap: go TO that major (open it if folded); never folds it.
  Future<void> _jumpToMajor(String major) async {
    final wasCollapsed = _collapsedMajors.contains(major);
    if (wasCollapsed) setState(() => _collapsedMajors.remove(major));
    _activeMajor.value = major;
    _revealChip(_majorStripCtrl, _majorChipKeys, major);
    if (wasCollapsed) {
      await _nextFrame();
      if (!mounted) return;
    }
    final offset = CategoryTreeList.majorOffset(_tree, major, _twoColumns);
    if (offset != null) await _animateTo(offset);
  }

  /// Category card tap. With majors only one category is open at a time;
  /// without majors each folds independently.
  void toggleCategory(String key) {
    final flat = _flatMenu;
    final wasOpen = flat
        ? !_collapsedCategories.contains(key)
        : _expandedCategories.contains(key);
    setState(() {
      if (flat) {
        wasOpen
            ? _collapsedCategories.add(key)
            : _collapsedCategories.remove(key);
      } else {
        _expandedCategories.clear();
        if (!wasOpen) _expandedCategories.add(key);
      }
    });
    if (wasOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToScroll());
    } else {
      _setActiveCategory(key);
    }
  }

  /// Category chip tap (menus without majors): open it if folded, scroll to it.
  Future<void> _jumpToCategory(String key) async {
    if (_collapsedCategories.contains(key)) {
      setState(() => _collapsedCategories.remove(key));
      await _nextFrame();
      if (!mounted) return;
    }
    final spans = CategoryTreeList.sectionSpans(_tree, _twoColumns);
    final k = spans.indexWhere((s) => s.key == key);
    if (k < 0) return;
    _setActiveCategory(key);
    await _animateTo(spans[k].start);
  }

  /// The one strip above the list: majors when the menu has them, otherwise
  /// the categories on screen (all categories when a search matches nothing).
  Widget? buildTreeStrip(List<String> majors, List<String> allCats) {
    final l10n = context.l10n;
    String label(String c) => c.isEmpty ? l10n.billingCategoryOther : c;
    if (majors.isNotEmpty) {
      return ValueListenableBuilder<String?>(
        valueListenable: _activeMajor,
        builder: (_, active, __) => CategoryChipStrip(
          categories: majors,
          active: active,
          labelOf: label,
          onTap: _jumpToMajor,
          controller: _majorStripCtrl,
          chipKeys: _majorChipKeys,
        ),
      );
    }
    final subs = _tree.isEmpty ? const <TreeSection>[] : _tree.first.subs;
    final cats = subs.isNotEmpty ? [for (final s in subs) s.category] : allCats;
    if (cats.isEmpty) return null;
    return ValueListenableBuilder<String?>(
      valueListenable: _activeCategory,
      builder: (_, active, __) => CategoryChipStrip(
        categories: cats,
        active: active,
        labelOf: label,
        onTap: _jumpToCategory,
        controller: _catStripCtrl,
        chipKeys: _catChipKeys,
      ),
    );
  }

  Future<void> _nextFrame() {
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => done.complete());
    return done.future;
  }

  Future<void> _animateTo(double offset) async {
    if (!treeScrollCtrl.hasClients) return;
    final pos = treeScrollCtrl.position;
    // Rows just opened are still unfolding, so clamp to the settled extent.
    final settled = CategoryTreeList.settledMaxScroll(_tree, _twoColumns,
        viewportHeight: pos.viewportDimension);
    final target = offset.clamp(
        0.0, settled > pos.maxScrollExtent ? settled : pos.maxScrollExtent);
    _jumping = true;
    try {
      await treeScrollCtrl.animateTo(target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    } finally {
      _jumping = false;
    }
  }

  /// The open section while any of it is on screen, else the one at the top.
  String? _categoryAt(double offset, double viewport) {
    final spans = CategoryTreeList.sectionSpans(_tree, _twoColumns);
    if (spans.isEmpty || !spans.any((s) => s.expanded)) return null;
    final bottom = offset + viewport;
    for (final s in spans) {
      if (s.expanded && s.start < bottom && s.end > offset) return s.key;
    }
    var active = spans.first.key;
    for (var k = 1; k < spans.length && spans[k].start <= offset + 1; k++) {
      active = spans[k].key;
    }
    return active;
  }

  /// Scroll-spy: keep the strips pointing at what is on screen. Skipped while
  /// a jump drives the list, so the lit chip doesn't flicker through majors.
  void _syncToScroll() {
    if (!mounted || _jumping || _tree.isEmpty || !treeScrollCtrl.hasClients) {
      return;
    }
    final pos = treeScrollCtrl.position;
    _setActiveCategory(_categoryAt(pos.pixels, pos.viewportDimension));
    final major =
        CategoryTreeList.majorAtOffset(_tree, pos.pixels, _twoColumns);
    if (major != null && major != _activeMajor.value) {
      _activeMajor.value = major;
      _revealChip(_majorStripCtrl, _majorChipKeys, major);
    }
  }

  void _setActiveCategory(String? key) {
    if (_activeCategory.value == key) return;
    _activeCategory.value = key;
    if (key != null) _revealChip(_catStripCtrl, _catChipKeys, key);
  }

  /// Centre a chip in its strip.
  void _revealChip(
      ScrollController ctrl, Map<String, GlobalKey> keys, String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ctrl.hasClients) return;
      final ctx = keys[key]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    });
  }
}
