-- =============================================================================
-- Migration 036: add_item_major_category
-- =============================================================================
-- Items have carried exactly one free-text `category`. A long restaurant menu
-- therefore lists "Chinese Main Course", "Chinese Starters", "Fish", "Soups"
-- all at the same level, with no way to narrow it.
--
-- This adds the coarser level above it:
--   major_category — the group  ("Chinese", "Indian", "Bar")
--   category       — the subcategory ("Chinese Starters")
--
-- Both stay plain free text with no categories table: a category exists only
-- for as long as some active item carries that exact string, which is how
-- `category` has always worked and what the app derives its chip lists from.
--
-- NULL-able with no backfill is deliberate. `category` is NOT renamed and its
-- meaning is unchanged, so every existing row keeps billing, grouping and
-- printing exactly as it does today; a business that never fills the new field
-- sees no behavioural change at all. Nothing here touches bills/bill_items —
-- bill lines snapshot item_name/hsn_code and have never stored a category — so
-- no bill total, receipt or GST return can move.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE items
    ADD major_category NVARCHAR(100) NULL
GO
