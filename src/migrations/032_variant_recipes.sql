-- =============================================================================
-- Migration 032: variant_recipes
-- =============================================================================
-- A half plate must not consume a full plate's raw materials. Recipes move from
-- per-ITEM to per-(item, variant) so each size carries its own consumption.
--
-- Back-compat: variant_id NULL means "the recipe of an item that has no sizes" —
-- exactly what every existing row already is. No existing row is read, rewritten
-- or backfilled, and a bill line with no variant_id keeps matching those rows
-- unchanged.
--
-- The rule the application enforces:
--   * item WITHOUT variants -> its recipe lives on the item (variant_id NULL)
--   * item WITH variants    -> each size has its own recipe (variant_id set)
-- An item is never in both states, so a line matches exactly one set of rows.
-- A sized line NEVER falls back to the item-level rows — mirroring the price
-- rule from migration 031, where a sized item's own price is meaningless.
--
-- ON DELETE NO ACTION rather than CASCADE: variants are SOFT-deleted
-- (is_active = 0) and never removed, so a cascade could not fire anyway. This
-- also matches the deliberate choice already made for raw_material_id.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE item_recipes ADD variant_id UNIQUEIDENTIFIER NULL
GO

ALTER TABLE item_recipes ADD CONSTRAINT FK_item_recipes_variant
    FOREIGN KEY (variant_id) REFERENCES item_variants (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

-- The old index allowed one row per (item, material). Now that a material may
-- appear once per size, uniqueness must include the size.
DROP INDEX UQ_item_recipes_item_raw ON item_recipes
GO

-- SQL Server treats NULLs as EQUAL for uniqueness purposes, so this still
-- permits only one item-level row per (item, material) — the old guarantee,
-- preserved — while allowing one row per material per size alongside it.
CREATE UNIQUE INDEX UQ_item_recipes_item_variant_raw
    ON item_recipes (item_id, variant_id, raw_material_id)
GO

CREATE INDEX IX_item_recipes_variant_id ON item_recipes (variant_id)
GO
