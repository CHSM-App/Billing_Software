-- Restores 'retail_warranty' business_type for businesses this migration
-- converted, then drops the warranty_enabled column.
--
-- EXACT ONLY IF RUN BEFORE ANY BUSINESS HAS USED THE SETTINGS TOGGLE. Once an
-- owner turns warranty_enabled on/off themselves after this migration ran,
-- warranty_enabled = 1 AND business_type = 'retail' also matches businesses
-- that were never 'retail_warranty' — this rollback would wrongly revert
-- them too. If real usage has happened, restore from a pre-migration backup
-- instead, or identify the originally-converted businesses by id:
--   UPDATE businesses SET business_type = 'retail_warranty' WHERE id IN (...)

UPDATE businesses
SET business_type = 'retail_warranty'
WHERE warranty_enabled = 1 AND business_type = 'retail'
GO

ALTER TABLE businesses
    DROP CONSTRAINT DF_businesses_warranty_enabled
GO

ALTER TABLE businesses
    DROP COLUMN warranty_enabled
GO
