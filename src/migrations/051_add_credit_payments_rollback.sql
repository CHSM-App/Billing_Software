-- Drops what migration 051 added. Partly-paid credit bills lose their payment
-- history and read as owing their whole credit part again; fully paid ones keep
-- payment_status/settled_* and stay paid. Roll the code back at the same time
-- (src/creditPayments.js and the routes that use it read these).
IF OBJECT_ID('credit_payments', 'U') IS NOT NULL DROP TABLE credit_payments
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'credit_collected'
)
  ALTER TABLE bills DROP COLUMN credit_collected
GO
