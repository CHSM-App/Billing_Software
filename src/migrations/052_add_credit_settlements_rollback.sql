-- Drops what migration 052 added. The payments themselves stay (credit_payments
-- keeps every row); only the grouping into one receipt per settlement is lost.
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_credit_payments_settlement')
  ALTER TABLE credit_payments DROP CONSTRAINT FK_credit_payments_settlement
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_credit_payments_settlement')
  DROP INDEX IX_credit_payments_settlement ON credit_payments
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('credit_payments') AND name = 'settlement_id'
)
  ALTER TABLE credit_payments DROP COLUMN settlement_id
GO

IF OBJECT_ID('credit_settlements', 'U') IS NOT NULL DROP TABLE credit_settlements
GO
