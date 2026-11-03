-- =============================================================================
-- Rollback for Migration 023: add_whatsapp_mode
-- Drops the whatsapp_mode column (and its DEFAULT constraint) from businesses.
-- =============================================================================

DECLARE @df NVARCHAR(128)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('businesses') AND c.name = 'whatsapp_mode'
IF @df IS NOT NULL EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df)
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('businesses') AND name = 'whatsapp_mode')
  ALTER TABLE businesses DROP COLUMN whatsapp_mode
GO
