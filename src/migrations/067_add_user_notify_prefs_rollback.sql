-- =============================================================================
-- Rollback 067: add_user_notify_prefs
-- =============================================================================
-- Drop the auto-named DEFAULT constraints before their columns.
-- =============================================================================

DECLARE @df1 NVARCHAR(200)
SELECT @df1 = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('users')
  AND c.name = 'notify_low_stock'
IF @df1 IS NOT NULL
  EXEC('ALTER TABLE users DROP CONSTRAINT ' + @df1)
GO

ALTER TABLE users DROP COLUMN notify_low_stock
GO

DECLARE @df2 NVARCHAR(200)
SELECT @df2 = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('users')
  AND c.name = 'notify_online_orders'
IF @df2 IS NOT NULL
  EXEC('ALTER TABLE users DROP CONSTRAINT ' + @df2)
GO

ALTER TABLE users DROP COLUMN notify_online_orders
GO
