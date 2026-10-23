-- =============================================================================
-- Rollback 063: add_warranty_field_templates
-- =============================================================================
-- Drops the per-category custom field definitions. Existing warranties keep
-- whatever extra_data they already carry (that lives on migration 064's
-- table, untouched); only the ability to author new templates is removed.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

DROP TABLE IF EXISTS warranty_field_templates
GO
