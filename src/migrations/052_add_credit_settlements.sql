-- =============================================================================
-- Migration 052: credit_settlements — one receipt for one Credit-tab payment
--
-- Paying several credit bills at once from the Credit tab used to print (and
-- WhatsApp) one receipt per bill. A settlement row groups the credit_payments
-- made in that one go, so a single "Payment Receipt" can list them all:
--   receipt_token    public link (/receipt/s/<token>), same shape as bills'
--   mode / total     how it was paid and the total received
-- credit_payments.settlement_id points each payment at its settlement; rows
-- from before this migration, and dues collected with a new bill, stay NULL.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('credit_settlements', 'U') IS NULL
CREATE TABLE credit_settlements (
    id                 UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id        UNIQUEIDENTIFIER NOT NULL,
    receipt_token      NVARCHAR(16)     NOT NULL,
    customer_name      NVARCHAR(200)    NULL,
    customer_phone     NVARCHAR(20)     NULL,
    mode               NVARCHAR(20)     NOT NULL,  -- 'cash' | 'upi' | 'card' | 'other'
    total              DECIMAL(10,2)    NOT NULL,
    created_by_user_id UNIQUEIDENTIFIER NULL,
    created_at         DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_credit_settlements_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT UQ_credit_settlements_receipt_token UNIQUE (receipt_token)
)
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('credit_payments') AND name = 'settlement_id'
)
  ALTER TABLE credit_payments ADD settlement_id UNIQUEIDENTIFIER NULL
GO

-- NO ACTION: credit_payments already cascades from bills; a second cascade
-- path is rejected by SQL Server. Settlements are never deleted on their own.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_credit_payments_settlement')
  ALTER TABLE credit_payments ADD CONSTRAINT FK_credit_payments_settlement
    FOREIGN KEY (settlement_id) REFERENCES credit_settlements (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_credit_payments_settlement')
CREATE INDEX IX_credit_payments_settlement ON credit_payments (settlement_id)
  WHERE settlement_id IS NOT NULL
GO
