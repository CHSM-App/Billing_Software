-- =============================================================================
-- Rollback 065: add_bill_warranty_extra_data
-- =============================================================================
-- Drops the column. Existing warranties rows keep whatever extra_data they
-- already carry (migration 064's table is untouched); only the ability to
-- capture new details at billing time is removed.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

ALTER TABLE bills
    DROP COLUMN warranty_extra_data
GO
