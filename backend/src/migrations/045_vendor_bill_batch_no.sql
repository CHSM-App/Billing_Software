-- =============================================================================
-- Migration 045: vendor_bill_batch_no — one batch number per purchase bill
--
-- 044 put batch_no on each purchase line. A shop receives a delivery as one
-- lot, so the batch number belongs to the bill: every item on it shares it.
-- Moves the column to vendor_bills (keeping any value already entered) and
-- drops it from the lines. stock_batches.batch_no is unchanged — each batch
-- still carries its own copy, taken from its bill when received.
-- =============================================================================

ALTER TABLE vendor_bills ADD batch_no NVARCHAR(50) NULL
GO

UPDATE vb SET batch_no = (
    SELECT MAX(vbi.batch_no) FROM vendor_bill_items vbi WHERE vbi.vendor_bill_id = vb.id
)
FROM vendor_bills vb
GO

ALTER TABLE vendor_bill_items DROP COLUMN batch_no
GO
