-- =============================================================================
-- Migration 062: add_item_warranty_fields
-- =============================================================================
-- Supports the "Retail & Warranty" business type (tyre/battery/electronics
-- shops). An item can be flagged as carrying a warranty, with a default
-- period in months that seeds each warranty record created when it's sold.
--
-- Both NULL-able/defaulted with no backfill needed: every existing item
-- defaults to warranty_eligible = 0, so retail/restaurant businesses see no
-- behavioural change at all.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE items
    ADD warranty_eligible BIT NOT NULL CONSTRAINT DF_items_warranty_eligible DEFAULT 0
GO

ALTER TABLE items
    ADD default_warranty_months INT NULL
GO
