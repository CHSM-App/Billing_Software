-- Drops what migration 059 added. Price lists are lost; saved bills keep their
-- amounts (list prices were stored as ordinary line prices).
IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'price_list_id'
)
  ALTER TABLE bills DROP COLUMN price_list_id
GO

IF OBJECT_ID('price_list_items') IS NOT NULL
  DROP TABLE price_list_items
GO

IF OBJECT_ID('price_lists') IS NOT NULL
  DROP TABLE price_lists
GO
