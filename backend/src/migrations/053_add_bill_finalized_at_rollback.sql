-- Drops what migration 053 added. Bills fall back to created_at as their date.
IF EXISTS (
  SELECT 1 FROM sys.indexes
  WHERE object_id = OBJECT_ID('bills') AND name = 'IX_bills_business_finalized'
)
  DROP INDEX IX_bills_business_finalized ON bills
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'finalized_at'
)
  ALTER TABLE bills DROP COLUMN finalized_at
GO
