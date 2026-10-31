-- =============================================================================
-- Migration 053: bills.finalized_at — when the sale was finalized
--
-- created_at is when the bill row was first written: for a held order that is
-- the ORDER time, possibly days before it was settled. finalized_at is the
-- SALE time — what the bill prints as its date, and what history, sales and
-- GST reports file it under. NULL while a bill is still a draft.
--
-- Paying off a credit bill never changes it: the payoff has its own dates
-- (settled_at, credit_payments.created_at).
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'finalized_at'
)
  ALTER TABLE bills ADD finalized_at DATETIME2 NULL
GO

-- Existing finalized bills: the order time is the best record there is.
UPDATE bills SET finalized_at = created_at
WHERE status = 'finalized' AND finalized_at IS NULL
GO

-- History and report date ranges are per business on this column.
IF NOT EXISTS (
  SELECT 1 FROM sys.indexes
  WHERE object_id = OBJECT_ID('bills') AND name = 'IX_bills_business_finalized'
)
  CREATE INDEX IX_bills_business_finalized ON bills (business_id, finalized_at)
GO
