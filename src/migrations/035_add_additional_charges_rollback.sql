-- =============================================================================
-- Rollback 035: add_additional_charges
-- =============================================================================
-- Drop the auto-named DEFAULT constraint before its column. Any charges
-- already folded into bills.total stay in total (the detail is lost).
-- =============================================================================

DECLARE @df1 NVARCHAR(200)
SELECT @df1 = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('bills')
  AND c.name = 'charges_amount'
IF @df1 IS NOT NULL
  EXEC('ALTER TABLE bills DROP CONSTRAINT ' + @df1)
GO

ALTER TABLE bills DROP COLUMN charges_amount
GO

ALTER TABLE bills DROP COLUMN additional_charges
GO
