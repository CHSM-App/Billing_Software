-- =============================================================================
-- Migration 002: audit_logs table
--
-- Immutable append-only log for every significant action in the system.
-- Rows are NEVER updated or deleted — voiding bills and reversing stock
-- generates NEW rows that reference the original event.
--
-- event_type vocabulary (enforced by check constraint):
--   Bill lifecycle : bill_created, bill_finalized, bill_voided
--   Item changes   : item_created, item_price_changed, item_stock_adjusted,
--                    item_deleted
--   Staff changes  : staff_added, staff_updated, staff_deleted
--   Auth events    : user_login, user_login_failed, user_locked
-- =============================================================================

-- Guard: ensure the table does not already exist
IF NOT EXISTS (
    SELECT 1 FROM sys.objects WHERE name = 'audit_logs' AND type = 'U'
)
BEGIN
    CREATE TABLE audit_logs (
        -- Surrogate primary key
        id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),

        -- Tenant isolation — every row belongs to a business
        business_id      UNIQUEIDENTIFIER NOT NULL,

        -- Who performed the action (NULL for system-generated events)
        user_id          UNIQUEIDENTIFIER NULL,
        user_name        NVARCHAR(200)    NULL,   -- snapshot, survives user deletion

        -- What happened
        event_type       NVARCHAR(50)     NOT NULL,

        -- The primary entity affected (bill id, item id, user id, etc.)
        entity_id        UNIQUEIDENTIFIER NULL,
        entity_label     NVARCHAR(200)    NULL,   -- human-readable snapshot (bill number, item name, …)

        -- Structured before/after payloads (JSON text)
        -- NULL when the event has no meaningful state change (e.g. login)
        old_value        NVARCHAR(MAX)    NULL,
        new_value        NVARCHAR(MAX)    NULL,

        -- Free-form description added by the application
        description      NVARCHAR(1000)  NULL,

        -- Immutable timestamp (UTC)
        created_at       DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT PK_audit_logs PRIMARY KEY (id),

        CONSTRAINT CK_audit_logs_event_type CHECK (event_type IN (
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
            'user_locked'
        ))
    )
END
GO

-- Index: filter by business + time (most common query shape)
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_business_created'
      AND object_id = OBJECT_ID('audit_logs')
)
BEGIN
    CREATE INDEX IX_audit_logs_business_created
        ON audit_logs (business_id, created_at DESC)
END
GO

-- Index: filter by entity (e.g. "show all events for bill X")
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_entity'
      AND object_id = OBJECT_ID('audit_logs')
)
BEGIN
    CREATE INDEX IX_audit_logs_entity
        ON audit_logs (entity_id, created_at DESC)
        WHERE entity_id IS NOT NULL
END
GO

-- Index: filter by actor (e.g. "what did cashier Y do today?")
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_user'
      AND object_id = OBJECT_ID('audit_logs')
)
BEGIN
    CREATE INDEX IX_audit_logs_user
        ON audit_logs (user_id, created_at DESC)
        WHERE user_id IS NOT NULL
END
GO

-- Index: filter by event_type (e.g. "all voids this week")
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_event_type'
      AND object_id = OBJECT_ID('audit_logs')
)
BEGIN
    CREATE INDEX IX_audit_logs_event_type
        ON audit_logs (business_id, event_type, created_at DESC)
END
GO
