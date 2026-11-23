-- =============================================================================
-- Migration 068: add_quotations
--
-- Quotations — a priced quote handed to a customer before the sale, converted
-- into a real bill later (routes/quotations.js, POST /api/bills quotation_id).
--
-- Kept OUT of `bills` on purpose: a bill (even a draft) takes stock and an
-- invoice number, and reports/history/credit all read `bills`. A quotation
-- does none of that, so it stores the billing page's cart snapshot (a
-- Bill-shaped JSON) and is re-priced by the normal bill path on conversion.
--
--   businesses.quotations_enabled - shop-wide opt-in, off by default
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'quotations_enabled'
)
  ALTER TABLE businesses ADD quotations_enabled BIT NOT NULL CONSTRAINT DF_businesses_quotations_enabled DEFAULT 0
GO

IF OBJECT_ID('quotations') IS NULL
CREATE TABLE quotations (
    id                 UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id        UNIQUEIDENTIFIER NOT NULL,
    quotation_number   NVARCHAR(50)     NOT NULL,
    customer_name      NVARCHAR(200)    NULL,
    customer_phone     NVARCHAR(20)     NULL,
    total              DECIMAL(10,2)    NOT NULL,
    snapshot           NVARCHAR(MAX)    NOT NULL,
    status             NVARCHAR(20)     NOT NULL DEFAULT 'open', -- 'open', 'converted'
    bill_id            UNIQUEIDENTIFIER NULL,
    converted_at       DATETIME2        NULL,
    created_by_user_id UNIQUEIDENTIFIER NOT NULL,
    created_at         DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    updated_at         DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_quotations_business
        FOREIGN KEY (business_id) REFERENCES businesses (id),
    CONSTRAINT UQ_quotations_business_number
        UNIQUE (business_id, quotation_number)
)
GO
