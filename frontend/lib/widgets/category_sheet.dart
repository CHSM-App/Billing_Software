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

// ---------------------------------------------------------------------------
// Two-level (major → sub-category) sheet
// ---------------------------------------------------------------------------
//
// The billing screen groups items under a major category, and its
// sub-categories under that. These three widgets are the visual pieces of
// that tree. They are deliberately dumb — every label arrives pre-formatted
// and every height is passed in — so the owning screen keeps control of the
// fixed row extents its scroll math depends on, and so they can be rendered
// in a test without the screen's providers.

/// Fold clock shared by every part of the tree, so a group's bar, rail and
/// chevron all move together.
class CategoryTreeMotion {
  static const Duration duration = Duration(milliseconds: 300);
  static const Curve curve = Curves.easeOutCubic;
}

/// The tree's accent colour.
///
/// A per-major palette was tried here — a different hue for each major, its
/// whole subtree tinted to match — and pulled: on a dense billing list the
/// varying hues read as noise rather than as a way to tell blocks apart. The
/// tree is one colour again.
///
/// The accent is still threaded through every widget rather than hardcoded, so
/// this stayed a change to [of] alone. Bringing a palette back — per major, or
/// per anything else — is a change to [of] and nothing else.
class CategoryAccents {
  static Color of(int index) => AppColors.primary;

  /// Background wash for a major's card.
  static Color surfaceTint(Color accent) => AppColors.primaryLight;

  /// Wash for an open sub-category inside it.
  static Color openTint(Color accent) => AppColors.primaryLight;

  /// The rail and elbow — structure, so it stays a plain neutral rather than
  /// taking the accent and competing with the cards it hangs.
  static Color railTint(Color accent) => AppColors.border;

  /// Pill behind an item count on an open card.
  static Color pillTint(Color accent) => accent.withValues(alpha: 0.12);
}

/// One slice of the vertical rail drawn down the left gutter of everything
/// filed under a major category.
class TreeRail extends StatelessWidget {
  final double width;
  final Color color;

  /// Draw the horizontal elbow reaching right to the card this rail belongs
  /// to. True for a sub-category card; false for the item rows inside one,
  /// which only continue the vertical line.
  final bool branch;

  /// Stop the vertical line at the elbow, so the rail ends on the last
  /// sub-category instead of trailing past it into the next major's gap.
  final bool isLast;

  /// Where the elbow meets the card, measured in pixels from the top of the
  /// rail. Null centres it. Needed because the rail runs the FULL height of a
  /// row — gap included, so the line never breaks between cards — while the
  /// card it points at is inset below that gap, so the two midpoints differ.
  final double? branchY;

  const TreeRail({
    super.key,
    required this.width,
    required this.color,
    this.branch = false,
    this.isLast = false,
    this.branchY,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: CustomPaint(
          painter: _TreeRailPainter(
            color: color,
            branch: branch,
            isLast: isLast,
            branchY: branchY,
          ),
        ),
      );
}

class _TreeRailPainter extends CustomPainter {
  final Color color;
  final bool branch;
  final bool isLast;
  final double? branchY;

  const _TreeRailPainter({
    required this.color,
    required this.branch,
    required this.isLast,
    this.branchY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    // Centred in the gutter, leaving the card's own left edge clear.
    final x = size.width / 2;
    final midY = branchY ?? size.height / 2;
    final endY = isLast && branch ? midY : size.height;

    canvas.drawLine(Offset(x, 0), Offset(x, endY), paint);
    if (branch) {
      canvas.drawLine(Offset(x, midY), Offset(size.width, midY), paint);
    }
  }

  @override
  bool shouldRepaint(_TreeRailPainter old) =>
      old.color != color ||
      old.branch != branch ||
      old.isLast != isLast ||
      old.branchY != branchY;
}

/// Major-category card: just the name and a chevron. Tinted and rounded so it
/// reads as the container its sub-category cards sit inside rather than a peer
/// of them — the tint and weight carry that on their own, without a second
/// line of text under the name.
///
/// [height] is the whole extent INCLUDING the trailing gap — the owning list
/// sums these to position jumps, so spacing must live inside the extent rather
/// than as a margin between entries.
class MajorCategoryCard extends StatelessWidget {
  final String label;
  final bool open;
  final VoidCallback onTap;
  final double height;

  /// This major's hue — see [CategoryAccents]. Everything under it carries the
  /// same one.
  final Color accent;

  /// Space above the card, inside its fixed [height] — the break between one
  /// major's block and the next. Matches SubCategoryCard's top-gap rule.
  final double topGap;

  const MajorCategoryCard({
    super.key,
    required this.label,
    required this.open,
    required this.onTap,
    required this.height,
    required this.accent,
    this.topGap = 10,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, topGap, 8, 0),
          child: Material(
            color: CategoryAccents.surfaceTint(accent),
            borderRadius: BorderRadius.circular(AppRadius.small),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: CategoryTreeMotion.duration,
                      curve: CategoryTreeMotion.curve,
                      child: const Icon(Icons.expand_more,
                          size: 22, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Sub-category card hung off the tree rail: name, an "N items" pill beside
/// it, and a chevron pointing right while shut and up once open.
///
/// [nested] is false only for a menu with no major level at all, where these
/// are the top-level bars and there is no rail to hang them from.
class SubCategoryCard extends StatelessWidget {
  final String label;
  final String countLabel;
  final bool open;
  final bool nested;
  final bool isLast;
  final VoidCallback onTap;
  final double height;
  final double railGutter;

  /// The hue of the major this sits under — see [CategoryAccents].
  final Color accent;

  /// Space above the card, inside its fixed [height]. See build() for why the
  /// gap sits on top rather than underneath.
  final double topGap;

  const SubCategoryCard({
    super.key,
    required this.label,
    required this.countLabel,
    required this.open,
    required this.nested,
    required this.isLast,
    required this.onTap,
    required this.height,
    required this.railGutter,
    required this.accent,
    this.topGap = 6,
  });

  @override
  Widget build(BuildContext context) {
    // Open, the card is the TOP of a box that continues down over its item
    // rows: square bottom corners, and the rows below carry the same side
    // borders on and close it off. See ItemRowFrame.
    final radius = open
        ? const BorderRadius.vertical(top: Radius.circular(AppRadius.small))
        : BorderRadius.circular(AppRadius.small);

    final card = AnimatedContainer(
      duration: CategoryTreeMotion.duration,
      curve: CategoryTreeMotion.curve,
      decoration: BoxDecoration(
        color: open ? CategoryAccents.openTint(accent) : AppColors.surface,
        borderRadius: radius,
        // Border.all — a UNIFORM border. Flutter asserts
        // "A borderRadius can only be given on borders with uniform colors",
        // and BorderSide.none is not colourless: it carries the default black,
        // so dropping just the bottom side made the four colours disagree and
        // every open card threw. The bottom edge stays, and doubles as the
        // rule between the header and the first item row.
        border: Border.all(color: open ? accent : AppColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Column(
            children: [
              Expanded(
                child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              children: [
                // Name and pill share ONE Expanded so the chevron lands on the
                // right edge every time. A bare Flexible beside a Spacer split
                // the free space between them instead, which drifted the
                // chevron left or right with the length of the name.
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
                                ? accent
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // "8 items" rather than a bare digit — the number alone
                      // read as a price or a quantity on a dense billing
                      // screen.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: open
                              ? CategoryAccents.pillTint(accent)
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          countLabel,
                          style: AppFont.style(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: open
                                ? accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // chevron_right rotated a quarter turn anticlockwise becomes a
                // chevron_up, so ">" and "^" are one widget animating between
                // the two states rather than two icons swapping.
                AnimatedRotation(
                  turns: open ? -0.25 : 0,
                  duration: CategoryTreeMotion.duration,
                  curve: CategoryTreeMotion.curve,
                  child: Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: open ? accent : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
              ),
            ],
          ),
        ),
      ),
    );

    // Gap on TOP, not bottom. A card must never put space under itself: when
    // it is open its item rows have to butt straight against it for the shared
    // border to read as one box. Spacing each card away from whatever precedes
    // it gives the same even gaps AND a clean break after a closed box.
    //
    // The gap is applied to the CARD, not to the row — the rail has to run the
    // row's full height or the vertical line breaks at every gap.
    final inset = Padding(padding: EdgeInsets.only(top: topGap), child: card);

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8),
        child: nested
            // stretch, NOT the default centre: a Row sizes an unconstrained
            // child to its intrinsic height, and the rail's SizedBox has none —
            // it collapsed to zero height and painted nothing but the elbow.
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TreeRail(
                    // The major's hue, heavily muted — enough to tie the
                    // branch to its major, not enough to compete with the
                    // card. Never varies with open/shut: the rail is
                    // structure, and the card already shows that state.
                    width: railGutter,
                    color: CategoryAccents.railTint(accent),
                    branch: true,
                    isLast: isLast,
                    // Aim the elbow at the middle of the CARD, which sits
                    // below the gap, not the middle of the whole row.
                    branchY: topGap + (height - topGap) / 2,
                  ),
                  Expanded(child: inset),
                ],
              )
            : inset,
      ),
    );
  }
}

/// Continues an open [SubCategoryCard]'s border down over one of its item
/// rows, so the card and everything inside it read as a single box.
///
/// The rows are separate entries in the owning sliver — a fixed extent each,
/// for the scroll math — so no widget can wrap them all. The border is drawn
/// per row instead: side edges on every one, and the bottom edge plus rounded
/// corners only on [isLast].
class ItemRowFrame extends StatelessWidget {
  final Widget child;
  final bool isLast;

  /// The hue of the major this row's sub-category sits under, so the open
  /// box's sides match the card that opened it.
  final Color accent;

  const ItemRowFrame({
    super.key,
    required this.child,
    required this.isLast,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.surface),
        // Painted in the FOREGROUND, over the child. An item row fills its own
        // opaque background across the full width (the in-cart tint, the open
        // group tint), which drew straight over a border painted behind it —
        // the side edges vanished and only the top and bottom survived.
        //
        // A CustomPaint rather than a Border: this shape is three sides with
        // two rounded corners, and Flutter's Border refuses a borderRadius
        // unless all four sides share a colour — BorderSide.none counts as
        // black, so the "open" side made them disagree and it threw.
        child: CustomPaint(
          foregroundPainter:
              _ItemFramePainter(color: accent, isLast: isLast),
          child: child,
        ),
      );
}

/// Draws an open group's box down one item row: both sides, and on the final
/// row the bottom edge with its two rounded corners.
class _ItemFramePainter extends CustomPainter {
  final Color color;
  final bool isLast;

  const _ItemFramePainter({required this.color, required this.isLast});

  static const double _radius = AppRadius.small;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Half a pixel in, so a 1px stroke lands ON the boundary rather than
    // straddling it and rendering as a soft 2px smudge.
    const h = 0.5;
    final right = size.width - h;
    final bottom = size.height - h;

    if (!isLast) {
      canvas.drawLine(const Offset(h, 0), Offset(h, size.height), paint);
      canvas.drawLine(Offset(right, 0), Offset(right, size.height), paint);
      return;
    }
    canvas.drawPath(
      Path()
        ..moveTo(h, 0)
        ..lineTo(h, bottom - _radius)
        ..arcToPoint(Offset(h + _radius, bottom),
            radius: const Radius.circular(_radius), clockwise: false)
        ..lineTo(right - _radius, bottom)
        ..arcToPoint(Offset(right, bottom - _radius),
            radius: const Radius.circular(_radius), clockwise: false)
        ..lineTo(right, 0),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ItemFramePainter old) =>
      old.color != color || old.isLast != isLast;
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
