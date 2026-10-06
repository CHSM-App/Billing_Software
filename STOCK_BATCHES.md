# Stock Batches — paused feature

Batch-wise stock: each purchase (vendor bill) line creates a stock batch with
its own purchase cost and optional batch/lot number. The cashier picks the
batch while billing, the bill line snapshots that batch's cost, and reports
compute cost of goods and real profit.

**Status:** built as WIP in commit `9994b00a` ("WIP: stock batches (paused)"),
then **reverted before deploy** (Oct 2026). None of it is in the code or the
database now.

---

## How to bring it back

```bash
git show 9994b00a --stat              # everything the feature touched
git cherry-pick 9994b00a              # or: git revert <the revert commit>
```

Then, before shipping, fix everything under **Must fix before release** below.

### Database

The feature used migrations `044_add_stock_batches` and
`045_vendor_bill_batch_no`. Both were deleted by the revert, and 044 was rolled
back on `vittam_test_db`. 045 was never applied anywhere.

When restoring:
- If migrations 044+ have since been used by other features, **renumber** the
  batch migrations to the next free numbers rather than reusing 044/045.
- Fold 045 into 044 (create `vendor_bills.batch_no` directly; never add
  `vendor_bill_items.batch_no`). 045 only existed to move that column.
- To roll back exactly one migration use `node src/migrate.js down <prev>`, or
  bare `down` (fixed to roll back only the last one — it used to roll back
  **everything**).

### Offline SQLite (frontend)

`offline_service_native.dart` is at **version 13**. v13 was the batch build
(added `batches_json` to `cached_items` / `cached_variants`); after the revert
v13 is a no-op kept so devices never downgrade. Re-enabling must add the
column in a **v14** step (guard with `PRAGMA table_info`, as the WIP did).

---

## Design (as built in 9994b00a)

- `items.stock_quantity` / `item_variants.stock_quantity` stay the **total and
  source of truth**. Batches only split it.
- `opening stock = stock_quantity − SUM(stock_batches.qty_remaining)` — stock
  from before batches or added by hand; no known cost.
- `stock_batches` table: `item_id` XOR `variant_id`, `vendor_bill_id`,
  `batch_no`, `unit_cost` (net, after bill-level discount), `qty_received`,
  `qty_remaining >= 0`, `received_date`. No FK to vendor_bills (MSSQL cascade
  path conflict) — the route deletes a bill's batches itself.
- `bill_items.batch_id` + `bill_items.unit_cost` — cost snapshot that survives
  the batch being deleted.
- Backend helper `backend/src/batches.js`:
  - `receiveBatches` — on purchase create/edit (only tracked stock, only when
    stock is applied).
  - `takeFromBatch` / `returnToBatch` — sale / void of a line with `batch_id`.
  - `trimExcess` — whenever the total drops without naming a batch (manual
    stock edit, purchase edit/delete, sale with no batch), shrink batches
    oldest-first so they never exceed the total.
- `GET /api/items` attaches open `batches` per item/size (`unit_cost` owners
  only). `GET /api/stock-batches` lists open batches oldest-first (owners).
- Reports: `cost_of_goods`, `uncosted_qty`, and `net_profit` now subtracts COGS.
- Frontend: `StockBatch` model, `CartEntry.batch` (cart key includes batch),
  `widgets/batch_picker.dart`, `screens/stock_batches_screen.dart`, batch no.
  field on the purchase form.

---

## Must fix before release

Found in review on 2026-10-06; this is why the feature was pulled.

1. **Batch number is silently dropped.** `computeTotals` in
   `routes/vendor_bills.js` doesn't carry `batch_no` through, and nothing
   reads/writes `vendor_bills.batch_no`. Decide: one batch no. per bill
   (header field, per 045) or per line — then wire it end to end.
2. **Picker on every add breaks existing users' flow.** As soon as an
   inventory-on shop records a purchase for an item that already has stock,
   that item has 2 sources (opening + batch), so every grid tap, `+`, and
   **barcode scan** opens the batch sheet. Options:
   - Per-business setting "Batch tracking", **off by default**, gating both
     `receiveBatches` and the picker. Existing users then see no change.
   - Auto-pick FIFO (oldest batch / opening first) and only show the picker on
     long-press or in the cart.
3. **New sale rejection.** A line is refused when its chosen batch is short,
   even if the total stock is enough — two counters on the same batch, or an
   offline bill synced with a stale cached `qty_remaining`. Consider falling
   back to opening stock / next batch instead of 409.
4. **Profit numbers shift.** `net_profit` subtracts COGS only for batch sales;
   opening-stock sales have no cost, so profit is a mix. Show `uncosted_qty`
   prominently or label the figure, so owners aren't misled.
5. **Cart UX changes:** one item split across several batch lines; typing a
   qty in the grid is refused when split ("edit in cart"); `−1` removes from
   the last-added line. Confirm this is acceptable.

## Safe for old users (verified in review)

- Inventory off: no batches created, no picker.
- Inventory on, no purchase bills: no batches, no picker.
- Untracked items (`stock_quantity` NULL) never get batches.
- Old app versions / QR / online orders without `batch_id` keep working
  (`trimExcess` drains the oldest batch; those lines have no cost).
