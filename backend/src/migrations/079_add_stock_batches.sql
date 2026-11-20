-- =============================================================================
-- Migration 079: stock batches — purchase cost per lot, for real profit
--
-- Every purchase line of a tracked item/size puts its stock into a batch with
-- a known cost; every sale takes stock from batches (oldest first, or the one
-- the cashier picked), so reports can subtract what the goods cost.
-- src/batches.js holds the logic. Off by default: a shop only gets batches
-- after the owner turns on "Maintain batches" (needs inventory on).
--
--   * businesses.batch_tracking_enabled — the owner's switch.
--   * stock_batches — one row per lot. items/item_variants.stock_quantity stay
--     the TOTAL; batches only split it. opening (uncosted) stock =
--     stock_quantity - SUM(qty_remaining).
--   * stock_batch_allocations — which batches a sale bill took stock from.
--     Keyed by bill, not bill line: update-items re-inserts every line.
--   * vendor_bill_items.batch_id — the batch a purchase line went into.
--   * bill_items.batch_id — the cashier's preferred batch (NULL = automatic).
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'batch_tracking_enabled'
)
  ALTER TABLE businesses ADD batch_tracking_enabled BIT NOT NULL DEFAULT 0
GO

CREATE TABLE stock_batches (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id     UNIQUEIDENTIFIER NOT NULL,

    -- Exactly one (CK below): a size's batches name the size, not its item.
    item_id         UNIQUEIDENTIFIER NULL,
    variant_id      UNIQUEIDENTIFIER NULL,

    -- Shown as B-0001; numbered per business by batches.receive.
    batch_seq       INT              NOT NULL,
    -- The supplier's own lot/batch number, when the owner types one.
    lot_no          NVARCHAR(50)     NULL,

    -- Cost of one unit as it reached the shelf: net of the vendor's bill
    -- discount, plus GST when it can't be claimed back, spread over free goods.
    unit_cost       DECIMAL(12,4)    NOT NULL,
    received_date   DATE             NOT NULL,
    -- The purchase that opened it. No FK: vendor_bills already cascades from
    -- businesses and a second path is rejected by MSSQL (see 074's scan_id).
    created_by_vendor_bill_id UNIQUEIDENTIFIER NULL,
    created_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),

    -- Three counters, so a purchase edit only touches what was received and
    -- sold units are never counted twice.
    qty_received    DECIMAL(10,2)    NOT NULL DEFAULT 0,
    qty_sold        DECIMAL(10,2)    NOT NULL DEFAULT 0,
    -- Written off: stock corrected down by hand below what batches held.
    qty_lost        DECIMAL(10,2)    NOT NULL DEFAULT 0,
    qty_remaining   AS (qty_received - qty_sold - qty_lost),

    CONSTRAINT FK_stock_batches_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    CONSTRAINT CK_stock_batches_single_target CHECK (
        (CASE WHEN item_id    IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN variant_id IS NOT NULL THEN 1 ELSE 0 END) = 1
    )
)
GO

CREATE UNIQUE INDEX UQ_stock_batches_seq
    ON stock_batches (business_id, batch_seq)
GO

CREATE INDEX IX_stock_batches_item
    ON stock_batches (business_id, item_id) WHERE item_id IS NOT NULL
GO

CREATE INDEX IX_stock_batches_variant
    ON stock_batches (business_id, variant_id) WHERE variant_id IS NOT NULL
GO

-- No FKs to bills / stock_batches: both already cascade from businesses.
-- batches.returnBill removes a bill's rows itself.
CREATE TABLE stock_batch_allocations (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id     UNIQUEIDENTIFIER NOT NULL,
    bill_id         UNIQUEIDENTIFIER NOT NULL,
    batch_id        UNIQUEIDENTIFIER NOT NULL,
    item_id         UNIQUEIDENTIFIER NULL,
    variant_id      UNIQUEIDENTIFIER NULL,
    quantity        DECIMAL(10,2)    NOT NULL,

    CONSTRAINT FK_stock_batch_allocations_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE
)
GO

CREATE INDEX IX_stock_batch_allocations_bill
    ON stock_batch_allocations (bill_id)
GO

CREATE INDEX IX_stock_batch_allocations_batch
    ON stock_batch_allocations (batch_id)
GO

ALTER TABLE vendor_bill_items ADD batch_id UNIQUEIDENTIFIER NULL
GO

ALTER TABLE bill_items ADD batch_id UNIQUEIDENTIFIER NULL
GO
