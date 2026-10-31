-- =============================================================================
-- Rollback 070: add_sessions_valid_after
-- =============================================================================

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('users') AND name = 'sessions_valid_after'
)
  ALTER TABLE users DROP COLUMN sessions_valid_after
GO
