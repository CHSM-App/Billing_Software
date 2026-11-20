-- =============================================================================
-- Migration 081: stock/batch correctness fixes (all additive)
--
--   * items.is_service — "Service (no stock)": a purchase never starts tracking
--     stock for it (Nitrogen Filling, fitting charges ...).
--   * items / item_variants.buying_price — optional cost per unit before GST,
--     the profit cost for shops that never enter purchase bills.
--   * bill_items.stock_taken — did this line take stock? Online/QR order lines
--     never did, so a void or edit must not give stock back for them.
--   * stock_batches.qty_closed — stock that left the batches without being
--     lost (item untracked, made a service, given sizes, deleted). Not a loss.
--   * businesses.staff_see_cost — may staff see purchase cost while billing?
--     1 = today's behaviour.
--   * stock_movements accepts 'return' (sales returns).
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE items ADD is_service BIT NOT NULL CONSTRAINT DF_items_is_service DEFAULT 0
GO

ALTER TABLE items ADD buying_price DECIMAL(12,4) NULL
GO

ALTER TABLE item_variants ADD buying_price DECIMAL(12,4) NULL
GO

ALTER TABLE bill_items ADD stock_taken BIT NOT NULL CONSTRAINT DF_bill_items_stock_taken DEFAULT 1
GO

-- Online and QR order lines (source 'customer') were inserted without taking
-- stock.
UPDATE bill_items SET stock_taken = 0 WHERE source = 'customer'
GO

ALTER TABLE stock_batches ADD qty_closed DECIMAL(10,2) NOT NULL
  CONSTRAINT DF_stock_batches_qty_closed DEFAULT 0
GO

ALTER TABLE stock_batches DROP COLUMN qty_remaining
GO

ALTER TABLE stock_batches ADD qty_remaining AS (qty_received - qty_sold - qty_lost - qty_closed)
GO

ALTER TABLE businesses ADD staff_see_cost BIT NOT NULL
  CONSTRAINT DF_businesses_staff_see_cost DEFAULT 1
GO

ALTER TABLE stock_movements DROP CONSTRAINT CK_stock_movements_type
GO

ALTER TABLE stock_movements ADD CONSTRAINT CK_stock_movements_type
  CHECK (movement_type IN ('opening','purchase','sale','void','adjust','return'))
GO
