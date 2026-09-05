-- =============================================================================
-- Rollback 030: add_last_active_at
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

ALTER TABLE businesses
    DROP COLUMN last_active_at
GO
