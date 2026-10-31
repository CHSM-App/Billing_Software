-- =============================================================================
-- Rollback for Migration 024: barcode_default_on
-- Restores the column DEFAULT to 0. (Does not revert per-row values, since the
-- original off/on state was not preserved.)
-- =============================================================================

DECLARE @df NVARCHAR(128)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('businesses') AND c.name = 'has_barcode_scanner'
IF @df IS NOT NULL EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df)
GO

ALTER TABLE businesses
  ADD CONSTRAINT DF_businesses_has_barcode_scanner
  DEFAULT 0 FOR has_barcode_scanner
GO
