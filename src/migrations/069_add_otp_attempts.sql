-- =============================================================================
-- Migration 069: add_otp_attempts
--
-- whatsapp_otp_log.attempts counts wrong guesses against one OTP. verifyOtp
-- (whatsapp.js) retires the code after MAX_OTP_ATTEMPTS, so guesses spread
-- across many IPs can no longer add up against a single 6-digit code.
--
-- NULLable with no default on purpose: adding it is a metadata-only change on
-- every SQL Server edition, so it never rewrites or locks the table. NULL
-- reads as 0.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('whatsapp_otp_log') AND name = 'attempts'
)
  ALTER TABLE whatsapp_otp_log ADD attempts INT NULL
GO
