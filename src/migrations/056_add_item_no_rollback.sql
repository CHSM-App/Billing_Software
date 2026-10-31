-- Drops what migration 056 added. Item numbers are lost.
IF EXISTS (
  SELECT 1 FROM sys.default_constraints WHERE name = 'DF_businesses_show_item_no'
)
  ALTER TABLE businesses DROP CONSTRAINT DF_businesses_show_item_no
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'show_item_no'
)
  ALTER TABLE businesses DROP COLUMN show_item_no
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('items') AND name = 'item_no'
)
  ALTER TABLE items DROP COLUMN item_no
GO
