-- =============================================================================
-- Rollback for Migration 037: add_online_store
-- =============================================================================
-- Drops the online-store tables and the businesses.store_* columns, and puts the
-- audit event-type CHECK back to migration 034's list.
--
-- Order matters: online_order_items references online_orders, and online_orders
-- references bills/users/businesses, so children go first.
-- =============================================================================

-- --- audit event types back to the 034 list ----------------------------------
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_audit_logs_event_type')
    ALTER TABLE audit_logs DROP CONSTRAINT CK_audit_logs_event_type
GO

-- Any rows written by the online store would violate the restored constraint, so
-- clear them before re-adding it (they are log entries, not financial records).
DELETE FROM audit_logs
WHERE event_type IN ('online_order_accepted', 'online_order_rejected')
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
        'vendor_bill_deleted'
    ))
GO

-- --- tables -------------------------------------------------------------------
IF OBJECT_ID('online_order_items', 'U') IS NOT NULL
    DROP TABLE online_order_items
GO

IF OBJECT_ID('online_orders', 'U') IS NOT NULL
    DROP TABLE online_orders
GO

-- --- businesses.store_* --------------------------------------------------------
-- A DEFAULT constraint must be dropped before its column on some SQL Server
-- setups, so each BIT/DECIMAL column clears its default first.
DECLARE @c sysname, @sqlText NVARCHAR(500)
DECLARE cols CURSOR LOCAL FAST_FORWARD FOR
    SELECT c.name
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('businesses')
      -- store_pickup_enabled is listed although 037 no longer adds it: an early
      -- database may still carry it from before pickup became unconditional.
      AND c.name IN ('store_enabled', 'store_pickup_enabled', 'store_delivery_enabled',
                     'store_delivery_charge', 'store_advance_percent',
                     'store_payment_required')
OPEN cols
FETCH NEXT FROM cols INTO @c
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @sqlText = 'ALTER TABLE businesses DROP CONSTRAINT ' + dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE c.object_id = OBJECT_ID('businesses') AND c.name = @c
    IF @sqlText IS NOT NULL EXEC(@sqlText)
    SET @sqlText = NULL
    FETCH NEXT FROM cols INTO @c
END
CLOSE cols
DEALLOCATE cols
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_businesses_store_token')
    DROP INDEX UQ_businesses_store_token ON businesses
GO

IF COL_LENGTH('businesses', 'store_payment_required') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_payment_required
GO
IF COL_LENGTH('businesses', 'store_advance_percent') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_advance_percent
GO
IF COL_LENGTH('businesses', 'store_payment_qr_url') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_payment_qr_url
GO
IF COL_LENGTH('businesses', 'store_delivery_charge') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_delivery_charge
GO
IF COL_LENGTH('businesses', 'store_delivery_enabled') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_delivery_enabled
GO
IF COL_LENGTH('businesses', 'store_pickup_enabled') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_pickup_enabled
GO
IF COL_LENGTH('businesses', 'store_token') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_token
GO
IF COL_LENGTH('businesses', 'store_enabled') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_enabled
GO
