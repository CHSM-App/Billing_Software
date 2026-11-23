-- =============================================================================
-- Migration 017 rollback: add_kitchen
-- =============================================================================

DROP INDEX IX_bill_items_kitchen_status ON bill_items
GO

-- Drop the DEFAULT constraint on kitchen_status before dropping the column.
DECLARE @df NVARCHAR(200)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('bill_items') AND c.name = 'kitchen_status'
IF @df IS NOT NULL EXEC('ALTER TABLE bill_items DROP CONSTRAINT ' + @df)
GO

ALTER TABLE bill_items DROP COLUMN kitchen_status
GO

ALTER TABLE bill_items DROP COLUMN kitchen_done_at
GO
