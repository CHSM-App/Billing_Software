-- =============================================================================
-- Rollback 016: add_item_variants
-- =============================================================================

DROP INDEX IX_bill_items_variant_id ON bill_items
GO

ALTER TABLE bill_items DROP CONSTRAINT FK_bill_items_variant
GO

ALTER TABLE bill_items DROP COLUMN variant_id
GO

DROP TABLE item_variants
GO
