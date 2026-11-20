-- Drops what migration 075 added. Sizes go back to their item's unit; stock is
-- unaffected.
IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('item_variants') AND name = 'unit'
)
  ALTER TABLE item_variants DROP COLUMN unit
GO
