-- =============================================================================
-- Rollback 036: add_item_major_category
-- =============================================================================
-- Drops the coarse grouping level. Every item keeps its `category` — that column
-- was never touched — so billing and the item sheets fall straight back to the
-- single flat category list. The only loss is which group each category
-- belonged to, which must be re-entered if the migration is re-applied.
--
-- No default constraint to drop: the column was added plain NULL.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

ALTER TABLE items
    DROP COLUMN major_category
GO
