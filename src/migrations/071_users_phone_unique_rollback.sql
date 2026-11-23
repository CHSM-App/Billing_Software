-- =============================================================================
-- Rollback 071: users_phone_unique
-- =============================================================================

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_users_phone' AND object_id = OBJECT_ID('users'))
  DROP INDEX UQ_users_phone ON users
GO
