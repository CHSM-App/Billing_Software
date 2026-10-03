-- Migration 006: Add business_profile_updated event type to audit_logs CHECK constraint
-- MSSQL does not support ALTER on CHECK constraints — must drop and recreate.
-- Use GO as the batch separator. No BEGIN/COMMIT — runner manages atomicity.

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
