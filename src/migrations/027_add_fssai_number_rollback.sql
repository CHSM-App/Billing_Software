-- =============================================================================
-- Rollback 027: add_fssai_number
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('businesses') AND name = 'fssai_number'
)
BEGIN
    ALTER TABLE businesses DROP COLUMN fssai_number
END
GO
