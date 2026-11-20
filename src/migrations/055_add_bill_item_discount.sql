-- =============================================================================
-- Migration 055: bill_items.discount_amount — per-item discount from the order card
--
-- The ₹ taken off one line's NET (pre-tax) amount. Display only: unit_price
-- already holds the discounted net rate, so every taxable = qty × unit_price
-- query (reports, GST summary, receipts) stays correct untouched. 0 for every
-- existing row.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bill_items') AND name = 'discount_amount'
)
  ALTER TABLE bill_items ADD discount_amount DECIMAL(10,2) NOT NULL CONSTRAINT DF_bill_items_discount_amount DEFAULT 0
GO
