-- =============================================================================
-- Migration 051: credit_payments — paying credit bills off in parts
--
-- A credit (udhaari) bill used to be settled all at once: payment_status
-- flipped to 'paid' and settled_payment_mode recorded the one mode. Customers
-- pay old dues in pieces — ₹200 today with a new purchase, the rest next week
-- from the Credit tab — so every payment is now a row here:
--   bill_id          the credit bill being paid off
--   paid_in_bill_id  the bill it was collected with (NULL: the Credit tab)
--   mode / amount    how much, and in which tender
-- A bill still owes its credit part less these rows (src/creditPayments.js);
-- at 0 it is settled exactly as before (payment_status, settled_at, mode).
--
-- bills.credit_collected is the total of old dues a bill collected, so the
-- receipt and history know to list them without a lookup on every bill.
--
-- Backfill: each credit bill already settled gets one row for its whole credit
-- part, dated when it was settled, so "what is still owed" reads 0 for it.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('credit_payments', 'U') IS NULL
CREATE TABLE credit_payments (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id      UNIQUEIDENTIFIER NOT NULL,
    bill_id          UNIQUEIDENTIFIER NOT NULL,
    paid_in_bill_id  UNIQUEIDENTIFIER NULL,
    mode             NVARCHAR(20)     NOT NULL,  -- 'cash' | 'upi' | 'card' | 'other'
    amount           DECIMAL(10,2)    NOT NULL,
    created_at       DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_credit_payments_bill
        FOREIGN KEY (bill_id) REFERENCES bills (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,
    -- NO ACTION: a second cascade path into credit_payments is not allowed, and
    -- a bill that collected dues is a financial record that is never deleted.
    CONSTRAINT FK_credit_payments_paid_in
        FOREIGN KEY (paid_in_bill_id) REFERENCES bills (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_credit_payments_bill')
CREATE INDEX IX_credit_payments_bill ON credit_payments (bill_id) INCLUDE (amount, mode)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_credit_payments_paid_in')
CREATE INDEX IX_credit_payments_paid_in ON credit_payments (paid_in_bill_id)
  WHERE paid_in_bill_id IS NOT NULL
GO

-- Reports: money collected per day, by mode.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_credit_payments_business_date')
CREATE INDEX IX_credit_payments_business_date
  ON credit_payments (business_id, created_at) INCLUDE (mode, amount)
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'credit_collected'
)
  ALTER TABLE bills ADD credit_collected DECIMAL(10,2) NULL
GO

-- Backfill settled credit bills (see header). Re-runnable: skips any bill that
-- already has a payment row.
INSERT INTO credit_payments (business_id, bill_id, paid_in_bill_id, mode, amount, created_at)
SELECT b.business_id, b.id, NULL,
       ISNULL(NULLIF(b.settled_payment_mode, ''), 'other'),
       ISNULL(b.credit_amount, b.total - b.discount_amount + ISNULL(b.round_off, 0)),
       ISNULL(b.settled_at, b.created_at)
FROM bills b
WHERE b.payment_status = 'paid'
  AND b.status = 'finalized'
  AND (b.payment_mode = 'credit' OR b.credit_amount IS NOT NULL)
  AND b.settled_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM credit_payments cp WHERE cp.bill_id = b.id)
GO
