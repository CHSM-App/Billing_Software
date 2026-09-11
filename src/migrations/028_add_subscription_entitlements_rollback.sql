-- =============================================================================
-- Rollback 028: add_subscription_entitlements
--
-- Each column carries a system-named DEFAULT constraint, which must be dropped
-- before the column itself. The constraint name is server-generated, so look it
-- up per column and drop it via dynamic SQL, then drop the column.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

DECLARE @sql NVARCHAR(MAX)

-- max_staff
SELECT @sql = 'ALTER TABLE subscriptions DROP CONSTRAINT ' + dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('subscriptions') AND c.name = 'max_staff'
IF @sql IS NOT NULL EXEC sp_executesql @sql
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('subscriptions') AND name = 'max_staff')
    ALTER TABLE subscriptions DROP COLUMN max_staff
GO

DECLARE @sql2 NVARCHAR(MAX)

-- allow_mobile
SELECT @sql2 = 'ALTER TABLE subscriptions DROP CONSTRAINT ' + dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('subscriptions') AND c.name = 'allow_mobile'
IF @sql2 IS NOT NULL EXEC sp_executesql @sql2
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_mobile')
    ALTER TABLE subscriptions DROP COLUMN allow_mobile
GO

DECLARE @sql3 NVARCHAR(MAX)

-- allow_desktop
SELECT @sql3 = 'ALTER TABLE subscriptions DROP CONSTRAINT ' + dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('subscriptions') AND c.name = 'allow_desktop'
IF @sql3 IS NOT NULL EXEC sp_executesql @sql3
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_desktop')
    ALTER TABLE subscriptions DROP COLUMN allow_desktop
GO
