-- =============================================================================
-- Rollback 062: add_item_warranty_fields
-- =============================================================================
-- Drops the warranty flag and default period. Any item marked
-- warranty_eligible simply stops being distinguishable that way; the
-- warranties table (migration 064) is untouched, so existing warranty
-- records are unaffected.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

ALTER TABLE items
    DROP COLUMN default_warranty_months
GO

ALTER TABLE items
    DROP CONSTRAINT DF_items_warranty_eligible
GO

ALTER TABLE items
    DROP COLUMN warranty_eligible
GO
