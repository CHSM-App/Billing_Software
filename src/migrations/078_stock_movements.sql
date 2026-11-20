-- =============================================================================
-- Migration 078: stock ledger + sale cost snapshot (Opening/Closing stock and
-- item-wise profit reports)
--
--   * stock_movements — one signed row per change to items/item_variants
--     .stock_quantity. closing(D) = SUM(qty) dated <= D, opening(D) = < D.
--   * bill_items.unit_cost — the item's buying price (ex-tax, weighted average
--     of purchase bills) frozen at sale time. NULL = never purchased / sale
--     predates this migration.
--   * businesses.day_end_hour — shops open past midnight book those sales to
--     the previous business day (0 = calendar day).
--
-- Backfill: one 'opening' row per tracked item/size = its stock right now,
-- dated YESTERDAY (IST) so today's opening equals stock at migration time.
-- History before that is not reconstructable.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('stock_movements') IS NULL
CREATE TABLE stock_movements (
  id             BIGINT IDENTITY(1,1) PRIMARY KEY,
  business_id    UNIQUEIDENTIFIER NOT NULL,
  -- Exactly one is set: a sized item's stock lives on the size.
  item_id        UNIQUEIDENTIFIER NULL,
  variant_id     UNIQUEIDENTIFIER NULL,
  movement_date  DATE             NOT NULL,
  movement_type  NVARCHAR(20)     NOT NULL,
  qty            DECIMAL(12,3)    NOT NULL,
  ref_id         UNIQUEIDENTIFIER NULL,
  created_at     DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT CK_stock_movements_type
    CHECK (movement_type IN ('opening','purchase','sale','void','adjust')),
  CONSTRAINT CK_stock_movements_target
    CHECK ((item_id IS NULL AND variant_id IS NOT NULL)
        OR (item_id IS NOT NULL AND variant_id IS NULL))
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_movements_biz_date')
  CREATE INDEX IX_stock_movements_biz_date
    ON stock_movements (business_id, movement_date) INCLUDE (item_id, variant_id, movement_type, qty)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_movements_ref')
  CREATE INDEX IX_stock_movements_ref ON stock_movements (ref_id) WHERE ref_id IS NOT NULL
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('bill_items') AND name = 'unit_cost')
  ALTER TABLE bill_items ADD unit_cost DECIMAL(12,4) NULL
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('businesses') AND name = 'day_end_hour')
  ALTER TABLE businesses ADD day_end_hour TINYINT NOT NULL
    CONSTRAINT DF_businesses_day_end_hour DEFAULT 0
GO

IF NOT EXISTS (SELECT 1 FROM stock_movements WHERE movement_type = 'opening')
BEGIN
  INSERT INTO stock_movements (business_id, item_id, movement_date, movement_type, qty)
  SELECT i.business_id, i.id,
         DATEADD(DAY, -1, CAST(DATEADD(MINUTE, 330, SYSUTCDATETIME()) AS DATE)),
         'opening', i.stock_quantity
  FROM items i WHERE i.stock_quantity IS NOT NULL AND i.stock_quantity <> 0;

  INSERT INTO stock_movements (business_id, variant_id, movement_date, movement_type, qty)
  SELECT i.business_id, v.id,
         DATEADD(DAY, -1, CAST(DATEADD(MINUTE, 330, SYSUTCDATETIME()) AS DATE)),
         'opening', v.stock_quantity
  FROM item_variants v JOIN items i ON i.id = v.item_id
  WHERE v.stock_quantity IS NOT NULL AND v.stock_quantity <> 0;
END
GO
