-- =============================================================================
-- Migration 024: barcode scanning on by default, for everyone
--
-- Barcode scanning is now always-on (the settings toggle was removed). This:
--   1. Turns it on for every existing business.
--   2. Changes the column DEFAULT from 0 to 1 so any future insert that omits
--      the flag is on too.
-- =============================================================================

-- 1) Existing businesses → on.
UPDATE businesses SET has_barcode_scanner = 1 WHERE has_barcode_scanner = 0
GO

-- 2) Swap the DEFAULT constraint 0 → 1. Drop the old one first (its name is
--    auto-generated, so look it up), then add a named default of 1.
DECLARE @df NVARCHAR(128)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('businesses') AND c.name = 'has_barcode_scanner'
IF @df IS NOT NULL EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df)
GO

ALTER TABLE businesses
  ADD CONSTRAINT DF_businesses_has_barcode_scanner
  DEFAULT 1 FOR has_barcode_scanner
GO
