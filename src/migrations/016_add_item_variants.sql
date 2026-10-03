-- =============================================================================
-- Migration 016: add_item_variants
-- =============================================================================
-- Adds product variants (e.g. sizes S/M/L/XL) with independent stock, optional
-- price delta and barcode. A bill line may reference a variant; when it does,
-- stock is tracked against the variant rather than the parent item.
-- =============================================================================

CREATE TABLE item_variants (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    item_id             UNIQUEIDENTIFIER NOT NULL,
    label               NVARCHAR(50)     NOT NULL,          -- 'S', 'M', 'L', 'XL'
    price               DECIMAL(10,2)    NULL,              -- absolute price; NULL = use item.price
    barcode             NVARCHAR(100)    NULL,
    stock_quantity      DECIMAL(10,2)    NULL,               -- NULL = untracked
    low_stock_threshold DECIMAL(10,2)    NULL,
    sort_order          INT              NOT NULL DEFAULT 0,
    is_active           BIT              NOT NULL DEFAULT 1,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_item_variants_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE NO ACTION ON DELETE CASCADE
)
GO

CREATE INDEX IX_item_variants_item_id ON item_variants (item_id)
GO

-- One barcode per business is enforced at the item level; variant barcodes are
-- unique per item (NULLs excluded).
CREATE UNIQUE INDEX UQ_item_variants_item_barcode
    ON item_variants (item_id, barcode)
    WHERE barcode IS NOT NULL
GO

-- Bill lines may point at a specific variant. SET NULL on delete mirrors the
-- existing item_id behaviour: the item_name snapshot on bill_items is preserved.
ALTER TABLE bill_items ADD variant_id UNIQUEIDENTIFIER NULL
GO

ALTER TABLE bill_items ADD CONSTRAINT FK_bill_items_variant
    FOREIGN KEY (variant_id) REFERENCES item_variants (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

CREATE INDEX IX_bill_items_variant_id ON bill_items (variant_id) WHERE variant_id IS NOT NULL
GO
