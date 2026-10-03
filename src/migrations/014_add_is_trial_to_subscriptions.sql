-- Migration 014: add is_trial flag to subscriptions
-- Distinguishes auto-provisioned free-trial subscriptions (created at
-- registration) from paid subscriptions activated via the admin endpoint.
-- Default 0 so all existing/paid rows are treated as non-trial.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'is_trial'
)
BEGIN
    ALTER TABLE subscriptions
        ADD is_trial BIT NOT NULL DEFAULT 0
END
GO
