-- =============================================================================
-- Rollback 068: add_quotations
-- =============================================================================

IF OBJECT_ID('quotations') IS NOT NULL
  DROP TABLE quotations
GO

IF EXISTS (
  SELECT 1 FROM sys.default_constraints WHERE name = 'DF_businesses_quotations_enabled'
)
  ALTER TABLE businesses DROP CONSTRAINT DF_businesses_quotations_enabled
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'quotations_enabled'
)
  ALTER TABLE businesses DROP COLUMN quotations_enabled
GO
