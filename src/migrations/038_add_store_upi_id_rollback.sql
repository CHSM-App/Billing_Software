-- =============================================================================
-- Rollback for Migration 038: add_store_upi_id
-- =============================================================================
IF COL_LENGTH('businesses', 'store_upi_id') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN store_upi_id
GO
