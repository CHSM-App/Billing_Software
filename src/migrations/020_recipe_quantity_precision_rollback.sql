-- =============================================================================
-- Rollback 020: recipe_quantity_precision
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

ALTER TABLE item_recipes ALTER COLUMN quantity DECIMAL(10,3) NOT NULL
GO
