-- =============================================================================
-- Migration 008: add receipt_token to bills
-- Each bill gets a unique 16-char random token used to generate a public
-- receipt URL: https://billing.vengurlatech.com/receipt/<token>
-- No expiry — receipts are permanent.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'receipt_token'
)
BEGIN
  ALTER TABLE bills ADD receipt_token NVARCHAR(16) NULL;

  -- Backfill existing bills with random tokens
  UPDATE bills
  SET receipt_token = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 16)
  WHERE receipt_token IS NULL;

  -- Make unique and not-null now that all rows are filled
  ALTER TABLE bills ALTER COLUMN receipt_token NVARCHAR(16) NOT NULL;

  CREATE UNIQUE INDEX UQ_bills_receipt_token ON bills (receipt_token);
END
GO
