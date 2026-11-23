-- =============================================================================
-- Rollback 032: variant_recipes
-- =============================================================================
-- DESTRUCTIVE: per-size recipe rows are deleted.
--
-- They must go before the old unique index can be rebuilt — two sizes of one
-- dish using the same raw material are two rows that collide on
-- (item_id, raw_material_id) once variant_id is gone.
--
-- Item-level rows (variant_id IS NULL) are untouched, so pre-032 behaviour
-- returns intact.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

DELETE FROM item_recipes WHERE variant_id IS NOT NULL
GO

DROP INDEX UQ_item_recipes_item_variant_raw ON item_recipes
GO

DROP INDEX IX_item_recipes_variant_id ON item_recipes
GO

ALTER TABLE item_recipes DROP CONSTRAINT FK_item_recipes_variant
GO

ALTER TABLE item_recipes DROP COLUMN variant_id
GO

CREATE UNIQUE INDEX UQ_item_recipes_item_raw
    ON item_recipes (item_id, raw_material_id)
GO
