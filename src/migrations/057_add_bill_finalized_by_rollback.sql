-- Drops what migration 057 added. "Billed by" falls back to the bill's creator.
IF EXISTS (
  SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bills_finalized_by_user'
)
  ALTER TABLE bills DROP CONSTRAINT FK_bills_finalized_by_user
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'finalized_by_user_id'
)
  ALTER TABLE bills DROP COLUMN finalized_by_user_id
GO
