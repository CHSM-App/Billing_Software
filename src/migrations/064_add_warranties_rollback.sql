-- =============================================================================
-- Rollback 064: add_warranties
-- =============================================================================
-- Drops the warranty record table entirely, including all recorded
-- warranties. Nothing else references it (bills/items/customers are
-- untouched), so this is safe to roll back in isolation.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

DROP TABLE IF EXISTS warranties
GO
