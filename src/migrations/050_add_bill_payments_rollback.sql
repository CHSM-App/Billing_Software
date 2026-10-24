-- Drops what migration 050 added. Split bills keep payment_mode = 'split' but
-- lose their per-mode rows, and a part-credit bill's due reverts to its whole
-- total — roll the code back at the same time (routes/bills.js, credit.js and
-- reports.js read these).
IF OBJECT_ID('bill_payments', 'U') IS NOT NULL DROP TABLE bill_payments
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'credit_amount'
)
  ALTER TABLE bills DROP COLUMN credit_amount
GO
