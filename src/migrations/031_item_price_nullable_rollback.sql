-- =============================================================================
-- Rollback 031: item_price_nullable
-- =============================================================================
-- Restoring NOT NULL fails if any variant item has since been saved with a NULL
-- price, so give those rows a price first. 0 is used deliberately: it is an
-- obviously wrong figure that shows up immediately, rather than a plausible
-- number that would quietly bill customers the wrong amount.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

UPDATE items SET price = 0 WHERE price IS NULL
GO

ALTER TABLE items
    ALTER COLUMN price DECIMAL(10,2) NOT NULL
GO
