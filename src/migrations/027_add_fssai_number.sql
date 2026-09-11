-- =============================================================================
-- Migration 027: add_fssai_number
--
-- FSSAI license number for food businesses (restaurants). Optional — printed on
-- the bill / receipt only when set. 14-digit number, stored as text to preserve
-- any leading zeros.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('businesses') AND name = 'fssai_number'
)
BEGIN
    ALTER TABLE businesses ADD fssai_number NVARCHAR(20) NULL
END
GO
