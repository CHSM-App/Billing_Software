-- =============================================================================
-- Migration 012: add_low_stock_threshold
-- =============================================================================
ALTER TABLE items ADD low_stock_threshold DECIMAL(10,2) NULL
GO
