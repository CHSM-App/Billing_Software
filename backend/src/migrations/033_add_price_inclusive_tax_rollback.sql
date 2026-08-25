-- =============================================================================
-- Rollback 033: add_price_inclusive_tax
-- =============================================================================
-- Dropping the column reverts every item to tax-exclusive pricing. Any item the
-- owner had marked inclusive will start billing tax ON TOP of its MRP, so its
-- prices must be re-entered as net values before this rollback is applied.
--
-- The DEFAULT constraint must be dropped before the column it defaults.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

-- Narrowing back to 2dp rounds any stored net rate from an inclusive-priced
-- line. Those bills are already finalized and their totals are stored
-- independently, so no total changes — only the per-line rate loses precision.
ALTER TABLE bill_items
    ALTER COLUMN unit_price DECIMAL(10,2) NOT NULL
GO

ALTER TABLE items
    DROP CONSTRAINT DF_items_price_inclusive_tax
GO

ALTER TABLE items
    DROP COLUMN price_inclusive_tax
GO
