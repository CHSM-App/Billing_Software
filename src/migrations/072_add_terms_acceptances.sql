-- =============================================================================
-- Migration 072: add_terms_acceptances
--
-- Evidence that a business owner agreed to the legal terms (Terms of Service +
-- Acceptable Use Policy + Privacy Policy, docs/legal/). One row per user per
-- version accepted, INSERT-only — a re-acceptance of a new version adds a row,
-- so the full history of who agreed to what, when, is kept.
--
--   terms_version - src/legal.js TERMS_VERSION at the moment of acceptance.
--                   Always the SERVER's value, never one the client chose.
--   source        - 'register' (checkbox at sign-up) | 'reaccept' (the
--                   updated-terms screen shown to existing owners)
--   ip_address    - req.ip, as login_logs already records at sign-in
--
-- Inert until TERMS_VERSION is set in src/legal.js; nothing writes here before.
-- Also adds 'terms_accepted' to the audit_logs event list.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('terms_acceptances', 'U') IS NULL
CREATE TABLE terms_acceptances (
    id             UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    user_id        UNIQUEIDENTIFIER NOT NULL,
    business_id    UNIQUEIDENTIFIER NOT NULL,
    terms_version  NVARCHAR(20)     NOT NULL,
    source         NVARCHAR(20)     NOT NULL,
    ip_address     NVARCHAR(45)     NULL,
    accepted_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    -- Same choices as login_logs (026): the business going takes its records
    -- with it; a user row cannot be removed while its acceptance evidence exists.
    CONSTRAINT FK_terms_acceptances_business FOREIGN KEY (business_id)
        REFERENCES businesses (id) ON DELETE CASCADE,
    CONSTRAINT FK_terms_acceptances_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE NO ACTION,

    CONSTRAINT CK_terms_acceptances_source
        CHECK (source IN ('register', 'reaccept'))
)
GO

-- One acceptance per user per version. Also the lookup /license makes on every
-- app open ("has this owner accepted the current version?").
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_terms_acceptances_user_version')
    CREATE UNIQUE INDEX UQ_terms_acceptances_user_version
        ON terms_acceptances (user_id, terms_version)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_terms_acceptances_business')
    CREATE INDEX IX_terms_acceptances_business
        ON terms_acceptances (business_id, accepted_at DESC)
GO

-- --- audit event types --------------------------------------------------------
-- MSSQL cannot ALTER a CHECK constraint — drop and recreate with the FULL list.
-- Source of truth is migration 037's list (25 values); this adds terms_accepted.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_audit_logs_event_type')
    ALTER TABLE audit_logs DROP CONSTRAINT CK_audit_logs_event_type
GO

ALTER TABLE audit_logs
    ADD CONSTRAINT CK_audit_logs_event_type CHECK (event_type IN (
        -- Bill lifecycle
        'bill_created',
        'bill_finalized',
        'bill_voided',
        'bill_items_added',
        'bill_items_updated',
        -- Item management
        'item_created',
        'item_price_changed',
        'item_stock_adjusted',
        'item_deleted',
        -- Staff management
        'staff_added',
        'staff_updated',
        'staff_deleted',
        -- Auth events
        'user_login',
        'user_login_failed',
        'user_locked',
        -- Business profile
        'business_profile_updated',
        -- Account deletion lifecycle
        'account_deletion_requested',
        'account_deletion_cancelled',
        'account_deleted',
        -- Vendor bills (034)
        'vendor_bill_created',
        'vendor_bill_updated',
        'vendor_bill_deleted',
        -- Online store (037)
        'online_order_accepted',
        'online_order_rejected',
        -- Legal terms (new in 072)
        'terms_accepted'
    ))
GO
