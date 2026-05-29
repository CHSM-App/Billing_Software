-- =============================================================================
-- Rollback 002: drop audit_logs table and its indexes
-- =============================================================================

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_event_type'
      AND object_id = OBJECT_ID('audit_logs')
)
    DROP INDEX IX_audit_logs_event_type ON audit_logs
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_user'
      AND object_id = OBJECT_ID('audit_logs')
)
    DROP INDEX IX_audit_logs_user ON audit_logs
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_entity'
      AND object_id = OBJECT_ID('audit_logs')
)
    DROP INDEX IX_audit_logs_entity ON audit_logs
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_audit_logs_business_created'
      AND object_id = OBJECT_ID('audit_logs')
)
    DROP INDEX IX_audit_logs_business_created ON audit_logs
GO

IF OBJECT_ID('audit_logs', 'U') IS NOT NULL
    DROP TABLE audit_logs
GO
