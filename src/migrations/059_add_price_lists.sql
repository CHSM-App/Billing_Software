-- =============================================================================
-- Migration 059: price lists — "Party", "Wholesale", "AC section"
--
-- A list is an optional % rule (adjust_pct, e.g. +10) plus optional fixed
-- prices per item or per size (price_list_items). The cashier picks one on the
-- order card and the app sends the list price as each line's price_override,
-- so bill pricing itself is untouched: bill_items.unit_price stays the truth.
--
-- price_list_items.item_id / variant_id carry no FK on purpose: items and
-- item_variants already cascade into each other, and SQL Server refuses a
-- second cascade path. GET /api/price-lists joins them back to active rows.
--
-- bills.price_list_id only remembers which list a held bill was opened with.
-- No FK, so the rollback is a plain DROP COLUMN.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('price_lists') IS NULL
  CREATE TABLE price_lists (
    id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id UNIQUEIDENTIFIER NOT NULL,
    name        NVARCHAR(60)     NOT NULL,
    adjust_pct  DECIMAL(6,2)     NULL,
    is_active   BIT              NOT NULL DEFAULT 1,
    created_at  DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_price_lists_business
      FOREIGN KEY (business_id) REFERENCES businesses (id)
  )
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_price_lists_business_id')
  CREATE INDEX IX_price_lists_business_id ON price_lists (business_id)
GO

IF OBJECT_ID('price_list_items') IS NULL
  CREATE TABLE price_list_items (
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    price_list_id UNIQUEIDENTIFIER NOT NULL,
    item_id       UNIQUEIDENTIFIER NOT NULL,
    variant_id    UNIQUEIDENTIFIER NULL,
    price         DECIMAL(12,2)    NOT NULL,

    CONSTRAINT FK_price_list_items_list
      FOREIGN KEY (price_list_id) REFERENCES price_lists (id) ON DELETE CASCADE
  )
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_price_list_items_line')
  CREATE UNIQUE INDEX UQ_price_list_items_line
    ON price_list_items (price_list_id, item_id, variant_id)
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bills') AND name = 'price_list_id'
)
  ALTER TABLE bills ADD price_list_id UNIQUEIDENTIFIER NULL
GO
