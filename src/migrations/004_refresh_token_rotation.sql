-- Migration 004: Add token rotation support to refresh_tokens
-- Adds family_id for reuse detection (revoke entire family on stolen token use)
-- Use GO as the batch separator (not semicolons). No BEGIN/COMMIT — runner manages atomicity.

ALTER TABLE refresh_tokens
    ADD family_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID()
GO

-- Backfill: each existing token gets its own unique family ID.
UPDATE refresh_tokens
SET family_id = NEWID()
WHERE 1 = 1
GO

-- Index for family-based revocation queries.
CREATE INDEX IX_refresh_tokens_family_id ON refresh_tokens (family_id)
GO
