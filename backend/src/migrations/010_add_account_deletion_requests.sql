-- Migration 010: account_deletion_requests table + new audit event types
--
-- Stores pending/completed account deletion requests submitted via the
-- landing page. The 30-day scheduled_for window lets users cancel before
-- data is permanently erased.
--
-- audit_logs CHECK constraint is extended with three new event types:
--   account_deletion_requested  — owner submitted and OTP-verified the form
--   account_deletion_cancelled  — owner cancelled within the 30-day window
--   account_deleted             — data was permanently purged (by the cleanup job)

-- ── 1. account_deletion_requests ────────────────────────────────────────────

IF NOT EXISTS (
    SELECT 1 FROM sys.objects WHERE name = 'account_deletion_requests' AND type = 'U'
)
BEGIN
    CREATE TABLE account_deletion_requests (
        id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        business_id     UNIQUEIDENTIFIER NOT NULL,
        requested_by    UNIQUEIDENTIFIER NOT NULL,   -- user.id of the owner
        phone           NVARCHAR(20)     NOT NULL,   -- snapshot of owner phone at request time
        reason          NVARCHAR(500)    NULL,
        status          NVARCHAR(20)     NOT NULL DEFAULT 'pending',
        otp_verified_at DATETIME2        NOT NULL,
        scheduled_for   DATETIME2        NOT NULL,   -- otp_verified_at + 30 days
        completed_at    DATETIME2        NULL,
        created_at      DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT PK_account_deletion_requests PRIMARY KEY (id),

        -- No CASCADE on business_id — the request row must survive the deletion
        -- so we have a permanent audit record even after the business is gone.
        CONSTRAINT FK_adr_business FOREIGN KEY (business_id)
            REFERENCES businesses(id),

        -- Same: keep the request row after the user row is deleted.
        CONSTRAINT FK_adr_user FOREIGN KEY (requested_by)
            REFERENCES users(id),

        CONSTRAINT CK_adr_status CHECK (status IN ('pending', 'cancelled', 'completed'))
    )

    -- Only one pending request per business at a time
    CREATE UNIQUE INDEX UX_adr_business_pending
        ON account_deletion_requests (business_id)
        WHERE status = 'pending'

    -- Lookup by scheduled_for for the nightly cleanup job
    CREATE INDEX IX_adr_scheduled
        ON account_deletion_requests (status, scheduled_for)

    PRINT 'Migration 010: account_deletion_requests created.'
END
ELSE
BEGIN
    PRINT 'Migration 010: account_deletion_requests already exists — skipped.'
END
GO

-- ── 2. Extend whatsapp_otp_log purpose constraint ───────────────────────────
-- Add 'delete_account' as a valid OTP purpose

ALTER TABLE whatsapp_otp_log
    DROP CONSTRAINT CK_whatsapp_otp_log_purpose
GO

ALTER TABLE whatsapp_otp_log
    ADD CONSTRAINT CK_whatsapp_otp_log_purpose CHECK (purpose IN (
        'register',
        'forgot_pin',
        'delete_account'
    ))
GO

-- ── 3. Extend audit_logs CHECK constraint ───────────────────────────────────
-- MSSQL does not support ALTER on CHECK constraints — must drop and recreate.

ALTER TABLE audit_logs
    DROP CONSTRAINT CK_audit_logs_event_type
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
        'account_deleted'
    ))
GO
