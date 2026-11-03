-- =============================================================================
-- Rollback 072: add_terms_acceptances
--
-- Set TERMS_VERSION back to null in src/legal.js BEFORE running this, or
-- /license and /register will query a table that no longer exists.
-- WARNING: drops the acceptance evidence. Export it first if it may be needed:
--   SELECT * FROM terms_acceptances
-- =============================================================================

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_audit_logs_event_type')
    ALTER TABLE audit_logs DROP CONSTRAINT CK_audit_logs_event_type
GO

-- Rows of the removed type would violate the restored constraint.
DELETE FROM audit_logs WHERE event_type = 'terms_accepted'
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
        'business_profile_updated',
        'account_deletion_requested',
        'account_deletion_cancelled',
        'account_deleted',
        'vendor_bill_created',
        'vendor_bill_updated',
        'vendor_bill_deleted',
        'online_order_accepted',
        'online_order_rejected'
    ))
GO

IF OBJECT_ID('terms_acceptances', 'U') IS NOT NULL
    DROP TABLE terms_acceptances
GO
