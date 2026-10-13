import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// A header sitting ABOVE a scroll view that folds away with the content,
/// YouTube-style, while anything between it and the list (the Billing /
/// Items category strip) stays pinned at the top.
///
/// Usage: header pieces in [FoldAway]s on [bar]; the list gets [physics];
/// a `NotificationListener<ScrollNotification>(onNotification: onScroll)`
/// sits around the list.
///
///  * a finger drag is spent on the header first ([FloatingBarPhysics]), so
///    the rows track the finger exactly while it folds or unfolds;
///  * a fling carries the fold on at the list's speed, so a quick flick hides
///    the whole header rather than leaving it half way;
///  * once scrolling stops, a half-folded header finishes the way the user was
///    going; at the top of the list it always opens.
///
/// Done outside the list's slivers so its scroll offsets still start at 0 —
/// the jump-to-category and scroll-spy math is built on that. Programmatic
/// scrolls (a category jump) never fold it.
class FoldingHeader {
  FoldingHeader({
    required TickerProvider vsync,
    required this.extent,
    required this.canFold,
  }) : bar = AnimationController(
            vsync: vsync,
            value: 1,
            duration: const Duration(milliseconds: 260));

  /// How much of the header shows: 0 = folded away, 1 = fully shown.
  final AnimationController bar;

  /// The header's full height. A callback: it can change (a tab bar coming
  /// and going), and a Scrollable keeps its first physics object.
  final double Function() extent;

  /// False pins the header open (search in use, wide layout…).
  final bool Function() canFold;

  late final ScrollPhysics physics = FloatingBarPhysics(
    bar: bar,
    extent: extent,
    canFloat: canFold,
    parent: const AlwaysScrollableScrollPhysics(),
  );

  bool _userScrolling = false;
  ScrollDirection _lastDir = ScrollDirection.idle;

  /// Opens the header with the same easing as a snap.
  void show() {
    if (bar.value < 1 && !(bar.isAnimating && bar.velocity > 0)) {
      bar.animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  /// For a screen whose lists are built by other widgets (tab views of other
  /// screens): every scrollable below gets [physics] — their own physics
  /// chain onto it — and their scrolls drive the fold.
  Widget wrap(BuildContext context, Widget child) {
    final config = ScrollConfiguration.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: onScroll,
      child: ScrollConfiguration(
        behavior: config.copyWith(
            physics: physics.applyTo(config.getScrollPhysics(context))),
        child: child,
      ),
    );
  }

  bool onScroll(ScrollNotification n) {
    // Only vertical lists — not the sideways chip strips or tab pages.
    // ponytail: no depth filter (tab-view lists sit inside a horizontal
    // PageView); a vertical list nested in another would count twice.
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      _userScrolling = n.direction != ScrollDirection.idle;
      if (_userScrolling) {
        _lastDir = n.direction;
      } else {
        _settle(n.metrics);
      }
    } else if (n is ScrollUpdateNotification) {
      if (n.metrics.extentBefore <= 0) {
        show();
      } else if (n.dragDetails == null && _userScrolling && canFold()) {
        // The fling after a flick: keep folding/unfolding at its speed.
        final d = n.scrollDelta ?? 0;
        bar.value = (bar.value - d / extent()).clamp(0.0, 1.0);
      }
    }
    return false;
  }

  void _settle(ScrollMetrics m) {
    if (bar.value <= 0 || bar.value >= 1 || bar.isAnimating) return;
    // reverse = moving further down the list = folding.
    final fold = _lastDir == ScrollDirection.reverse && m.extentBefore > 0;
    bar.animateTo(fold ? 0 : 1, curve: Curves.easeOutCubic);
  }

  void dispose() => bar.dispose();
}

/// Spends a finger drag on the header first — dragging up folds it, dragging
/// down brings it back — and passes only the rest to the list.
class FloatingBarPhysics extends ScrollPhysics {
  const FloatingBarPhysics({
    required this.bar,
    required this.extent,
    required this.canFloat,
    super.parent,
  });

  /// How much of the bar shows: 0 = folded away, 1 = fully shown.
  final AnimationController bar;

  /// The bar's full height in logical pixels.
  final double Function() extent;

  /// False pins the bar open.
  final bool Function() canFloat;

  @override
  FloatingBarPhysics applyTo(ScrollPhysics? ancestor) => FloatingBarPhysics(
      bar: bar,
      extent: extent,
      canFloat: canFloat,
      parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // Sideways scrollables (tab pages, chip strips) may inherit this physics
    // through a ScrollConfiguration — they must never fold the bar.
    if (position.axis == Axis.vertical && canFloat()) {
      // offset < 0: finger moving up, i.e. further down the list.
      final h = extent();
      final next = (bar.value + offset / h).clamp(0.0, 1.0);
      final used = (next - bar.value) * h;
      if (used != 0) {
        bar.value = next;
        offset -= used;
      }
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }
}

/// Shows the bottom share of [child] given by [bar] (1 = all), so it slides
/// up out of sight as the header folds.
///
/// A header made of separate pieces folds as ONE block by giving each piece
/// its own slice of the fold, top piece first: see [slice].
class FoldAway extends AnimatedWidget {
  const FoldAway({super.key, required Animation<double> bar, required this.child})
      : super(listenable: bar);

  /// [header]'s fold, narrowed to one piece: [below] px of header sit under
  /// this piece and it is [height] px tall, out of [total]. The piece starts
  /// folding only once everything above it has gone.
  static Animation<double> slice(AnimationController header,
          {required double below, required double height, required double total}) =>
      header.drive(CurveTween(
          curve: Interval(below / total, (below + height) / total)));

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: (listenable as Animation<double>).value,
          child: child,
        ),
      );
}
