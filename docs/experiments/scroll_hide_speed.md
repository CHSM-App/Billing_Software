# Tweak: slower scroll hide/show of the bottom bar

Status: **trial**, unstaged. It sits on top of `scroll_hide.md` (committed) and `nav_morph.md`.

Undo just this tweak from the repo root:

```sh
git apply -R docs/experiments/scroll_hide_speed.patch
```

If you also want to remove the lens experiment, undo this patch FIRST and then `nav_morph.patch`.
Both touch `bottom_nav_bar.dart`. This order was checked with `git apply -R --check`.

## Change

| | Before | Now |
|---|---|---|
| Duration | 220ms | 420ms (`AppBottomNavBar.hideDuration`) |
| Curve | `easeOutCubic`, which does most of the move in the first frames | `easeInOutCubic`, which starts and ends gently (`AppBottomNavBar.hideCurve`) |

These apply to everything that rides with the bar, through one shared constant:

- the bar itself, including the glass, the lens, the fade and the offline strip (`HidesWithNavBar`)
- the Items screen's Add button (`HidesWithNavBar`)
- the Billing screen's Save Order / Cart row (`home_screen.dart`, `AnimatedPositioned`)

**Unchanged:**
- When it triggers: 24px of scroll in one direction (`_navToggleAfter` in `main_shell.dart`).
- With reduced motion turned on, it still moves instantly.

## Tuning

`hideDuration` in `bottom_nav_bar.dart`: raise it for a slower glide (for example 500), or lower it for
a faster one.

## Verified (2026-10-14)

- `flutter analyze` on both files: no issues.
- Full `flutter test`: all 250 tests pass.
- Not checked on a device.
