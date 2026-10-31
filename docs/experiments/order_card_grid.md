# Experiment: light-grey grid around order-card lines (Windows)

Status: **trial**, unstaged. To undo only this experiment, run from the repo root:

```sh
git apply -R --check docs/experiments/order_card_grid.patch   # preview
git apply -R docs/experiments/order_card_grid.patch
```

The patch was built on 2026-10-30 against uncommitted work on `main` (base `70799ccc`), on top
of the Windows order-card row (`_windowsCartRow`, per-line price-list badge). That row is not
part of this experiment and stays when it is undone. The patch is the only copy, so keep it.

## Change

- Windows only. The order card's item lines sit in one box with a light-grey (`AppColors.border`)
  outline and rounded corners. A 1px line separates each item from the next.
- The box has a 16px margin, so `_windowsCartRow` uses 10px side padding instead of 16px.

## Step 2: vertical lines (separate patch)

Added on top of step 1, with its own patch. Undo it first; step 1 stays:

```sh
git apply -R docs/experiments/order_card_grid_vertical.patch
```

- Light-grey vertical lines between the columns: name | rate | − qty + / unit | total.
  The two-line narrow layout has them on its second row only.
- Each column is now a padded cell, and the qty column has a fixed width of 150px, so the
  lines line up from row to row. `IntrinsicHeight` makes the lines run the full row height.

## Step 3: responsive tweaks (separate patch)

On top of step 2. Undo it first; steps 1–2 stay:

```sh
git apply -R docs/experiments/order_card_grid_responsive.patch
```

- Item name wraps to 2 lines before it gets "…".
- The rate is centred vertically in its cell (it sat at the top).
- Steppers are left-aligned in a 140px qty column, so they line up from row to row.
- The one-row layout starts at 600px (was 520), so names aren't squeezed beside the columns.

## Step 4: wider default card (separate patch)

On top of step 3. Undo it first; steps 1–3 stay:

```sh
git apply -R docs/experiments/order_card_grid_width.patch
```

- On Windows the order card now defaults to 640px wide (was 360), enough for the one-row grid.
  It can still be dragged, and a double-click on the divider goes back to 640.
- Windows saves the width under a new key, `billing_cart_width_win`, so a width saved for the
  old narrow card doesn't hide the new default. On a small screen the width is still clamped
  so the items panel keeps 360px.
- The item name is now centred vertically in its cell (it sat at the top).

## Step 5: no arrow, columns sized to content (separate patch)

On top of step 4. Undo it first; steps 1–4 stay:

```sh
git apply -R docs/experiments/order_card_grid_autocols.patch
```

- The ⌄ arrow is gone. Tapping the item name still opens the price/discount editor.
- The rate, qty and total columns are as wide as their widest figure across all lines
  (`_cartCols` measures them with `TextPainter`), so every row's lines still line up. The name
  column takes the rest.
- The switch to the two-line layout is now based on content: the name moves to its own line
  when the columns leave it under 160px (`_cartNameMin`). The fixed 600px threshold is gone.
- The qty width relies on the stepper's sizes (28px buttons, 36/48px field). If those change,
  update the numbers in `_cartCols`.

## Step 6: same-size steppers (separate patch)

On top of step 5. Undo it first; steps 1–5 stay:

```sh
git apply -R docs/experiments/order_card_grid_samestepper.patch
```

- The qty box was 48px for any unit other than piece (decimal quantities allowed) and 36px for
  pieces, so steppers differed between rows. In the Windows grid every row now uses the widest
  box any line needs (`_CartCols.field`, passed through `_qtyStepper` to `_CartQtyField.width`).

## Things to check

- The line editor (price / disc % / disc ₹) opens inside the box, under its row.
- On the narrow, two-line layout (card under 520px) the box takes 32px of width.
