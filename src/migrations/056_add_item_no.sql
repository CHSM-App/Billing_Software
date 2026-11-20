-- =============================================================================
-- Migration 056: items.item_no + businesses.show_item_no — identify items by number
--
-- Some shops know their items by a number ("101" = Masala Dosa). item_no is
-- optional free text per item; the cashier can search billing by it. Uniqueness
-- among active items is enforced in routes/items.js (an index would block
-- reusing the number of a soft-deleted item).
--
-- show_item_no is the shop-wide opt-in to show it on the billing page as
-- "(101) Masala Dosa". Off by default, so nothing changes for existing shops.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('items') AND name = 'item_no'
)
  ALTER TABLE items ADD item_no NVARCHAR(30) NULL
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'show_item_no'
)
  ALTER TABLE businesses ADD show_item_no BIT NOT NULL CONSTRAINT DF_businesses_show_item_no DEFAULT 0
GO
