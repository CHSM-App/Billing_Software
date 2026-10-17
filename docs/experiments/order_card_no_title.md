# Tweak: order card without the "Order" title and cart icon

Status: **trial**, unstaged. It sits on top of `price_lists.md` (same file, `home_screen.dart`).
To undo only this tweak, run from the repo root:

```sh
git apply -R --check docs/experiments/order_card_no_title.patch   # preview
git apply -R docs/experiments/order_card_no_title.patch
```

The patch was built from snapshot `f6744f8504aaffa62a8c5206477e48b08347a0ae` (2026-10-17) and is
the only copy, so keep it. If you also undo price lists, undo this one first.

## Change (`home_screen.dart`, order-card header)

- Removed:
  - the gradient cart icon tile
  - the "Order" title
- The item-count badge now leads the row.
- The price-list chip, preview and clear icons stay on the right.
- A 36px strut keeps the header height when the cart is empty. The icon used to set that height.
- The `billingOrder` string is still in the .arb files, but no code uses it now.
