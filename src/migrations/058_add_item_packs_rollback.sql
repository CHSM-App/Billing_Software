-- Drops what migration 058 added. Pack settings are lost; stock is unaffected.
IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('item_variants') AND name = 'pack_unit'
)
  ALTER TABLE item_variants DROP COLUMN pack_unit, pack_size
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('items') AND name = 'pack_unit'
)
  ALTER TABLE items DROP COLUMN pack_unit, pack_size
GO
