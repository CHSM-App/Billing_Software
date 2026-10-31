-- =============================================================================
-- Rollback 073: one_owner_per_business
-- =============================================================================

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_users_one_owner' AND object_id = OBJECT_ID('users'))
  DROP INDEX UQ_users_one_owner ON users
GO
