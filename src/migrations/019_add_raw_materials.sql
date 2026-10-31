-- =============================================================================
-- Migration 019: add_raw_materials
-- =============================================================================
-- Adds restaurant raw-material inventory (a Bill of Materials / recipe system).
--
-- Model:
--   * raw_materials — stock-tracked ingredients (bun, patty, cheese, oil). They
--     are NEVER shown on the billing page; only sellable items are billed.
--   * item_recipes — links a sellable item (e.g. "Burger") to the raw materials
--     it consumes, with the quantity used per ONE unit of the item.
--
-- On sale: selling N of an item deducts, for each recipe row, (quantity * N)
-- from that raw material's stock. Low-stock alerts fire per raw material.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

CREATE TABLE raw_materials (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id         UNIQUEIDENTIFIER NOT NULL,
    name                NVARCHAR(200)    NOT NULL,
    unit                NVARCHAR(20)     NOT NULL DEFAULT 'piece',  -- piece, g, kg, ml, litre
    stock_quantity      DECIMAL(10,2)    NULL,                      -- NULL = untracked
    low_stock_threshold DECIMAL(10,2)    NULL,
    is_active           BIT              NOT NULL DEFAULT 1,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_raw_materials_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE
)
GO

CREATE INDEX IX_raw_materials_business_id ON raw_materials (business_id)
GO

-- Recipe rows: which raw materials an item consumes, and how much per unit sold.
CREATE TABLE item_recipes (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    item_id         UNIQUEIDENTIFIER NOT NULL,
    raw_material_id UNIQUEIDENTIFIER NOT NULL,
    quantity        DECIMAL(10,3)    NOT NULL,   -- amount of raw material per 1 item
    created_at      DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_item_recipes_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,
    -- No cascade on the raw material: deleting one that is still used by a recipe
    -- must be blocked so we never silently break a dish's consumption.
    CONSTRAINT FK_item_recipes_raw_material
        FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
)
GO

CREATE INDEX IX_item_recipes_item_id ON item_recipes (item_id)
GO

CREATE INDEX IX_item_recipes_raw_material_id ON item_recipes (raw_material_id)
GO

-- One raw material appears at most once per item's recipe.
CREATE UNIQUE INDEX UQ_item_recipes_item_raw
    ON item_recipes (item_id, raw_material_id)
GO
