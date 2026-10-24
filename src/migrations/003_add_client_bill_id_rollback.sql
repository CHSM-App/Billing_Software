-- Rollback 003: remove client_bill_id column and its index

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'UQ_bills_client_bill_id'
      AND object_id = OBJECT_ID('bills')
)
    DROP INDEX UQ_bills_client_bill_id ON bills
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('bills')
      AND name = 'client_bill_id'
)
BEGIN
    ALTER TABLE bills DROP COLUMN client_bill_id
END
GO
