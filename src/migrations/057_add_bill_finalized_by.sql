-- =============================================================================
-- Migration 057: bills.finalized_by_user_id — who settled the bill
--
-- created_by_user_id is whoever STARTED the bill — for a table order that is the
-- waiter who held it. Prices and discounts are edited, and the bill settled, by
-- a cashier/owner, so receipts and History show "Billed by" the settler. NULL on
-- bills settled before this column existed; readers fall back to the creator.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'finalized_by_user_id'
)
  ALTER TABLE bills ADD finalized_by_user_id UNIQUEIDENTIFIER NULL
GO

-- NO ACTION: bills are financial records and must survive staff deletion.
IF NOT EXISTS (
  SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bills_finalized_by_user'
)
  ALTER TABLE bills ADD CONSTRAINT FK_bills_finalized_by_user
    FOREIGN KEY (finalized_by_user_id) REFERENCES users (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO
