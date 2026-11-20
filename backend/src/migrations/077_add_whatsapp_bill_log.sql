-- =============================================================================
-- Migration 077: add_whatsapp_bill_log
-- =============================================================================
-- One row per "send receipt on WhatsApp" attempt (a bill or a credit-settlement
-- receipt), written by whatsapp.logWhatsappSend. Behind the per-business count
-- on the Vittam admin dashboard — 'api' sends cost money on the shared account.
--
--   status: sent / failed / skipped (api mode, API disabled)
--           opened (deeplink — the app opened the cashier's own WhatsApp; the
--                   server can't know whether they actually pressed send)
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

CREATE TABLE whatsapp_bill_log (
    id             UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id    UNIQUEIDENTIFIER NOT NULL,
    -- One or the other. No FKs: both bills and credit_settlements cascade from
    -- businesses, and a second path is a multiple-cascade-path error in MSSQL.
    bill_id        UNIQUEIDENTIFIER NULL,
    settlement_id  UNIQUEIDENTIFIER NULL,
    mode           NVARCHAR(10)     NOT NULL,
    status         NVARCHAR(10)     NOT NULL,
    campaign_id    NVARCHAR(100)    NULL,
    error_detail   NVARCHAR(500)    NULL,
    created_at     DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_whatsapp_bill_log_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    CONSTRAINT CK_whatsapp_bill_log_mode
        CHECK (mode IN ('api', 'deeplink')),

    CONSTRAINT CK_whatsapp_bill_log_status
        CHECK (status IN ('sent', 'failed', 'skipped', 'opened'))
)
GO

-- The admin dashboard counts a business's sends since the 1st.
CREATE INDEX IX_whatsapp_bill_log_business_created
    ON whatsapp_bill_log (business_id, created_at)
GO
