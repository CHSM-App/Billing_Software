-- Rollback 010: Remove account_deletion_requests table and revert audit constraint

-- ── 1. Drop the table (indexes are dropped automatically) ───────────────────

IF EXISTS (
    SELECT 1 FROM sys.objects WHERE name = 'account_deletion_requests' AND type = 'U'
)
BEGIN
    DROP TABLE account_deletion_requests
    PRINT 'Rollback 010: account_deletion_requests dropped.'
END
GO

-- ── 2. Revert whatsapp_otp_log purpose constraint ───────────────────────────

ALTER TABLE whatsapp_otp_log
    DROP CONSTRAINT CK_whatsapp_otp_log_purpose
GO

ALTER TABLE whatsapp_otp_log
    ADD CONSTRAINT CK_whatsapp_otp_log_purpose CHECK (purpose IN (
        'register',
        'forgot_pin'
    ))
GO

-- ── 3. Revert audit_logs CHECK constraint to pre-010 state ──────────────────

ALTER TABLE audit_logs
    DROP CONSTRAINT CK_audit_logs_event_type
GO

ALTER TABLE audit_logs
    ADD CONSTRAINT CK_audit_logs_event_type CHECK (event_type IN (
        'bill_created',
        'bill_finalized',
        'bill_voided',
        'bill_items_added',
        'bill_items_updated',
        'item_created',
        'item_price_changed',
        'item_stock_adjusted',
        'item_deleted',
        'staff_added',
        'staff_updated',
        'staff_deleted',
        'user_login',
        'user_login_failed',
        'user_locked',
        'business_profile_updated'
    ))
GO
