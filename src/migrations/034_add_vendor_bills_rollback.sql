-- =============================================================================
-- Migration 034 rollback: add_vendor_bills
-- =============================================================================
-- Drops the vendor bill tables and restores the pre-034 audit event list.
--
-- ORDER MATTERS. The audit rows must go FIRST: restoring the 19-value CHECK
-- while 'vendor_bill_*' rows still exist makes the ALTER fail, because MSSQL
-- validates existing data against the new constraint. Those rows reference
-- tables this migration is about to drop, so deleting them is correct rather
-- than merely convenient.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

DELETE FROM audit_logs WHERE event_type LIKE 'vendor_bill_%'
GO

ALTER TABLE audit_logs
    DROP CONSTRAINT CK_audit_logs_event_type
GO

-- The migration-010 list, verbatim.
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

-- Child first: vendor_bill_items cascades from vendor_bills, but an explicit
-- drop keeps the intent obvious and the order safe.
DROP TABLE vendor_bill_items
GO

DROP TABLE vendor_bills
GO
