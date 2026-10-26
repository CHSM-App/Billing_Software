# Experiment: units on the printed bill

Status: **trial**, unstaged. It sits on top of the short-unit names (`unitShort()` in
`models.dart`), which are not part of this experiment and stay when it is undone.
To undo only this experiment, run from the repo root:

```sh
git apply -R --check docs/experiments/receipt_units.patch   # preview
git apply -R docs/experiments/receipt_units.patch
```

The patch was built on 2026-10-24 against uncommitted work on `main` (base `37eda1a2`). It is the
only copy, so keep it.

## Change

- The receipt's Qty column prints the short unit: `2 kg`, `1.5 L`, `21 pkt`. Lines whose item
  is not in the catalog (deleted items, custom lines) print the bare number as before.
- Applies to thermal receipts (text and raster paths, plus the column-fit sizing) and to the
  A4/A5 PDF invoice.
- Bill lines store no unit, so the unit comes from the live item list. `catalogUnits` in
  `models.dart` is refreshed by `ItemsNotifier` (`listenSelf`) and read by `receiptQty()`.

## Things to check

- On 58 mm paper the Qty column widens and the item-name column shrinks, so long names
  wrap onto more lines.
- A reprint shows the item's current unit, not the unit it had when the bill was made.

## If it is kept

Store the unit on `bill_items` on the server, so reprints and other devices don't rely on
the catalog, then drop `catalogUnits`.
