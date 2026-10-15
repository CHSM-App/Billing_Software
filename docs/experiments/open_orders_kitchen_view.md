# Experiment: Open Orders shown like the Kitchen page

Status: **trial**. The changes are left **unstaged** and are separate from `nav_morph` (no shared
files). To undo only this experiment, run this from the repo root:

```sh
git apply -R docs/experiments/open_orders_kitchen_view.patch
```

To preview the undo first, run `git apply -R --check docs/experiments/open_orders_kitchen_view.patch`.
This patch is the only copy, so keep it.

## Why

Open Orders and Kitchen both list every draft bill with its dishes. The idea is to make Open Orders
do the floor staff's half of the Kitchen page, then decide whether the Kitchen tab is still needed for
non-chef roles. The **Kitchen page is not changed** (only some of its widgets became public for reuse).

## What changed

- **Order:** oldest first, with queue numbers (#1 = waiting longest). The newest order goes last.
  The sort happens on the client, so `/bills/drafts` and its other users are unchanged.
- **Cards:** a masonry layout using the Kitchen page's `kitchenMasonry`. Each card shows the queue
  number, the name, the order's age, the total, the item count, a green "🛎 N" ready badge, and the
  "Paid online" line. The card turns green when every dish is ready or served.
- **Taps:**
  - **Header (anywhere) → fold or unfold** the dishes, with an animation. Cards start folded on
    phones (<720px) and open on wider screens.
  - **"Open bill" button** under the dishes (shown while the card is open) → opens it in billing.
  - **Short swipe right** on any card, folded or open → opens it in billing. Same feel as the
    billing page swipe-to-add: max 72px travel, fires past 56px, springs back. A haptic tick when
    it crosses the trigger point, a light impact when it opens.
  - **Green (ready) dish → mark it served.** Tapping it again undoes this. It uses the same
    `PUT /kitchen/items/:id` and role rules as the Kitchen page.
- New string `openOrdersOpenBill` (en + mr) and the regenerated `app_localizations*.dart`.
- **Ready to serve toggle** in the Orders header (restaurants only). It shows the live count and
  filters Open Orders down to the ready dishes. The cards are forced open while it is on.
- **Live updates:** the shell now also refreshes open drafts on the realtime `kitchen` event. The chef
  ticking a dish shows up on Orders without a manual refresh.
- No backend change. `/bills/drafts` already returned `kitchen_status`, and `BillItem` now keeps it.

## Not done (yet)

- Order notes on the cards: the `Bill` model has no `notes` field.
- The Orders nav badge is still the open-order count.
