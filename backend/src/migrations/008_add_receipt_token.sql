-- =============================================================================
-- Migration 008: add receipt_token to bills
-- Each bill gets a unique 16-char random token used to generate a public
-- receipt URL: https://VBill.vengurlatech.com/receipt/<token>
-- No expiry — receipts are permanent.
-- =============================================================================

-- Step 1: Add column as nullable
IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'receipt_token'
)
  ALTER TABLE bills ADD receipt_token NVARCHAR(16) NULL
GO

-- Step 2: Backfill existing bills (separate batch so column is visible)
UPDATE bills
SET receipt_token = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 16)
WHERE receipt_token IS NULL
GO

-- Step 3: Make NOT NULL
ALTER TABLE bills ALTER COLUMN receipt_token NVARCHAR(16) NOT NULL
GO

-- Step 4: Unique index
IF NOT EXISTS (
  SELECT 1 FROM sys.indexes
  WHERE object_id = OBJECT_ID('bills') AND name = 'UQ_bills_receipt_token'
)
  CREATE UNIQUE INDEX UQ_bills_receipt_token ON bills (receipt_token)
GO
