-- =============================================================================
-- Rollback 069: add_otp_attempts
-- =============================================================================

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('whatsapp_otp_log') AND name = 'attempts'
)
  ALTER TABLE whatsapp_otp_log DROP COLUMN attempts
GO
