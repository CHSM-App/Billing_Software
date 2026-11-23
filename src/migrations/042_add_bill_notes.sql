-- =============================================================================
-- Migration 042: add bills.notes
--
-- The customer's instruction on an online-store order ("no onions", "ring the
-- bell twice") lives in online_orders.note, and accepting the order is supposed
-- to carry it onto the bill so the kitchen card and the printed KOT can show
-- it. There was nowhere to put it: `notes` existed only on vendor_bills.
--
-- Without this column, routes/online_orders.js fails its INSERT with
-- "Invalid column name 'notes'" and NO online order can be accepted at all,
-- and routes/kitchen.js fails its SELECT, taking the whole kitchen queue with
-- it. Both changes shipped together with this migration for that reason.
--
-- Nullable with no default: a bill without a note is the normal case, and an
-- empty string would be indistinguishable from "the customer wrote nothing".
-- =============================================================================

IF COL_LENGTH('bills', 'notes') IS NULL
    ALTER TABLE bills ADD notes NVARCHAR(500) NULL
GO
