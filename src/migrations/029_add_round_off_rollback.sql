-- =============================================================================
-- Rollback 029: add_round_off
-- =============================================================================
-- Drop the auto-named DEFAULT constraints before their columns.
-- =============================================================================

DECLARE @df1 NVARCHAR(200)
SELECT @df1 = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('businesses')
  AND c.name = 'round_off_enabled'
IF @df1 IS NOT NULL
  EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df1)
GO

ALTER TABLE businesses DROP COLUMN round_off_enabled
GO

DECLARE @df2 NVARCHAR(200)
SELECT @df2 = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('bills')
  AND c.name = 'round_off'
IF @df2 IS NOT NULL
  EXEC('ALTER TABLE bills DROP CONSTRAINT ' + @df2)
GO

ALTER TABLE bills DROP COLUMN round_off
GO
