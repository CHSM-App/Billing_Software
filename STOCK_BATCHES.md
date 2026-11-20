# Stock Batches

Purchase cost per lot, so the shop sees real profit. Each purchase line of a
tracked item or size puts its stock into a **batch** with a known unit cost.
Each sale takes stock from batches, and reports subtract what the goods cost.

**Off by default.** An owner turns on Settings → "Maintain batches", which
only shows while inventory is on. While it's off, purchases, sales and the
item list behave exactly as before.

An earlier attempt (`9994b00a`) was reverted in Oct 2026, mainly because it
made the cashier pick a batch on every add or scan. This design is new; it
uses that commit only as a reference.

## How it works

- `items.stock_quantity` / `item_variants.stock_quantity` stay the **total and
  source of truth**. Batches only split it:
  `opening (uncosted) stock = stock_quantity − Σ open qty_remaining`.
- **Purchase** (`routes/vendor_bills.js`, `batches.receive`):
  - Each linked item or size line goes into a **new** batch (`B-0001`, with an
    optional supplier lot no.), or **tops up** an existing batch of the same
    item. Top-ups are allowed only at the same unit cost; otherwise it's a 400.
  - Unit cost = line net × bill-discount factor, plus GST when the shop can't
    claim it back, ÷ (qty + free).
  - Editing or deleting a purchase takes back what it received
    (`unreceive`). A batch this bill opened takes the edited cost. Empty
    batches that never sold are deleted (`dropEmpty`).
- **Sale** (`routes/bills.js`, `batches.allocate`):
  - After each line's stock decrement, stock is taken from the line's
    preferred batch (`bill_items.batch_id`, the cashier's pick), then oldest
    first, then opening stock.
  - A sale is never refused because of batches.
  - Allocations are keyed by **bill** (`stock_batch_allocations`), because
    update-items re-inserts every line. Void and update-items give them back
    (`returnBill`).
- **Manual stock correction** below what the batches hold writes the
  difference off the oldest batches (`qty_lost`, `trimExcess`).
- **Gating:** creating batch data needs the switch on. Reversals always run
  when there's batch data to reverse. Switching on runs `reconcile` to trim
  batches that went stale while it was off.

## Where it shows

- **Cart:** under each line with batches, e.g. "B-0001 · Cost ₹50", or a range
  when the line runs into a second batch. It's red when the line sells below
  cost. Tapping it picks the batch, with "Auto (oldest first)" as the default.
  The pick round-trips through held bills and offline sync.
- **Purchase form:** a "Batch: New ▾" chip on linked lines, to choose a new
  batch (with a lot no.) or top up an existing one.
- **Purchases → Batches** (owner): Open and Settled tabs. Each batch shows
  bought / sold / left, written off, sales, cost, and profit or loss.
- **Reports → Profit:** costed sales, cost of goods and gross profit
  (pre-tax). Sales without a known cost are named separately.
  `net_profit` keeps its old meaning.

## Data (migration 079)

- `businesses.batch_tracking_enabled`.
- `stock_batches`: `qty_received`, `qty_sold` and `qty_lost`, with
  `qty_remaining` computed from them.
- `stock_batch_allocations`.
- `vendor_bill_items.batch_id`, `bill_items.batch_id`.

## Not covered (v1)

- Raw materials and restaurant recipes (food cost).
- Freight and other-charges lines spread into item cost.
- Expiry dates.
- The cost line in the cart while offline: the offline item cache has no
  batches.
- Write-offs in the period summary: they have no date, so they're shown per
  batch only.
- Known, separate bug: online and QR orders insert lines without taking stock,
  but void and update-items give stock back for them. That inflates opening
  stock; it doesn't break batches.
