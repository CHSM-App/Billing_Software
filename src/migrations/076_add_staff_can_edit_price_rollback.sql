-- Drops what migration 076 added. Staff go back to editing prices freely.
-- The auto-named DEFAULT constraint must go before its column.
DECLARE @df NVARCHAR(200)
SELECT @df = dc.name
FROM sys.default_constraints dc
JOIN sys.columns c
  ON c.default_object_id = dc.object_id
WHERE dc.parent_object_id = OBJECT_ID('businesses')
  AND c.name = 'staff_can_edit_price'
IF @df IS NOT NULL
  EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df)
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'staff_can_edit_price'
)
  ALTER TABLE businesses DROP COLUMN staff_can_edit_price
GO
