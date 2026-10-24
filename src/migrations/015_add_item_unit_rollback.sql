-- =============================================================================
-- Rollback 015: add_item_unit
-- =============================================================================
-- Drop the default constraint (auto-named) before dropping the column.
-- =============================================================================

DECLARE @df NVARCHAR(200)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('items')
  AND c.name = 'unit'
IF @df IS NOT NULL
  EXEC('ALTER TABLE items DROP CONSTRAINT ' + @df)
GO

ALTER TABLE items DROP COLUMN unit
GO
