-- =============================================================================
-- Migration 050: split payments (bill_payments) + the credit part of a bill
--
-- A bill used to carry exactly one payment_mode. A customer who pays ₹300 cash
-- and ₹200 UPI — or ₹500 now and ₹200 on credit — could not be recorded as it
-- happened. Such a bill now stores payment_mode = 'split' and one row per tender
-- here. Single-mode bills are unchanged and have no rows in this table.
--
-- A child table, not a JSON column: reports sum these amounts by mode, and the
-- codebase avoids OPENJSON so it runs on any SQL Server compatibility level.
--
-- bills.credit_amount is the part of a bill left on credit (the 'credit' row of
-- a split). NULL means "the whole bill" — every credit bill written before this
-- migration — so nothing needs backfilling.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('bill_payments', 'U') IS NULL
CREATE TABLE bill_payments (
    id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    bill_id     UNIQUEIDENTIFIER NOT NULL,
    mode        NVARCHAR(20)     NOT NULL,  -- 'cash' | 'upi' | 'card' | 'other' | 'credit'
    amount      DECIMAL(10,2)    NOT NULL,
    created_at  DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_bill_payments_bill
        FOREIGN KEY (bill_id) REFERENCES bills (id)
        ON UPDATE NO ACTION ON DELETE CASCADE
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bill_payments_bill')
CREATE INDEX IX_bill_payments_bill ON bill_payments (bill_id) INCLUDE (mode, amount)
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'credit_amount'
)
  ALTER TABLE bills ADD credit_amount DECIMAL(10,2) NULL
GO
