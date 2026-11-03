-- =============================================================================
-- Rollback 025: add_gst_hsn
-- =============================================================================
-- Drop the gst_enabled default constraint (auto-named) before the column.
-- =============================================================================

DECLARE @df NVARCHAR(200)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('businesses')
  AND c.name = 'gst_enabled'
IF @df IS NOT NULL
  EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df)
GO

ALTER TABLE businesses DROP COLUMN gst_enabled
GO

ALTER TABLE businesses DROP COLUMN default_sac_code
GO

ALTER TABLE items DROP COLUMN hsn_code
GO

ALTER TABLE bill_items DROP COLUMN hsn_code
GO
