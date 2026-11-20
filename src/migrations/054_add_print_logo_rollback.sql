-- Drops what migration 054 added. The logo stops printing on bills.
IF EXISTS (
  SELECT 1 FROM sys.default_constraints WHERE name = 'DF_businesses_print_logo'
)
  ALTER TABLE businesses DROP CONSTRAINT DF_businesses_print_logo
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'print_logo'
)
  ALTER TABLE businesses DROP COLUMN print_logo
GO
