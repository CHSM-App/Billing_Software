import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
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

  /// How the bar (and anything riding with it, like the Billing cart row)
  /// slides away and back on scroll: unhurried, easing in and out so it
  /// glides rather than snaps. Raise the duration for a slower glide.
  static const hideDuration = Duration(milliseconds: 420);
  static const hideCurve = Curves.easeInOutCubic;

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
        : AppBottomNavBar.hideDuration;
    return ValueListenableBuilder<bool>(
      valueListenable: AppBottomNavBar.shown,
      builder: (context, shown, child) => IgnorePointer(
        ignoring: !shown,
        child: AnimatedSlide(
          offset: shown ? Offset.zero : Offset(0, drop),
          duration: duration,
          curve: AppBottomNavBar.hideCurve,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: duration,
            curve: AppBottomNavBar.hideCurve,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _AppBottomNavBarState extends State<AppBottomNavBar>
    with TickerProviderStateMixin {
  /// Highlight position in TAB units: 0 = first tab, 1.5 = halfway between the
  /// second and third. Unbounded so the spring can run freely; drawing clamps.
  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: _target.toDouble());

  /// Near-critically damped: a slow, deliberate glide (~400ms for a one-tab
  /// hop) so the glass can be felt, with only a hint of settle and no visible
  /// bounce. Raise the stiffness to shift faster (300 = ~300ms, 520 = ~200ms).
  static final _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 180, ratio: 0.86);

  int get _target =>
      widget.selectedIndex.clamp(0, widget.items.length - 1).toInt();

  bool _dragging = false;

  /// 0..1: how far the lens is swollen because a finger is on it: 1 while a
  /// thumb drags it, ~0.45 while the selected tab is only pressed (a subtle
  /// squish). Eases in and out (see [_hold]), so it never pops in size.
  late final AnimationController _held = AnimationController(vsync: this);

  /// 0..1: how swollen the lens is right now. While the spring moves, the
  /// tinted pill grows into a larger, clearer lens with a thick glass edge that
  /// spills ~5px past the capsule, and the whole bar breathes ~2% bigger; both
  /// ease back as the spring settles (as in the iOS reference). Driven by
  /// velocity (tabs/sec, ~4.7 peak on a one-tab hop), so it rises and falls
  /// smoothly and quick re-taps keep it swollen instead of flickering. A thumb
  /// drag sets the value directly (velocity 0), so [_held] swells it instead;
  /// the larger of the two wins, so releasing hands over without a dip.
  double get _swell =>
      (_pos.velocity.abs() * 0.25).clamp(_held.value, 1.0).toDouble();

  void _hold(double to) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _held.value = to; // reduced motion: no grow/shrink tween
    } else {
      // Quicker to swell (140ms) than to settle back (220ms).
      _held.animateTo(to,
          duration: Duration(milliseconds: to > _held.value ? 140 : 220));
    }
  }

  /// Off switch for the liquid-glass shader (falls back to [RawMagnifier]).
  /// ponytail: on-device look not yet confirmed; flip to false if the rim
  /// samples the wrong spot (backdrop texture not screen-sized).
  static const _waterDrop = true;

  /// No glass lens on Android: on low-powered phones its extra backdrop pass
  /// (shader or [RawMagnifier]) made tab changes lag. Android keeps every
  /// other behaviour: the frosted bar, the indigo pill sliding on the spring
  /// and stretching, the bar breathing, press/drag, scroll-hide. iOS (and
  /// desktop) keep the lens.
  static bool get _lensEnabled =>
      defaultTargetPlatform != TargetPlatform.android;

  /// The liquid-glass lens shader (shaders/lens.frag), or null where the
  /// engine can't run shader filters: Skia (older Android GL devices) and
  /// widget tests. The lens then falls back to a plain [RawMagnifier].
  static final Future<FragmentProgram?> _lensProgram =
      _waterDrop && _lensEnabled && ImageFilter.isShaderFilterSupported
          ? FragmentProgram.fromAsset('shaders/lens.frag')
              .then<FragmentProgram?>((p) => p, onError: (_) => null)
          : Future.value(null);
  FragmentShader? _lensShader;

  @override
  void initState() {
    super.initState();
    _lensProgram.then((p) {
      if (p != null && mounted) {
        setState(() => _lensShader = p.fragmentShader());
      }
    });
  }

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
    _held.dispose();
    _lensShader?.dispose();
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
    _hold(0);
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
    // The whole bar breathes ~2% bigger with the lens (see [_swell]). It
    // scales the finished layer, so layout and tap slots don't move.
    return AnimatedBuilder(
      animation: Listenable.merge([_pos, _held]),
      builder: (context, bar) =>
          Transform.scale(scale: 1 + 0.02 * _swell, child: bar),
      child: Center(
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
            // Only the glass is clipped; the highlight and icons sit on top
            // unclipped, so the moving lens can swell past the capsule edge.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: radius,
                    // ponytail: one blur layer at sigma 18 — if low-end
                    // Android stutters, drop the sigma or swap for a solid
                    // ~92% fill.
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.75),
                          borderRadius: radius,
                          // Light rim so the glass edge reads over any
                          // background.
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: h,
                  padding: const EdgeInsets.all(4),
                  // Slot width is measured, never hard-coded, so the pill
                  // lines up on any screen width and tab count.
                  child: LayoutBuilder(builder: (context, box) {
                    final slotW = box.maxWidth / items.length;
                    // Pressing the selected tab squishes the lens a little;
                    // letting go eases it back. Raw pointer events, so taps
                    // and drags below are untouched (and a drag that starts
                    // from the press takes the lens on to full size).
                    return Listener(
                      onPointerDown: (d) {
                        if ((d.localPosition.dx / slotW).floor() == _target) {
                          _hold(0.45);
                        }
                      },
                      onPointerUp: (_) {
                        if (!_dragging) _hold(0);
                      },
                      onPointerCancel: (_) {
                        if (!_dragging) _hold(0);
                      },
                      child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) {
                        _dragging = true;
                        _pos.stop();
                        _hold(1);
                        _dragTo(d.localPosition.dx, slotW);
                      },
                      onHorizontalDragUpdate: (d) =>
                          _dragTo(d.localPosition.dx, slotW),
                      onHorizontalDragEnd: (_) => _dragEnd(),
                      onHorizontalDragCancel: _dragEnd,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_pos, _held]),
                        builder: (context, _) {
                          final p =
                              _pos.value.clamp(0.0, items.length - 1.0);
                          final s = _swell; // see [_swell]
                          final grow = 9 * s;
                          // Moving, the lens spans ~1.35 tabs, as in the
                          // reference.
                          final widen = 0.175 * s * slotW;
                          final lensSize = Size(slotW + 2 * widen,
                              box.maxHeight + 2 * grow);
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                key: const ValueKey('navHighlight'),
                                left: p * slotW - widen,
                                width: lensSize.width,
                                top: -grow,
                                bottom: -grow,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    // At rest: indigo tint, a step darker
                                    // than primaryLight so the active tab
                                    // reads clearly on the glass. Swollen:
                                    // mostly clear glass (the lens on top
                                    // draws the rim and shadow).
                                    // (No lens on Android: the pill keeps
                                    // its tint while it moves.)
                                    color: Color.lerp(
                                        AppColors.primary
                                            .withValues(alpha: 0.18),
                                        AppColors.surface
                                            .withValues(alpha: 0.25),
                                        _lensEnabled ? s : 0),
                                    borderRadius: BorderRadius.circular(h),
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
                              // The lens itself, only while it is swollen:
                              // it magnifies what is under it (icons, labels,
                              // the page behind the glass) up to 1.4x, like
                              // the iOS reference, with a white rim, a soft
                              // lift and the thick-glass edge on top. Above
                              // the icons, so it never takes their taps. At
                              // rest it is gone and everything is crisp.
                              if (s > 0.01 && _lensEnabled)
                                Positioned(
                                  left: p * slotW - widen,
                                  top: -grow,
                                  child: IgnorePointer(
                                    child: _lensShader == null
                                        ? RawMagnifier(
                                            size: lensSize,
                                            magnificationScale: 1 + 0.4 * s,
                                            decoration: MagnifierDecoration(
                                              shape: StadiumBorder(
                                                  side: BorderSide(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.9 * s))),
                                              shadows: [
                                                BoxShadow(
                                                  color: AppColors.textPrimary
                                                      .withValues(
                                                          alpha: 0.12 * s),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: CustomPaint(
                                                painter: _LensEdgePainter(s)),
                                          )
                                        // Impeller: the real liquid-glass
                                        // lens. The shader lights its own
                                        // rim; only a faint edge line is
                                        // drawn over it to define the
                                        // silhouette.
                                        : SizedBox.fromSize(
                                            size: lensSize,
                                            child: Stack(children: [
                                              // Contact shadow, only OUTSIDE
                                              // the lens, so the glass never
                                              // refracts a dark smear inward.
                                              Positioned.fill(
                                                child: ClipPath(
                                                  clipper: _OutsideStadium(),
                                                  child: DecoratedBox(
                                                    decoration: ShapeDecoration(
                                                      shape:
                                                          const StadiumBorder(),
                                                      shadows: [
                                                        BoxShadow(
                                                          color: AppColors
                                                              .textPrimary
                                                              .withValues(
                                                                  alpha:
                                                                      0.16 * s),
                                                          blurRadius: 10,
                                                          offset: const Offset(
                                                              0, 3),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DecoratedBox(
                                                position: DecorationPosition
                                                    .foreground,
                                                decoration: ShapeDecoration(
                                                  shape: StadiumBorder(
                                                      side: BorderSide(
                                                          color: Colors.white
                                                              .withValues(
                                                                  alpha: 0.35 *
                                                                      s))),
                                                ),
                                                child: ClipPath.shape(
                                                  shape: const StadiumBorder(),
                                                  child: _WaterDropLens(
                                                    shader: _lensShader!,
                                                    swell: s,
                                                    magnification:
                                                        1 + 0.4 * s,
                                                  ),
                                                ),
                                              ),
                                            ]),
                                          ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      ),
                    );
                  }),
                ),
              ],
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
        // The tab is a fixed 48px tall: past ~1.8x system text size the label
        // would overflow it. Cap at 1.6x, as iOS and Material tab bars cap
        // theirs; labels still grow 60% for large-text users.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.6,
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
      ),
    );
  }
}

/// The moving lens's thick glass edge: a soft dark band just inside the rim,
/// where a concave lens bends light the most, and a bright line where light
/// catches the upper inner edge. Both fade in with [s]; the centre stays
/// clear. Drawn over the lens's magnified image.
// ponytail: shaded, not refracted. Really warping the content at the rim
// needs a fragment shader (ImageFilter.shader, Impeller-only, so not on older
// Android GL devices); add it only if this reads flat on a device.
class _LensEdgePainter extends CustomPainter {
  _LensEdgePainter(this.s);

  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    if (s <= 0) return;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(rrect);
    // Inner shadow: a wide blurred stroke on the rim with its outer half
    // clipped away leaves a band that deepens toward the edge.
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = AppColors.textPrimary.withValues(alpha: 0.14 * s)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    // Highlight: the same rim nudged down, so only its upper arc lands inside.
    canvas.drawRRect(
        rrect.shift(const Offset(0, 1.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.8 * s)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LensEdgePainter old) => old.s != s;
}

/// Runs the water-drop shader (shaders/lens.frag) as a backdrop filter over
/// its own box. The lens rect is read at paint time, after layout, in the
/// physical pixels the shader sees, so the refraction never trails the lens
/// by a frame — including while the whole bar is scaled.
class _WaterDropLens extends SingleChildRenderObjectWidget {
  const _WaterDropLens({
    required this.shader,
    required this.swell,
    required this.magnification,
  }) : super(child: const SizedBox.expand());

  final FragmentShader shader;
  final double swell;
  final double magnification;

  @override
  _RenderWaterDropLens createRenderObject(BuildContext context) =>
      _RenderWaterDropLens(shader, swell, magnification,
          MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(
      BuildContext context, _RenderWaterDropLens renderObject) {
    renderObject
      ..shader = shader
      ..swell = swell
      ..magnification = magnification
      ..dpr = MediaQuery.devicePixelRatioOf(context)
      ..markNeedsPaint();
  }
}

class _RenderWaterDropLens extends RenderProxyBox {
  _RenderWaterDropLens(this.shader, this.swell, this.magnification, this.dpr);

  FragmentShader shader;
  double swell;
  double magnification;
  double dpr;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Logical global rect (getTransformTo(null) stops below the RenderView).
    final r = MatrixUtils.transformRect(
        getTransformTo(null), Offset.zero & size);
    shader
      // Floats 0-1 are u_size, which the engine fills in.
      ..setFloat(2, r.left * dpr)
      ..setFloat(3, r.top * dpr)
      ..setFloat(4, r.width * dpr)
      ..setFloat(5, r.height * dpr)
      ..setFloat(6, swell)
      ..setFloat(7, magnification);
    layer ??= BackdropFilterLayer();
    layer!.filter = ImageFilter.shader(shader);
    context.pushLayer(layer!, super.paint, offset);
  }
}

/// Everything except the inside of a stadium the size of the box: lets the
/// lens's contact shadow show around the glass without darkening the glass.
class _OutsideStadium extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final box = Offset.zero & size;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(box.inflate(40)) // room for the shadow's blur and offset
      ..addRRect(
          RRect.fromRectAndRadius(box, Radius.circular(size.height / 2)));
  }

  @override
  bool shouldReclip(_OutsideStadium oldClipper) => false; // size-only
}
