-- =============================================================================
-- Migration 044: add_stock_batches — batch-wise stock with per-batch cost
--
-- Every vendor-bill line that receives an item or size now also creates a
-- stock batch carrying its own purchase cost and an optional batch/lot number.
-- The cashier picks the batch while billing, and the bill line snapshots that
-- batch's cost, so reports can compute real cost of goods and profit.
--
-- stock_quantity on items / item_variants stays the TOTAL and the source of
-- truth (oversell guard, offline cache, low-stock alerts all keep reading it).
-- Batches only split it: stock_quantity - SUM(qty_remaining) is "opening"
-- stock — whatever existed before this migration or was added by hand — with
-- no known cost.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

CREATE TABLE stock_batches (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id     UNIQUEIDENTIFIER NOT NULL,

    -- Exactly one of these is set (see CK below).
    item_id         UNIQUEIDENTIFIER NULL,
    variant_id      UNIQUEIDENTIFIER NULL,

    -- The purchase this batch came from. No FK: vendor_bills already cascades
    -- from businesses, and a second path here is rejected by MSSQL. The route
    -- deletes a bill's batches itself before deleting the bill.
    vendor_bill_id  UNIQUEIDENTIFIER NULL,

    batch_no        NVARCHAR(50)     NULL,
    -- Net (pre-tax) cost per unit, after the vendor's bill-level discount.
    unit_cost       DECIMAL(12,4)    NOT NULL,
    qty_received    DECIMAL(10,2)    NOT NULL,
    qty_remaining   DECIMAL(10,2)    NOT NULL,
    received_date   DATE             NOT NULL,
    created_at      DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_stock_batches_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    CONSTRAINT CK_stock_batches_single_target CHECK (
        (CASE WHEN item_id    IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN variant_id IS NOT NULL THEN 1 ELSE 0 END) = 1
    ),

    CONSTRAINT CK_stock_batches_qty CHECK (qty_remaining >= 0)
)
GO

-- Open batches of one item/size, oldest first — the picker and the trim.
CREATE INDEX IX_stock_batches_open
    ON stock_batches (item_id, variant_id, received_date)
    INCLUDE (qty_remaining, unit_cost)
    WHERE qty_remaining > 0
GO

CREATE INDEX IX_stock_batches_vendor_bill
    ON stock_batches (vendor_bill_id)
    WHERE vendor_bill_id IS NOT NULL
GO

CREATE INDEX IX_stock_batches_business
    ON stock_batches (business_id, received_date)
GO

-- Kept on the purchase line so an edit of the bill can recreate its batches.
ALTER TABLE vendor_bill_items ADD batch_no NVARCHAR(50) NULL
GO

-- The batch a bill line was sold from, and its cost at the time. No FK: the
-- batch may later be deleted with its vendor bill, and the cost snapshot must
-- survive that. NULL batch_id = opening stock (or an untracked item).
ALTER TABLE bill_items ADD
    batch_id  UNIQUEIDENTIFIER NULL,
    unit_cost DECIMAL(12,4)    NULL
GO
