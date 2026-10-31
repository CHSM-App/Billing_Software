-- =============================================================================
-- Migration 025: add_gst_hsn
-- =============================================================================
-- Adds optional GST tax-invoice support. All additive and OFF by default so
-- existing businesses print exactly as before:
--   businesses.gst_enabled       - master toggle (0 = off; hides all GST UI/receipt)
--   businesses.default_sac_code  - bill-level fallback HSN/SAC (e.g. restaurant 9963)
--   items.hsn_code               - optional per-item HSN/SAC
--   bill_items.hsn_code          - snapshot of the item's code at sale time
-- No money math changes: CGST/SGST are derived (tax_amount / 2) at render time.
-- Use GO as the batch separator. No BEGIN/COMMIT — runner manages atomicity.
-- =============================================================================

ALTER TABLE businesses
    ADD gst_enabled      BIT           NOT NULL DEFAULT 0,
        default_sac_code NVARCHAR(10)  NULL
GO

ALTER TABLE items ADD hsn_code NVARCHAR(10) NULL
GO

ALTER TABLE bill_items ADD hsn_code NVARCHAR(10) NULL
GO
