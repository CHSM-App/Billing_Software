-- =============================================================================
-- Migration 022: credit (udhaari) bills
--
-- A credit bill is a finalized sale whose money has not been collected yet.
-- It stays status='finalized' with payment_mode='credit', but is tracked as
-- unpaid via payment_status until it is settled. On settlement the row flips
-- to payment_status='paid' and records when + how it was paid.
--
-- Existing bills default to 'paid', so current behaviour and reports are
-- unchanged — only bills explicitly created on credit are 'unpaid'.
-- =============================================================================

-- payment_status: 'paid' | 'unpaid'
IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'payment_status'
)
  ALTER TABLE bills ADD payment_status NVARCHAR(20) NOT NULL DEFAULT 'paid'
GO

-- When the credit bill was settled (paid off). NULL while unpaid.
IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'settled_at'
)
  ALTER TABLE bills ADD settled_at DATETIME2 NULL
GO

-- How the credit bill was ultimately paid (cash/upi/…). NULL while unpaid.
IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'settled_payment_mode'
)
  ALTER TABLE bills ADD settled_payment_mode NVARCHAR(20) NULL
GO

-- Index to quickly list unpaid credit bills per business (the Credit tab).
IF NOT EXISTS (
  SELECT 1 FROM sys.indexes
  WHERE object_id = OBJECT_ID('bills') AND name = 'IX_bills_unpaid_credit'
)
  CREATE INDEX IX_bills_unpaid_credit
    ON bills (business_id, customer_phone)
    WHERE payment_status = 'unpaid'
GO
