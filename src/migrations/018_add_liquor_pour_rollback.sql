-- =============================================================================
-- Rollback 018: add_liquor_pour
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

DROP INDEX IX_bill_items_source_variant_id ON bill_items
GO

ALTER TABLE bill_items DROP CONSTRAINT FK_bill_items_source_variant
GO

ALTER TABLE bill_items DROP COLUMN source_variant_id, pour_ml
GO

-- Drop the auto-named DEFAULT constraint on is_poured before dropping the column.
DECLARE @df NVARCHAR(200)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('item_variants') AND c.name = 'is_poured'
IF @df IS NOT NULL EXEC('ALTER TABLE item_variants DROP CONSTRAINT ' + @df)
GO

ALTER TABLE item_variants DROP COLUMN serving_ml, is_poured, bottle_ml, open_ml_remaining
GO
