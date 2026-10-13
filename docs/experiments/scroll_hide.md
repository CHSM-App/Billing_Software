# Experiment: YouTube-style scroll (hide bottom nav, fold app bar)

Status: **trial** — left **unstaged** on purpose, on top of the staged glass-nav
experiment (`glass_nav.md`). Undo this one without touching anything else:

```sh
git apply -R docs/experiments/scroll_hide.patch     # from the repo root
```

`git apply -R --check docs/experiments/scroll_hide.patch` previews. Keep this folder until
you've decided — the patch is the only copy. Re-apply later with `git apply docs/experiments/scroll_hide.patch`.
Undo this BEFORE the glass-nav patch if you remove both (it builds on the glass bar's code).

## Behaviour

| Action | Billing app bar | Major / category strip | Bottom nav (all tabs) |
|---|---|---|---|
| Drag up (scroll down) | Folds away under the finger first, then the list scrolls; a fling keeps folding at the list's speed | Stays pinned under the status bar | Slides off-screen after 24px |
| Drag down (scroll up) | Comes back first, then the list scrolls | Pinned | Slides back after 24px |
| Stop | If half-folded, finishes the way you were scrolling (260ms easeOutCubic) | Pinned | Stays as is |
| Reach top (fling / jump) | Animates fully back | Pinned | Shown |
| Switch tab | Billing keeps its own state | — | Always shown |
| Back from a pushed page (no bottom bar) | Keeps its own state | — | Shown again (already visible while the page slides away) |
| Category tap / filter / search typing | Unchanged (programmatic scroll) | — | Unchanged |
| Search open | Pinned open | — | — |
| Wide (>= 720px) layout | Never folds | — | No bottom nav; nothing hides |

**Items page** works the same way, but the folding header is app bar + Items/Raw tab bar +
search box, folding as ONE block (app bar → tabs → search slide up in turn), and the major/minor strip stays pinned. It stays open while
the keyboard is up, and opens again when switching to the Raw-materials tab (which doesn't fold).
The **Add Item / Add Raw Material** button slides down and fades out together with the bottom
nav, and doesn't take taps while hidden.

**Orders and Kitchen pages:** only the title/actions row folds; the sub-tab row (Tables / Open /
Online / Credit, or Pending / Completed) stays pinned, like the category strip elsewhere. It
opens again on switching sub-tab. Orders keeps it open while its search field is in use. Their
lists live in other widgets, so `FoldingHeader.wrap()` hands down the physics through a
`ScrollConfiguration` instead of editing each list.

## Files (9)

| File | Change |
|---|---|
| `frontend/lib/widgets/floating_bar_physics.dart` | New. `FoldingHeader`: owns the 0..1 controller, the list physics and the scroll handler (fling carries the fold, snap on stop, open at top); `wrap()` injects the physics via `ScrollConfiguration`. Physics ignores horizontal scrollables. `FloatingBarPhysics`: spends a finger drag on the header first. `FoldAway` (+ `FoldAway.slice`): clips a header piece; slices make several pieces fold as one block. |
| `frontend/lib/screens/home_screen.dart` | `_header = FoldingHeader(...)`. Save Order / Cart row follows `AppBottomNavBar.shown` (drops to the system inset when the nav hides). App bar in `FoldAway` under a fixed status-bar band. Items panel wrapped in `NotificationListener(_header.onScroll)`; both item scroll views use `_header.physics`. Search button reopens the bar. `_ExcelItemTable` takes a `physics` param. |
| `frontend/lib/screens/items_screen.dart` | `_header = FoldingHeader(...)` (extent = 51 + tab bar 48 if shown + search 50). App bar + tab bar and the search box are two `FoldAway.slice`s of the same fold. Status-bar band. Listener on the list; header reopens on tab change. All 3 list variants use the physics. `SingleTicker…` → `TickerProviderStateMixin`. FAB in `HidesWithNavBar(drop: 2)`. |
| `frontend/lib/screens/orders_screen.dart` | `_header = FoldingHeader(extent 50)`. Status-bar band; `ShellAppBar` (with its TabBar) in a `FoldAway` whose Tween keeps the tab row + divider (49 of 99 px). `TabBarView` in `_header.wrap(...)`. Opens on sub-tab change and when search opens. |
| `frontend/lib/screens/kitchen_screen.dart` | Same as Orders. `SingleTicker…` → `TickerProviderStateMixin` (second controller). Opens on tab change (`_tabController.addListener(_header.show)`). |
| `frontend/lib/widgets/category_tree_list.dart` | Optional `physics` param (default unchanged). |
| `frontend/lib/widgets/bottom_nav_bar.dart` | `AppBottomNavBar.shown` (static `ValueNotifier`) + `HidesWithNavBar` (slide + fade + ignore taps). |
| `frontend/lib/screens/main_shell.dart` | `NotificationListener` around the tab `IndexedStack` → `_onPageScroll` drives `AppBottomNavBar.shown`; bottom area in `HidesWithNavBar`. Reset to shown on tab change, on wide layouts, and when a page pushed over the shell pops (`ModalRoute.isCurrentOf` flips back to true). |
| `frontend/test/widgets/floating_bar_physics_test.dart` | New: fold-first / remainder scrolls / pinned when disabled; a flick folds the WHOLE two-piece header and flinging back to the top opens it; `wrap()`: a tab list with its own physics still folds the header, a sideways tab swipe does not. |

## How it works

- **Why not slivers:** the Billing jump-to-category and scroll-spy math uses exact row offsets
  that start at 0, and the strip is 1 or 2 rows tall depending on width. Moving the app bar and
  strip into the table's `CustomScrollView` would shift every offset. Instead the strip stays
  where it already was (above the list = pinned), and the app bar *above* it folds by soaking up
  drag distance in `ScrollPhysics.applyPhysicsToUserOffset` — the content tracks the finger
  exactly, like a floating `SliverAppBar`. Only one strip, one selection state; untouched.
- **Bottom nav:** `UserScrollNotification` marks a finger-driven scroll (drag + its fling);
  `ScrollUpdateNotification` deltas accumulate per direction; ±24px toggles a `ValueNotifier`.
  Only vertical scrolls count (chip strips ignored); iOS bounce (`outOfRange`) ignored; at the top
  (`extentBefore <= 0`) always shown. Only the bar rebuilds — no shell `setState`.
- **Glass preserved:** the whole bottom area (fade, blur capsule, highlight, connectivity strip)
  moves as one `AnimatedSlide` by its own height + fades, 220ms easeOutCubic, zero with reduced
  motion. Layout height is unchanged, so list bottom padding doesn't jump.

## Tuning knobs

- `_navToggleAfter = 24` in `main_shell.dart` — higher = less eager to hide/show.
- Slide `220ms easeOutCubic` in `_buildBottomNav`.
- `extent: () => 51` in `home_screen.dart`, and the `51 + 48 + 50` sum in `items_screen.dart` —
  must match the real header heights or rows drift slightly against the finger.
- `drop: 2` on the Items FAB — how far it slides (in its own heights).
- `FoldingHeader` 260ms easeOutCubic — snap / reveal speed.

## Known limits

- Bottom nav: the dark fade and the offline (connectivity) strip hide with the bar.
- Billing: while the bar is coming back, the list doesn't move — that's what makes rows track
  the finger, but it means 51px of drag before the list scrolls up.
- Hidden nav keeps its padding at the end of lists (no reclaimed space at the very bottom).
- Items FAB hides with the nav; Billing Save Order / Cart row glides down to 16px above the
  system inset when the nav hides (`AnimatedPositioned`, 220ms). The Orders/Tables FABs
  stay lifted over the gap (wrap them in `HidesWithNavBar` to match).
- Items page: `RawMaterialsTab` doesn't fold the header.
- Orders/Kitchen: no depth filter on scroll notifications (their lists sit inside a horizontal
  PageView), so a vertical list nested inside another vertical list would fold it twice as fast.
- Bottom nav reacts to every tab's vertical lists; a vertical list nested in another vertical
  list would feed it twice (none seen in the tab screens).

## Verified (2026-10-13)

- `flutter analyze` on the 9 files: no new issues (2 old ones in items_screen.dart).
- Full `flutter test` + `flutter build apk --debug`: see chat.
- **Not verified on a device:** feel of the fold, nav slide, iOS bounce, Android gesture nav.
