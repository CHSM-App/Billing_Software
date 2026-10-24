-- =============================================================================
-- Migration 020: recipe_quantity_precision
-- =============================================================================
-- Widens item_recipes.quantity so recipe amounts entered in grams/ml against a
-- material stocked in kg/litre keep precision after conversion. A 5 g pinch of a
-- kg-stocked spice stores as 0.005 kg; DECIMAL(12,4) leaves headroom below that.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

ALTER TABLE item_recipes ALTER COLUMN quantity DECIMAL(12,4) NOT NULL
GO
