-- =============================================================================
-- Migration 082: sales returns (credit notes)
--
-- A customer returns some items (or quantity) from a settled bill. The return
-- is a credit note: its own number (CN-0001 per business), what it gives back
-- (taxable value + GST, at the bill's own prices and discount), and how the
-- money went back (cash / UPI / card / other, or "credit" = taken off what a
-- credit bill still owes). Stock and batch quantities come back; reports and
-- GST returns are net of it (routes/bills.js, routes/reports.js).
--
--   * sales_returns       — one row per credit note.
--   * sales_return_items  — the bill lines returned, and how many of each.
--
-- No FK from sales_returns.bill_id to bills: both cascade from businesses and
-- a second path is rejected by MSSQL (see 074's scan_id). Every lookup joins
-- on business_id too.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

CREATE TABLE sales_returns (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id         UNIQUEIDENTIFIER NOT NULL,
    bill_id             UNIQUEIDENTIFIER NOT NULL,
    -- CN-0001: numbered per business, never reused.
    return_seq          INT              NOT NULL,
    return_number       NVARCHAR(30)     NOT NULL,
    returned_at         DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    reason              NVARCHAR(200)    NULL,
    refund_mode         NVARCHAR(20)     NOT NULL,
    -- Taxable value (after the bill's discount), GST, and the two together.
    -- CGST/SGST are the halves of tax_amount, as on the bill itself.
    subtotal            DECIMAL(12,2)    NOT NULL,
    tax_amount          DECIMAL(12,2)    NOT NULL,
    total               DECIMAL(12,2)    NOT NULL,
    created_by_user_id  UNIQUEIDENTIFIER NOT NULL,

    CONSTRAINT FK_sales_returns_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    CONSTRAINT CK_sales_returns_refund_mode
        CHECK (refund_mode IN ('cash', 'upi', 'card', 'other', 'credit'))
)
GO

CREATE UNIQUE INDEX UQ_sales_returns_seq ON sales_returns (business_id, return_seq)
GO

CREATE INDEX IX_sales_returns_period ON sales_returns (business_id, returned_at)
GO

CREATE INDEX IX_sales_returns_bill ON sales_returns (bill_id)
GO

CREATE TABLE sales_return_items (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    return_id       UNIQUEIDENTIFIER NOT NULL,
    -- The bill line returned. A settled bill's lines never change, so this
    -- stays valid; it caps how much of a line can be returned in total.
    bill_item_id    UNIQUEIDENTIFIER NOT NULL,
    item_id         UNIQUEIDENTIFIER NULL,
    variant_id      UNIQUEIDENTIFIER NULL,
    item_name       NVARCHAR(200)    NOT NULL,
    quantity        DECIMAL(10,2)    NOT NULL,
    unit_price      DECIMAL(12,4)    NOT NULL,
    tax_rate        DECIMAL(5,2)     NULL,
    hsn_code        NVARCHAR(10)     NULL,
    -- This line's share of the credit note: taxable value and GST.
    net_amount      DECIMAL(12,2)    NOT NULL,
    tax_amount      DECIMAL(12,2)    NOT NULL,
    -- The sale line's cost snapshot, so profit gives the cost back too.
    unit_cost       DECIMAL(12,4)    NULL,

    CONSTRAINT FK_sales_return_items_return
        FOREIGN KEY (return_id) REFERENCES sales_returns (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    CONSTRAINT CK_sales_return_items_qty CHECK (quantity > 0)
)
GO

CREATE INDEX IX_sales_return_items_bill_item ON sales_return_items (bill_item_id)
GO

CREATE INDEX IX_sales_return_items_return ON sales_return_items (return_id)
GO
