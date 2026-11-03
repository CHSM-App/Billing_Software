-- =============================================================================
-- Migration 070: add_sessions_valid_after
--
-- users.sessions_valid_after — access tokens issued before this instant are
-- refused (authState.js / requireAuth). Set by a PIN reset and by "log out of
-- all devices", so an attacker's still-valid 8-hour token dies with them,
-- instead of only their refresh token.
--
-- NULLable, no default: metadata-only on every edition. NULL = no cut-off.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('users') AND name = 'sessions_valid_after'
)
  ALTER TABLE users ADD sessions_valid_after DATETIME2 NULL
GO
