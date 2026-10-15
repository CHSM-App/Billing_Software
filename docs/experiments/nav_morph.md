# Experiment: swelling "lens" highlight (from the WhatsApp iPhone reference)

Status: **trial**. It is left **unstaged** and builds on the glass bar (`glass_nav.md`) and on
scroll-hide (`scroll_hide.md`), both committed in e6a77e4c. To undo only this experiment, run
this from the repo root:

```sh
git apply -R docs/experiments/nav_morph.patch
```

To preview the undo first, run `git apply -R --check docs/experiments/nav_morph.patch`. This
patch is the only copy, so keep it.

## What the reference does (frame by frame, 55fps)

1. At rest there is a tinted pill behind the selected tab, inside the bar.
2. On a tap, the pill swells into a larger, clear glass lens with a bright rim. The lens
   spills past the top and bottom of the bar, and it does this within about 2 frames.
3. The lens travels to the new tab while it is still swollen.
4. It shrinks back into the tinted pill under the new tab. The whole move takes about 220ms.

The selected icon also turns filled. The bar already did that.

Also visible on a closer look: the **whole bar grows about 2%** (icons included) on every tab change and
eases back. The labels at both ends move about 2.5px outward. The **lens edge looks like thick concave glass**:
the centre is clear, and the rim shows a dark band where the glass bends content.

## What Vittam does now

- **Slower shift:** the spring stiffness went from 520 to 300 (damping ratio 0.86 unchanged), so a
  one-tab hop now settles in about 300ms instead of about 200ms. A re-tap still picks up the current speed.
- **Swell = spring speed.** `_swell = |velocity| x 0.2`, clamped to 0..1, so the lens grows as the
  highlight speeds up and shrinks as it settles.
  - When fully swollen, the lens is 9px taller at each end, which is about 5px past the capsule
    edge. It is also 6% of a slot wider on each side.
  - The fill fades from indigo at 18% to surface at 25%. A white rim and a soft shadow fade in.
  - **Concave edge** (`_LensEdgePainter`): a 12px blurred dark stroke inside the rim gives a band
    that darkens toward the edge. A 2px white stroke shifted down 1.5px leaves a bright line along
    the upper inner edge. It is drawn over the lens's magnified image.
- **Magnifying lens** (from a closer look at the reference): while moving, the lens magnifies
  whatever is under it, up to 1.4x: the icons, the labels, and the page behind the glass. It also
  spans about 1.35 tabs. This uses Flutter's built-in `RawMagnifier` (the iOS text-selection
  loupe), which runs on both Impeller and Skia. It sits ABOVE the icons in an `IgnorePointer`, so
  taps still reach the tabs, and it is removed entirely at rest (`s <= 0.01`), so the settled bar
  is crisp and has no extra backdrop cost. The tinted pill under the icons stays and fades to clear
  as the lens takes over. The rim and lift shadow are now the magnifier's `MagnifierDecoration`.
- **Whole bar grows:** an `AnimatedBuilder` around the capsule applies
  `Transform.scale(1 + 0.02 x _swell)`. This scales the finished layer, so layout and tap slots
  do not move.
  - Rapid re-taps keep the speed up, so the lens stays swollen instead of flickering.
- **Only the glass is clipped now.** Before, the highlight and the icons sat inside the
  `ClipRRect`. Now they sit in an unclipped `Stack` above the clipped blur, so the lens can
  spill over the edge. The shadow, blur, fill and rim are unchanged.
- **Thumb drag:** the lens swells to full size while the thumb holds it, using a separate
  `_held` controller (140ms to grow, 220ms to shrink). The swell is the larger of `_held` and the
  speed value, so letting go hands over to the spring without a dip.
- **Reduced motion:** the highlight jumps to the new tab with no swell. A thumb drag still
  shows the lens, but it appears and disappears instantly instead of growing.
- **Icons, labels and badges** are separate widgets drawn on top of the lens and are never
  scaled. Their colour still blends with how much of the pill covers them.

- **Water-drop rim** (`frontend/shaders/lens.frag`, Impeller only, which covers all iOS and modern
  Android): a fragment shader runs as the lens's backdrop filter. The middle magnifies like
  before. In a rim band (55% of the lens's half-height) the glass curves away on a circular
  profile, so the shader samples from beyond the rim. Content gets squeezed and bent along the edge
  like light through a drop, with a slight red/blue split and a bright line just inside the rim.
  `_RenderWaterDropLens` reads the lens's screen rect at paint time (after layout, including the
  bar's scale) and passes it to the shader in physical pixels.
- **Fallback:** on Skia (older Android GL devices, widget tests) `ImageFilter.isShaderFilterSupported`
  is false, so the lens stays the plain `RawMagnifier` with the painted edge. It also falls back
  if the shader fails to load, or if `_waterDrop` is set to `false`.

## Files

| File | Change |
|---|---|
| `frontend/lib/widgets/bottom_nav_bar.dart` | `build` rewritten: the glass is in a clipped `Positioned.fill`, the highlight and the row are in an unclipped `Stack`. The highlight swells with spring speed. The `navHighlight` key is on the highlight's `Positioned`. |
| `frontend/shaders/lens.frag` | New: the water-drop lens shader. |
| `frontend/pubspec.yaml` | `flutter: shaders: - shaders/lens.frag`. |
| `frontend/test/widgets/bottom_nav_bar_test.dart` | The lens test also checks a `RawMagnifier` is present mid-move and gone at rest. The lens test also checks that the bar is wider mid-move and back to its exact size afterwards. The drag test now also checks the lens is swollen while held and back to normal after release. New test: mid-slide the lens is wider than at rest and more than 8px taller (it spills past the capsule). After settling it is back to one slot, two tabs over. |

## Tuning knobs (the `// Lens swell` block in `build`)

- `stiffness: 180`: shift speed (about 400ms per one-tab hop, slowed so the glass can be felt). Higher is faster: 300 is about 300ms, 520 about 200ms.
- `0.25` in `_swell`: how quickly the lens reaches full swell. A one-tab hop peaks at about 4.7 tabs/s.
- `0.02` in the `Transform.scale`: how much the whole bar grows.
- `_LensEdgePainter`: edge band `strokeWidth 12`, `blur 5`, `alpha 0.14`; highlight `alpha 0.8`.
- `9 * s`: the vertical growth per end. It must stay under the shell's 8px bottom margin plus
  4px of padding.
- `0.175 * s * slotW`: the horizontal growth per side (0.175 gives about 1.35 tabs wide).
- `1 + 0.4 * s` (`magnificationScale`): how much the lens magnifies.
- Thumb-drag lens: the `_held` durations (140ms grow, 220ms shrink).
- Water drop (in `lens.frag`): rim band `r * 0.55`, bend strength `1.2`, colour split
  `1.12`/`0.88`, rim light `0.22`. Set `_waterDrop = false` in `bottom_nav_bar.dart` to turn it off.
- Lens look: the surface fill at `0.35`, the rim at `0.9`, the shadow at `0.12`.

## Verified (2026-10-13)

- Frame by frame against the video: frames were rendered from a throwaway golden test (since
  deleted) at 0/16/33/50/83/116/150/200/260/400ms. They match the reference in shape and
  timing. Our swell starts one frame earlier (about 16ms instead of 33ms).
- Bar grow, concave edge and the slower spring: frames re-rendered at 0–600ms; the bar widens and
  returns, and the lens edge band shows with a clear centre.
- Magnifier: frames re-rendered over a striped background; inside the lens, the neighbouring
  labels show magnified and clipped at the rim, and the lens is gone once settled.
- `flutter analyze` on both files: no issues.
- Full `flutter test`: all 245 tests pass.
- Water drop: `flutter build apk --debug` compiles the shader, and `lens.frag` is in the APK. The
  phone (SM-S721B, Android 16) runs Impeller on Vulkan. That phone run happened before the shader
  was registered in pubspec, so it used the fallback. **The water-drop lens itself has not been
  seen on a device yet.**
- **Not checked on a device** (no phone or emulator attached): how it feels at 60/120Hz, how the
  lens looks over real content, and blur cost on low-end Android.

## Liquid-glass upgrade (2026-10-13, later)

**Audit of `liquid_glass_easy` v5.0.0** (MIT, github.com/AhmeedGamil/liquid_glass_easy):
- It uses the same technique as ours: an Impeller `BackdropFilter` running `ImageFilter.shader` on the
  live backdrop. There are no per-frame captures on Impeller.
- On Skia without its own capture view, it degrades to frost and blur with no refraction.
- It is about 29k lines of Dart, and adopting its `LiquidGlassTabBar` would replace our bar, the
  scroll-hide, the badges and the drag behaviour. So it is **not added as a dependency**.
- Conventions we borrowed from it:
  - Fragment coordinates are full-frame physical pixels on Flutter 3.38. Its changelog says
    Flutter 3.47 changed this for composed passes, so re-check after an SDK upgrade.
  - The Impeller backdrop alpha is not a transparency signal, so the shader treats the backdrop
    as opaque.
  - Keep uniforms few, because iOS 26 caps them at about 30.

**What `lens.frag` does now:**
- **Refraction:** a circular-profile rim (60% of the half-height) that is strongest at the edge and
  flat in the middle, with the middle magnified.
- **Dispersion:** per-channel sampling (red 0.86x, green 1x, blue 1.14x of the offset). This gives
  thin blue/purple and yellow fringes, only where content edges cross the rim.
- **Frost:** a 7% milky lift in the middle with no blur.
- **Light:** a Fresnel rim (`t^4`), plus a thin specular line lit from the upper left with a faint
  far arc. It is brighter over bright backgrounds.

**Dart changes:**
- A **contact shadow** is drawn only outside the lens (`_OutsideStadium` clipper), so the glass never
  refracts a dark smear inward.
- The flat white outline is now faint (0.35), because the shader lights its own rim.
- **Press deformation:** a raw `Listener` eases `_held` to 0.45 while the selected tab is pressed
  and back to 0 on release. A drag still takes it to 1. Taps and drags are unaffected.
- New test: the press swells the lens subtly (more than 4px and less than 12px taller), release
  settles it, and the tap still goes through.

**Verified:**
- `flutter analyze` is clean, all 246 tests pass, and `flutter build apk --debug` compiles the shader.
- **Not seen on a device:** the user chose to check it themselves. iOS is untested, because this is a
  Windows host. The widget tests only run the Skia fallback (`RawMagnifier`), never the shader.

## Device-class checks (2026-10-13)

- **Responsiveness test** (`bottom_nav_bar_test.dart`) covers 108 combinations:
  - widths 320, 360, 393, 412, 430 and 719
  - 2, 4 and 5 tabs
  - text scale 1.0 and 2.0
  - Android (pixel ratio 2.625, 24px inset) and iOS (pixel ratio 3, 34px inset)

  It checks there is no overflow, the bar is 56px tall, 16px side margins are kept, the bar clears
  the system inset, each tab is at least 48px wide, and the iOS and Android geometry is identical.
- **It found one bug:** at 2x system text, the 48px tab overflowed by 2px. Labels are now capped at
  1.6x (`MediaQuery.withClampedTextScaling`), the same way iOS and Material tab bars cap theirs.
- **`lens.frag` OpenGL ES flip** is now guarded by `IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED`. Engines
  after 3.44 stop flipping the framebuffer, and without the guard the refraction would show upside
  down on Vulkan-less phones.
- **Renderers:**

  | Device | Renderer | Lens |
  |---|---|---|
  | iOS | Impeller, Metal | Shader |
  | Android with Vulkan | Impeller, Vulkan | Shader |
  | Older Android without Vulkan | Impeller, OpenGL ES | Shader (Y-flip) |
  | Windows (no Impeller opt-in in the runner) | Skia | `RawMagnifier` fallback; the shader is never loaded |

- **Builds:** `flutter build windows --debug` and `flutter build apk --debug` both succeed; the
  shader compiles for every target. All 247 tests pass.
