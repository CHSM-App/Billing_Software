# Feature: price lists (Party, Wholesale, AC section …)

Status: **trial**, unstaged. It sits on top of the other uncommitted work in the tree (the
open-orders kitchen view, the item packs and the cashier full name) and is kept separate from it.
`price_lists.patch` holds **only** this feature. It was built against the working-tree snapshot
`46558cb862868ef2cc5ed9735f563452b893e274` (`git stash create`, taken 2026-10-17 before the first edit).

## Undo

Do these steps in order. This patch is the only copy, so keep it.

1. **Code**, from the repo root:

   ```sh
   git apply -R --check docs/experiments/price_lists.patch   # preview, changes nothing
   git apply -R docs/experiments/price_lists.patch
   ```

   This reverts the edits and deletes the new files. Other experiments are left alone.

2. **Server**: redeploy the backend.

3. **Database**, only *after* step 2. If you roll back the database while the new backend is still
   live, that backend breaks.

   ```sh
   cd backend
   npm run migrate:status   # confirm 059 is the latest applied
   npm run migrate:down     # runs 059_add_price_lists_rollback.sql
   ```

   This drops `bills.price_list_id`, then `price_list_items`, then `price_lists`.
   - Data effect: the price lists are deleted.
   - **Saved bills keep their amounts**, because list prices were stored as ordinary line prices
     (`unit_price`). Only the "which list" tag is lost.
   - Skipping this step is harmless: the old code never reads those tables or that column.

4. **Devices**: nothing to do. The cached `price_lists_<businessId>` key in SharedPreferences is
   simply ignored.

## What it does

- **Owner, Settings → Price lists**:
  - Create a list: a name, an optional "% on every price" (e.g. +10, −5, kept to paise), and
    optional fixed prices per item or per size.
  - A fixed price wins over the %. A size is priced on its own and never borrows its item's fixed
    price.
- **Billing**:
  - A "Default ▾" chip in the order-card header (owner and cashier only; hidden until a list
    exists). Picking a list re-prices **every** line, including any hand-edited price, and the
    item grid shows list prices too.
  - Items added afterwards get list prices. A manual edit made after picking still wins for that
    line.
  - The list is per bill: clearing or settling goes back to Default. A held draft stores
    `price_list_id` and reopens on its list. Lines a waiter added at catalog price take the list
    price on reopen.
- **No new pricing code**: list prices travel as the existing per-line `price_override`, so GST/MRP
  maths, offline sync, receipts and reports are untouched.
- QR, online store and kitchen orders always use default prices.

## Files

- **Backend**:
  - migration `059_add_price_lists` (+ rollback), `schema.sql`
  - new `routes/price_lists.js` (GET for all roles; POST/PUT/DELETE owner only, soft delete)
  - `server.js` mount
  - `routes/bills.js`: `price_list_id` on POST and update-items, gated by `canReprice`;
    returned in the bill and drafts SELECTs
- **Frontend**:
  - `models.dart` (`PriceList`, `Bill.priceListId`)
  - `api.dart`, `storage.dart` (offline cache)
  - new `providers/price_lists_provider.dart`, `cart_provider.dart`
    (`applyPriceList`, `addItem`, `clear`, `loadFromBill`)
  - `home_screen.dart` (chip, grid price, payloads)
  - new `screens/price_lists_screen.dart`, `settings_screen.dart` tile
  - l10n (en + mr, regenerated)
- **Tests**:
  - `tests/routes/price_lists.test.js`, plus a `price_list_id` block in `bills.test.js`
  - `test/providers/price_lists_test.dart`

## Known corners (ponytail)

- An **offline** draft doesn't store `price_list_id`, because that would need a sqlite schema bump.
  It keeps its prices, but reopens showing Default.
- If the price lists haven't loaded yet when a draft is reopened, it shows Default too, with the
  prices kept.
- Other devices see a new or edited list the next time the app loads lists. There is no realtime
  push.
