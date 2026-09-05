-- =============================================================================
-- Rollback for Migration 022: add_credit
-- Drops the credit-tracking index and columns added to bills.
-- =============================================================================

IF EXISTS (
  SELECT 1 FROM sys.indexes
  WHERE object_id = OBJECT_ID('bills') AND name = 'IX_bills_unpaid_credit'
)
  DROP INDEX IX_bills_unpaid_credit ON bills
GO

-- Drop the DEFAULT constraint on payment_status before dropping the column.
DECLARE @df NVARCHAR(128)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('bills') AND c.name = 'payment_status'
IF @df IS NOT NULL EXEC('ALTER TABLE bills DROP CONSTRAINT ' + @df)
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('bills') AND name = 'payment_status')
  ALTER TABLE bills DROP COLUMN payment_status
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('bills') AND name = 'settled_at')
  ALTER TABLE bills DROP COLUMN settled_at
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('bills') AND name = 'settled_payment_mode')
  ALTER TABLE bills DROP COLUMN settled_payment_mode
GO
