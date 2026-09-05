-- =============================================================================
-- Migration 015: add_item_unit
-- =============================================================================
-- Adds a unit-of-measure column to items so products can be priced/sold by
-- weight or volume (kg, g, litre, ...) rather than only whole pieces.
-- Existing rows default to 'piece' to preserve current behaviour.
-- =============================================================================

ALTER TABLE items ADD unit NVARCHAR(20) NOT NULL DEFAULT 'piece'
GO
