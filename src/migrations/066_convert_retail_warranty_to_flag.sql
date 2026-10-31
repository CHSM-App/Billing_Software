-- =============================================================================
-- Migration 066: convert_retail_warranty_to_flag
-- =============================================================================
-- Retires the 'retail_warranty' business_type in favour of a toggleable
-- feature flag, warranty_enabled, mirroring inventory_enabled exactly. The
-- sign-up picker and VALID_BUSINESS_TYPES in routes/auth.js no longer offer
-- 'retail_warranty', so no new business can be created with it — this
-- converts the ones that already exist, folding them into plain 'retail'
-- with the new flag set, so the feature becomes something any retail shop
-- can turn on or off from Settings instead of a permanent sign-up choice.
--
-- WHY THIS IS SAFE: every table that holds warranty data (items,
-- warranties, warranty_field_templates) is keyed by business_id, which this
-- migration never touches — only the business's own type/flag columns
-- change. Nothing is lost.
--
-- WHY THIS ROLLBACK CAN BE EXACT (unlike migration 041's no-op rollback):
-- the new warranty_enabled column itself records exactly which businesses
-- were converted, so — as long as no business has used the Settings toggle
-- since this ran — the rollback can identify and revert them precisely. See
-- the rollback file for the caveat once real usage begins.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE businesses
    ADD warranty_enabled BIT NOT NULL CONSTRAINT DF_businesses_warranty_enabled DEFAULT 0
GO

UPDATE businesses
SET warranty_enabled = 1, business_type = 'retail'
WHERE business_type = 'retail_warranty'
GO
