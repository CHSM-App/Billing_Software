# Experiment: price-list editor in two columns with row lines

Status: **trial**, unstaged. To undo only this experiment, run from the repo root:

```sh
git apply -R --check docs/experiments/price_list_two_columns.patch   # preview
git apply -R docs/experiments/price_list_two_columns.patch
```

The patch was built on 2026-11-02 against `59ae6963` and touches only
`frontend/lib/screens/price_lists_screen.dart`. It is the only copy, so keep it.

## Change

- Price-list editor (Settings → Price lists → a list): the item rows are laid out two per row
  when the screen is at least 600px wide (Windows, tablets). Phones narrower than that keep one
  column, because the 110px ₹ field would crush the item name in half a phone width.
- A light-grey (`AppColors.border`) horizontal line runs under every row and above the first one,
  so the items read as a table.
- The per-item tile (name, default price, ₹ field) is unchanged and moved into `_priceTile`.
- The price-lists overview screen (the list of lists) is unchanged.
