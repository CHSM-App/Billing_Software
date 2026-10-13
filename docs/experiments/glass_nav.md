# Experiment: frosted-glass floating bottom nav

Status: **trial** — not committed. Undo with `glass_nav.patch` (below).
Applies to narrow (phone) layouts only; the wide (>= 720px) rail layout is untouched.

## Undo

From the repo root:

```sh
git apply -R --index docs/experiments/glass_nav.patch   # restores the old flat bar
```

Keep this folder until you're sure — it is the only copy of the patch.
If the scroll experiment (`scroll_hide.md`, unstaged) is still applied, undo that one FIRST —
it builds on this bar, and `--index` refuses files whose working copy differs from the index.
`git apply -R --check docs/experiments/glass_nav.patch` previews without changing anything.
The patch holds ONLY the nav hunks, so the other staged work (print logo, l10n,
settings screen, etc.) is left alone. If you edit any of these files before undoing,
the patch may need `--3way`. Re-apply later with `git apply --index docs/experiments/glass_nav.patch`.

## What changed (13 files)

| File | Change |
|---|---|
| `frontend/lib/widgets/bottom_nav_bar.dart` | Rewritten: flat Row → floating glass capsule (blur, shadow, spring-sliding pill, thumb drag with haptics). Adds `AppBottomNavBar.fabLift()`. |
| `frontend/lib/screens/main_shell.dart` | Scaffold `extendBody: true` so pages paint under the bar (needed for the blur to see them). Bottom area becomes a Stack: soft dark fade + 16/16/16/8 margin around the capsule. |
| `frontend/lib/screens/{credit,kitchen,online_orders,open_drafts,settings}_screen.dart` | List/scroll bottom padding `+ MediaQuery.paddingOf(context).bottom` so the last row scrolls above the bar. |
| `frontend/lib/screens/home_screen.dart` | Same padding for the Billing item table + cart bar raised above the capsule; auto-scroll math gets `bottomInset`. |
| `frontend/lib/widgets/category_tree_list.dart` | Same padding + `bottomInset` in `settledMaxScroll`. |
| `frontend/lib/screens/{items,orders,tables}_screen.dart` | FAB wrapped in `Padding(bottom: AppBottomNavBar.fabLift(context))` — Scaffold only lifts FABs past the system inset, not our bar. |
| `frontend/test/widgets/bottom_nav_bar_test.dart` | New: tap routing + blur present + badge; drag-to-select (+ its haptics); quick tap mid-slide. |

## How it works

- **Blur / background:** `extendBody` makes the tab content paint behind the bar, so the
  `BackdropFilter(ImageFilter.blur(σ18))` inside a `ClipRRect` blurs exactly the capsule area.
  Fill is `AppColors.surface` @ 75% with a white @ 60% rim; icons/labels are the filter's
  child, so they stay sharp. The Scaffold adds the bar height to the body's `MediaQuery.padding`,
  which is what the per-screen padding reads.
- **Shadow:** two `BoxShadow`s (textPrimary @16% blur 24 y+8, @6% blur 4 y+1) on a
  `DecoratedBox` *outside* the clip so they aren't cut off. Plus a full-width fade
  (0 → 10% → 28% textPrimary) behind the capsule, pointer-transparent.
- **Sliding pill:** one unbounded `AnimationController` holds the position in tab units.
  Tab change → `SpringSimulation` (stiffness 520, damping 0.86) from the *current* position and
  velocity, so rapid taps glide instead of restarting. Slot width = measured width / tab count.
  Icon/label colour and weight lerp with pill proximity. Reduced motion → jump, no slide.
  Selection still goes through the shell's existing `_onNav`; the IndexedStack keeps tab state.
- **Haptics (thumb drag only):** a light `selectionClick` each time the pill crosses onto another
  tab while dragged, and a `lightImpact` when the thumb lifts on a different tab than before.
- **Safe areas:** the capsule sits in `SafeArea(bottom: !connectivityBarVisible)`, which covers
  the iOS home indicator and Android gesture/3-button insets; no new system bar is drawn.

## Tuning knobs (all in `bottom_nav_bar.dart` unless noted)

- Blur `sigmaX/Y: 18` — drop to ~10, or replace with a solid ~92% fill, if low-end Android stutters.
- Fill alpha `0.75` — raise to make it more opaque/readable, lower for more glass.
- Pill `AppColors.primary` @ `0.18`.
- Spring `stiffness: 520, ratio: 0.86` — lower ratio = more bounce.
- Bottom fade colours in `main_shell.dart` `_buildBottomNav` — delete the `Positioned.fill` to remove it.
- Thumb dragging: the `onHorizontalDrag*` handlers — remove them for tap-only.
- Thumb-drag haptics in `_dragTo` / `_dragEnd`: `selectionClick` per tab crossed, `lightImpact` on
  release onto a new tab. Plain taps have none (add `HapticFeedback.selectionClick()` in `onTap`).

## Verified (2026-10-13)

- `flutter analyze`: no issues in the changed files (13 pre-existing issues elsewhere).
- `flutter test`: all 241 pass, including the 3 nav tests.
- `flutter build apk --debug`: builds. iOS not built (Windows host).
- **Not verified on a real device:** blur look, FPS on low-end Android, iOS home indicator
  spacing, and list padding while the keyboard is open (the body keeps the bar's padding
  even though the keyboard covers the bar).
