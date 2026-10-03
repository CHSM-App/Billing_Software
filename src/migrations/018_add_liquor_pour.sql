-- =============================================================================
-- Migration 018: add_liquor_pour
-- =============================================================================
-- Adds bar/liquor "peg pouring" support on top of item variants.
--
-- Model: a brand (e.g. "Signature") is one item; each serving size is a variant.
--   * SEALED sizes (180ml nip, 750ml, 1L, 2L) keep their own stock_quantity —
--     a whole-unit bottle count. Selling one deducts 1 from that count.
--   * POURED pegs (30/60/90ml by the glass) set is_poured = 1 and carry a
--     serving_ml. They have NO bottle count of their own; instead they draw ml
--     from an OPENED bottle of some sealed size.
--
-- A sealed size that pegs are poured from carries:
--   * bottle_ml          — full volume of one sealed bottle (e.g. 750)
--   * open_ml_remaining  — ml left in the currently-open bottle (the buffer)
-- When a peg is poured and the buffer can't cover it, one sealed bottle is
-- auto-opened: stock_quantity -= 1, open_ml_remaining += bottle_ml.
--
-- bill_items records, for a poured line, which sealed bottle it was poured from
-- (source_variant_id) and how many ml (pour_ml) so the sale can be reversed
-- exactly on void / replace.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE item_variants ADD
    serving_ml        DECIMAL(10,2) NULL,   -- poured peg: ml per serving (e.g. 90)
    is_poured         BIT           NOT NULL DEFAULT 0,
    bottle_ml         DECIMAL(10,2) NULL,   -- sealed size: full ml of one bottle
    open_ml_remaining DECIMAL(10,2) NULL    -- sealed size: ml left in open bottle
GO

-- Poured pegs never appear as a bill line's variant target for count-based
-- stock; instead the line points at the sealed bottle it was poured from.
ALTER TABLE bill_items ADD
    source_variant_id UNIQUEIDENTIFIER NULL,
    pour_ml           DECIMAL(10,2)    NULL
GO

ALTER TABLE bill_items ADD CONSTRAINT FK_bill_items_source_variant
    FOREIGN KEY (source_variant_id) REFERENCES item_variants (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

CREATE INDEX IX_bill_items_source_variant_id
    ON bill_items (source_variant_id) WHERE source_variant_id IS NOT NULL
GO
