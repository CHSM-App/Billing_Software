import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../theme/app_theme.dart';
import 'nav_item.dart';

/// Floating "glass" bottom bar: a capsule that hovers above the bottom edge,
/// blurs whatever scrolls behind it, and slides a highlight pill to the
/// selected tab. The shell lays page content underneath it (extendBody), so
/// this widget only draws the capsule — margins and safe-area are the caller's.
///
/// The highlight moves on a spring (WhatsApp-on-iPhone feel): a tap springs it
/// to the new tab, keeping its current speed if it was already moving, so
/// rapid taps glide instead of jumping. It can also be dragged with a finger —
/// it tracks the thumb, and letting go selects the tab under it.
class AppBottomNavBar extends StatefulWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const double height = 56;

  /// Never stretch the capsule across a tablet: past this width the tabs
  /// drift too far apart to scan.
  static const double maxWidth = 520;

  /// Extra bottom offset for a tab's floatingActionButton. A Scaffold lifts
  /// its FAB only past the SYSTEM inset (viewPadding); the glass bar's height
  /// lives in `padding` (the shell's extendBody), so the FAB would otherwise
  /// sit hidden behind the bar. Zero on wide layouts and pushed screens.
  static double fabLift(BuildContext context) {
    final mq = MediaQuery.of(context);
    final lift = mq.padding.bottom - mq.viewPadding.bottom;
    return lift > 0 ? lift : 0;
  }

  /// Whether the bar is showing or scrolled away (the shell drives it; see
  /// MainShell._onPageScroll). Static: there is one shell, and tab screens
  /// read it through [HidesWithNavBar] without the shell passing it down.
  static final ValueNotifier<bool> shown = ValueNotifier(true);

  @override
  State<AppBottomNavBar> createState() => _AppBottomNavBarState();
}

/// Slides [child] down off the screen, fading, while the bottom bar is
/// scrolled away ([AppBottomNavBar.shown]), and keeps it from taking taps
/// meanwhile. [drop] is how far to slide in [child]'s own heights.
class HidesWithNavBar extends StatelessWidget {
  const HidesWithNavBar({super.key, required this.child, this.drop = 1});

  final Widget child;
  final double drop;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return ValueListenableBuilder<bool>(
      valueListenable: AppBottomNavBar.shown,
      builder: (context, shown, child) => IgnorePointer(
        ignoring: !shown,
        child: AnimatedSlide(
          offset: shown ? Offset.zero : Offset(0, drop),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: duration,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _AppBottomNavBarState extends State<AppBottomNavBar>
    with SingleTickerProviderStateMixin {
  /// Highlight position in TAB units: 0 = first tab, 1.5 = halfway between the
  /// second and third. Unbounded so the spring can run freely; drawing clamps.
  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: _target.toDouble());

  /// Near-critically damped: a quick, decisive glide with only a hint of
  /// settle, no visible bounce.
  static final _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: 0.86);

  int get _target =>
      widget.selectedIndex.clamp(0, widget.items.length - 1).toInt();

  bool _dragging = false;

  @override
  void didUpdateWidget(AppBottomNavBar old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) {
      // Tabs appeared/disappeared (role or Orders badge rules): no slide
      // across a layout that just changed under it.
      _pos.value = _target.toDouble();
    } else if (old.selectedIndex != widget.selectedIndex && !_dragging) {
      _springTo(_target);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _springTo(int index) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pos.value = index.toDouble(); // reduced motion: jump, don't slide
      return;
    }
    // Starts from wherever the pill is NOW, at the speed it is moving now —
    // that is what keeps rapid taps smooth.
    _pos.animateWith(
        SpringSimulation(_spring, _pos.value, index.toDouble(), _pos.velocity));
  }

  // ── Thumb dragging ────────────────────────────────────────────────────────
  /// The tab the pill is over during a drag; -1 before the drag's first move.
  int _dragTab = -1;

  void _dragTo(double dx, double slotW) {
    _pos.value = (dx / slotW - 0.5).clamp(0.0, widget.items.length - 1.0);
    // A light tick each time the pill crosses onto another tab, like an iOS
    // picker wheel, so the thumb feels the tabs it passes.
    final tab = _pos.value.round();
    if (tab != _dragTab) {
      if (_dragTab != -1) HapticFeedback.selectionClick();
      _dragTab = tab;
    }
  }

  void _dragEnd() {
    // A plain tap also reports a drag "cancel" — only a real drag may pick.
    if (!_dragging) return;
    _dragging = false;
    _dragTab = -1;
    final i = _pos.value.round();
    _springTo(i);
    if (i != widget.selectedIndex) {
      HapticFeedback.lightImpact(); // a firmer bump when a new tab is picked
      widget.onDestinationSelected(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    const h = AppBottomNavBar.height;
    final radius = BorderRadius.circular(h / 2);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBottomNavBar.maxWidth),
        child: RepaintBoundary(
          // Shadow lives OUTSIDE the clip — ClipRRect would cut it off.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              // ponytail: one blur layer at sigma 18 — if low-end Android
              // stutters, drop the sigma or swap for a solid ~92% fill.
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: h,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.75),
                    borderRadius: radius,
                    // Light rim so the glass edge reads over any background.
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  // Slot width is measured, never hard-coded, so the pill
                  // lines up on any screen width and tab count.
                  child: LayoutBuilder(builder: (context, box) {
                    final slotW = box.maxWidth / items.length;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) {
                        _dragging = true;
                        _pos.stop();
                        _dragTo(d.localPosition.dx, slotW);
                      },
                      onHorizontalDragUpdate: (d) =>
                          _dragTo(d.localPosition.dx, slotW),
                      onHorizontalDragEnd: (_) => _dragEnd(),
                      onHorizontalDragCancel: _dragEnd,
                      child: AnimatedBuilder(
                        animation: _pos,
                        builder: (context, _) {
                          final p =
                              _pos.value.clamp(0.0, items.length - 1.0);
                          return Stack(
                            children: [
                              Positioned(
                                left: p * slotW,
                                top: 0,
                                bottom: 0,
                                width: slotW,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    // Indigo tint, a step darker than
                                    // primaryLight so the active tab reads
                                    // clearly on the glass.
                                    color: AppColors.primary
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(h / 2),
                                  ),
                                ),
                              ),
                              Row(
                                children: List.generate(items.length, (i) {
                                  // 1 when the pill sits on this tab, fading
                                  // to 0 one slot away — colours follow the
                                  // pill as it glides instead of snapping.
                                  final t = (1 - (p - i).abs()).clamp(0.0, 1.0);
                                  return Expanded(
                                    child: _NavButton(
                                      item: items[i],
                                      selected: i == widget.selectedIndex,
                                      emphasis: t,
                                      onTap: () =>
                                          widget.onDestinationSelected(i),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavItem item;

  /// The real selection — drives accessibility, not visuals.
  final bool selected;

  /// 0..1: how much the moving highlight covers this tab right now.
  final double emphasis;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.emphasis,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        Color.lerp(AppColors.textSecondary, AppColors.primary, emphasis)!;
    final lit = emphasis > 0.5;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            item.badged(Icon(
              lit ? item.iconFilled : item.iconOutlined,
              size: 20,
              color: color,
            )),
            const SizedBox(height: 1),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.lerp(
                    FontWeight.w500, FontWeight.w700, emphasis),
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
