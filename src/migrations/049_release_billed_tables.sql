-- =============================================================================
-- Migration 049: release tables left in 'billed'
--
-- Settling a table's bill now frees the table straight away (routes/bills.js —
-- finalize sets 'empty'; the old "Mark as Paid / Empty" step is gone). Nothing
-- writes 'billed' any more, but tables settled BEFORE this deploy are still
-- 'billed' — and the QR order page refuses orders on a billed table
-- (public_order.js, code table_billed), so diners at those tables could not
-- order until staff opened the table by hand.
--
-- A billed table's bill is already finalized (paid or on credit), so it is
-- free: set it empty, exactly what the old manual step did. Touches only rows
-- still 'billed'; running it again is a no-op.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

UPDATE tables SET status = 'empty' WHERE status = 'billed'
GO
