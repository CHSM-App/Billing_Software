-- Drops what migration 079 added. Batch history and every sale's batch link
-- are lost; stock totals are untouched (they never depended on batches).
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('bill_items') AND name = 'batch_id')
  ALTER TABLE bill_items DROP COLUMN batch_id
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('vendor_bill_items') AND name = 'batch_id')
  ALTER TABLE vendor_bill_items DROP COLUMN batch_id
GO

IF OBJECT_ID('stock_batch_allocations') IS NOT NULL DROP TABLE stock_batch_allocations
GO

IF OBJECT_ID('stock_batches') IS NOT NULL DROP TABLE stock_batches
GO

-- The auto-named DEFAULT constraint must go before its column.
DECLARE @df NVARCHAR(200)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('businesses')
  AND c.name = 'batch_tracking_enabled'
IF @df IS NOT NULL
  EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df)
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('businesses') AND name = 'batch_tracking_enabled')
  ALTER TABLE businesses DROP COLUMN batch_tracking_enabled
GO
