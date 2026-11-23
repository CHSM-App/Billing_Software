-- =============================================================================
-- Migration 033: add_price_inclusive_tax
-- =============================================================================
-- Until now every items.price was treated as tax-EXCLUSIVE: billing charged
-- qty x price and added GST on top. That is wrong for MRP-priced goods — a
-- packaged snack marked 20 is 20 at the counter, GST included, not 20 + 5%.
--
-- This flag says how to read the price stored on the item (and on its variants,
-- which inherit the parent's flag — a size is the same product at a different
-- quantity, so its price is quoted the same way):
--   0 (default) — price is NET; tax is added on top.        20 -> 21.00 @5%
--   1           — price is GROSS; tax is already inside it.  20 -> 20.00 @5%
--
-- For an inclusive item, billing back-calculates the net rate as
--     net = gross / (1 + rate/100)
-- and stores THAT in bill_items.unit_price. Everything downstream (subtotal,
-- discount-on-net, tax_amount, round-off, the GST tax invoice) therefore keeps
-- working unchanged and the printed invoice shows a proper net rate + separate
-- GST line, while qty x gross still ends up as the customer's total.
--
-- DEFAULT 0 is deliberate: it preserves the existing behaviour of every row
-- already in the table, so this migration cannot change any current bill total.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE items
    ADD price_inclusive_tax BIT NOT NULL
        CONSTRAINT DF_items_price_inclusive_tax DEFAULT 0
GO

-- bill_items.unit_price must widen from DECIMAL(10,2) to hold a back-calculated
-- net rate. An MRP of 20.00 at 5% has a net rate of 19.047619...; stored at 2dp
-- it becomes 19.05, and 19.05 x 1.05 = 20.0025 — so a receipt that recomputes
-- rate x qty x (1+rate) would no longer reconcile against the MRP the customer
-- actually paid. 4dp keeps the line reconcilable; the printed rate is still
-- formatted to 2dp for display.
--
-- Widening precision/scale is a metadata-only change for existing rows: every
-- current value is exactly representable, so no bill total moves.
ALTER TABLE bill_items
    ALTER COLUMN unit_price DECIMAL(12,4) NOT NULL
GO
