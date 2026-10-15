# Tweak: no liquid-glass lens on Android

Status: **trial**, unstaged. It sits on top of `nav_morph.md` and `scroll_hide_speed.md`.

Undo just this tweak from the repo root:

```sh
git apply -R docs/experiments/android_no_lens.patch
```

If you remove the others too, undo them in this order: this patch, then `scroll_hide_speed.patch`,
then `nav_morph.patch`. The chain was checked on 2026-10-15.

## Why

On low-powered Android phones, tab changes lagged because of the lens. Both forms of it, the
shader and the `RawMagnifier` fallback, add a second full-screen backdrop pass on every frame of
the move.

## Change (`bottom_nav_bar.dart`)

- `_lensEnabled` is `defaultTargetPlatform != TargetPlatform.android`.
- On Android:
  - The lens layer (shader or `RawMagnifier`) is never built.
  - `lens.frag` is never loaded.
  - The pill keeps its indigo tint while it moves. On iOS it fades to clear glass under the lens.
- Android keeps everything else:
  - the frosted bar with its blur
  - the pill sliding on the spring, with its stretch and swell
  - the bar growing slightly during a tab change
  - press and drag, with haptics
  - scroll-hide and badges
- iOS and desktop are unchanged.

## Test

`highlight swells while sliding (lens on iOS only), settles` runs on both iOS and Android
(`TargetPlatformVariant`):

- iOS: the lens is present mid-move.
- Android: there is no lens, but the pill still stretches and settles, and the bar still grows.

## Verified (2026-10-15)

- `flutter analyze` on both files: no issues.
- Full `flutter test`: all 251 tests pass.
- Not checked on a device.
