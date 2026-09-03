import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_theme.dart';

/// Building blocks for a "category-wise sheet": one continuous list of rows
/// grouped under tappable category bars, with a chip jump-list sitting above
/// it. The billing screen draws its item table this way; the Items page uses
/// these pieces so both screens read the same.
///
/// Every row has a fixed extent so a chip tap can compute its scroll target
/// exactly (and a scroll-spy can invert it) without measuring anything.
class CategorySheetMetrics {
  static const double columnHeaderHeight = 29; // 28 header + 1 divider
  static const double sectionBarExtent = 40;
  static const double rowExtent = 41; // 40 row + 1 divider
}

/// Keeps a header of fixed [height] pinned at the top of a CustomScrollView.
class PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(PinnedHeaderDelegate old) =>
      old.height != height || old.child != child;
}

/// Category jump-list. Chips fill one row while they fit the width; when
/// there are more they form a neat two-row grid (never more rows) whose
/// columns line up, and if even two rows overflow the whole block scrolls
/// sideways as one sheet.
///
/// Tapping a chip calls [onTap]; the chip whose category equals [active] is
/// filled, and none is filled when [active] is null. [chipKeys] lets the owner
/// scroll a chip into view with `Scrollable.ensureVisible`. The strip sizes
/// itself to its rows, so place it above the list rather than inside a
/// fixed-height header.
///
/// [active] is nullable rather than "" for no-selection: the uncategorised
/// section's key IS the empty string, so "" would light up its "Other" chip.
class CategoryChipStrip extends StatelessWidget {
  final List<String> categories;
  final String? active;
  final String Function(String category) labelOf;
  final void Function(String category) onTap;
  final ScrollController controller;
  final Map<String, GlobalKey> chipKeys;

  const CategoryChipStrip({
    super.key,
    required this.categories,
    required this.active,
    required this.labelOf,
    required this.onTap,
    required this.controller,
    required this.chipKeys,
  });

  /// Same side inset as the sheet's column header and rows beneath it.
  static const double _hPad = AppSpacing.space12;
  static const double _vPad = 6;
  static const double _chipGap = AppSpacing.space8;
  static const double _rowGap = 6;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: LayoutBuilder(builder: (context, constraints) {
        // The flow sits inside a horizontal scroll view (unbounded width), so
        // hand it the real viewport width to decide how many rows it needs.
        final viewport = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - 2 * _hPad)
            : double.infinity;
        return SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const ClampingScrollPhysics(),
          padding:
              const EdgeInsets.symmetric(horizontal: _hPad, vertical: _vPad),
          child: TwoRowChipFlow(
            viewportWidth: viewport,
            horizontalGap: _chipGap,
            verticalGap: _rowGap,
            children: [for (final cat in categories) _chip(cat)],
          ),
        );
      }),
    );
  }

  Widget _chip(String cat) {
    final selected = active == cat;
    return FilterChip(
      key: chipKeys.putIfAbsent(cat, GlobalKey.new),
      // Center shrink-wraps under the flow's unbounded measuring pass but
      // expands when the flow widens the chip to its grid column, so the
      // chip fills the column with its name centred.
      label: Center(child: Text(labelOf(cat))),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(cat),
      backgroundColor: AppColors.surfaceVariant,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 13,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small)),
    );
  }
}

/// Lays its children out in at most two rows. Everything that fits
/// [viewportWidth] in one row stays on one row; otherwise the children fill
/// a two-row grid column by column, with each column as wide as its wider
/// child so the two rows stay aligned. Meant to sit inside a horizontal
/// scroll view, which is why the viewport width is passed in rather than
/// read from the (unbounded) incoming constraints.
class TwoRowChipFlow extends MultiChildRenderObjectWidget {
  final double viewportWidth;
  final double horizontalGap;
  final double verticalGap;

  const TwoRowChipFlow({
    super.key,
    required this.viewportWidth,
    this.horizontalGap = 8,
    this.verticalGap = 6,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => RenderTwoRowFlow(
        viewportWidth: viewportWidth,
        horizontalGap: horizontalGap,
        verticalGap: verticalGap,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderTwoRowFlow renderObject) {
    renderObject
      ..viewportWidth = viewportWidth
      ..horizontalGap = horizontalGap
      ..verticalGap = verticalGap;
  }
}

class _TwoRowFlowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderTwoRowFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TwoRowFlowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TwoRowFlowParentData> {
  RenderTwoRowFlow({
    required double viewportWidth,
    required double horizontalGap,
    required double verticalGap,
  })  : _viewportWidth = viewportWidth,
        _horizontalGap = horizontalGap,
        _verticalGap = verticalGap;

  double _viewportWidth;
  set viewportWidth(double v) {
    if (v == _viewportWidth) return;
    _viewportWidth = v;
    markNeedsLayout();
  }

  double _horizontalGap;
  set horizontalGap(double v) {
    if (v == _horizontalGap) return;
    _horizontalGap = v;
    markNeedsLayout();
  }

  double _verticalGap;
  set verticalGap(double v) {
    if (v == _verticalGap) return;
    _verticalGap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TwoRowFlowParentData) {
      child.parentData = _TwoRowFlowParentData();
    }
  }

  /// Positions every child (unless [dry]) and returns the block's size.
  ///
  /// One row while everything fits [_viewportWidth]. Otherwise the children
  /// fill a grid of two rows column by column (top, bottom, next column…).
  /// Each column is as wide as the wider of its two children and both are
  /// stretched to that width, so the rows line up and every gap is exactly
  /// [_horizontalGap] — no half-empty columns.
  Size _layoutChildren({required bool dry}) {
    final children = getChildrenAsList();
    if (children.isEmpty) return Size.zero;
    // Pass 1: natural sizes.
    final sizes = <Size>[];
    var rowHeight = 0.0;
    var oneRowWidth = -_horizontalGap;
    for (final c in children) {
      final Size s;
      if (dry) {
        s = c.getDryLayout(const BoxConstraints());
      } else {
        c.layout(const BoxConstraints(), parentUsesSize: true);
        s = c.size;
      }
      sizes.add(s);
      rowHeight = math.max(rowHeight, s.height);
      oneRowWidth += s.width + _horizontalGap;
    }
    final rows = children.length > 1 && oneRowWidth > _viewportWidth ? 2 : 1;

    // Pass 2: column widths — the wider child of each column…
    final columns = (children.length + rows - 1) ~/ rows;
    final colWidths = List<double>.filled(columns, 0);
    for (var i = 0; i < children.length; i++) {
      final col = i ~/ rows;
      colWidths[col] = math.max(colWidths[col], sizes[i].width);
    }
    // …widened equally so the block spans the whole viewport edge to edge
    // whenever it would otherwise fall short. A block that has to scroll is
    // left at its natural width.
    var blockWidth = -_horizontalGap;
    for (final w in colWidths) {
      blockWidth += w + _horizontalGap;
    }
    if (_viewportWidth.isFinite && blockWidth < _viewportWidth) {
      final extra = (_viewportWidth - blockWidth) / columns;
      for (var col = 0; col < columns; col++) {
        colWidths[col] += extra;
      }
      blockWidth = _viewportWidth;
    }

    // Pass 3: place each column's children, widened to the column.
    if (!dry) {
      var x = 0.0;
      for (var col = 0; col < columns; col++) {
        final first = col * rows;
        final last = math.min(first + rows, children.length);
        for (var i = first; i < last; i++) {
          final child = children[i];
          if (child.size.width != colWidths[col]) {
            child.layout(
                BoxConstraints.tightFor(width: colWidths[col])
                    .copyWith(maxHeight: rowHeight),
                parentUsesSize: true);
          }
          final y = (i - first) * (rowHeight + _verticalGap);
          (child.parentData! as _TwoRowFlowParentData).offset =
              Offset(x, y + (rowHeight - child.size.height) / 2);
        }
        x += colWidths[col] + _horizontalGap;
      }
    }
    return Size(blockWidth, rows * rowHeight + (rows - 1) * _verticalGap);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_layoutChildren(dry: true));

  @override
  void performLayout() {
    size = constraints.constrain(_layoutChildren(dry: false));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// Highlighted, tappable category bar: "name (count)" with a round chevron
/// on the right that flips when the section is [open].
class CategorySectionBar extends StatelessWidget {
  final String label;
  final int count;
  final bool open;
  final VoidCallback onTap;

  const CategorySectionBar({
    super.key,
    required this.label,
    required this.count,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: open ? AppColors.primaryLight : AppColors.surfaceVariant,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: CategorySheetMetrics.sectionBarExtent,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: open ? AppColors.primary : AppColors.border,
                  width: 3),
              bottom: const BorderSide(color: AppColors.border),
            ),
          ),
          padding: const EdgeInsets.only(left: 9, right: 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: open
                              ? AppColors.primaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: open
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: AppFont.style(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: open
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: open ? AppColors.accent : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: open ? AppColors.accent : AppColors.border),
                ),
                child: AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: open ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
