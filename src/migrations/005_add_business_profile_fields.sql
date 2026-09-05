-- Migration 005: Add business profile fields (GST, contact, logo)
-- Adds extended business details to support the business profile management UI.
-- Use GO as the batch separator. No BEGIN/COMMIT — runner manages atomicity.

ALTER TABLE businesses
    ADD gst_number        NVARCHAR(15)   NULL,
        pan_number        NVARCHAR(10)   NULL,
        email             NVARCHAR(200)  NULL,
        website           NVARCHAR(500)  NULL,
        city              NVARCHAR(100)  NULL,
        state             NVARCHAR(100)  NULL,
        pincode           NVARCHAR(10)   NULL,
        logo_url          NVARCHAR(1000) NULL,
        bill_prefix       NVARCHAR(10)   NULL DEFAULT 'INV',
        bill_footer_note  NVARCHAR(500)  NULL
GO

-- Partial unique index: GSTIN must be unique across businesses if provided.
CREATE UNIQUE INDEX UQ_businesses_gst_number
    ON businesses (gst_number)
    WHERE gst_number IS NOT NULL
GO
