-- =============================================================================
-- Migration 034: add_vendor_bills
-- =============================================================================
-- Adds vendor bills (purchase invoices) — the inward-supply counterpart to
-- `bills`. Until now the app had no purchase data at all: `expenses` records a
-- category and an amount, which is enough for a spend report but cannot support
-- GST input tax credit (ITC). ITC needs the supplier's GSTIN, their invoice
-- number and date, and the taxable/tax split, so the credit claimed can be
-- matched against the supplier's own outward filing (GSTR-2B).
--
-- Model:
--   * vendor_bills      — the purchase invoice header (money + GST + vendor)
--   * vendor_bill_items — its lines. A line may target an item, an item
--     variant, or a raw material; receiving it INCREASES that target's stock.
--     A line may also target nothing — freight and service charges carry real
--     ITC but have no stock to receive.
--
-- Deliberately separate from `expenses`: expenses are flat amounts with no
-- lines, no stock effect and no tax split. Both count toward net_profit.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

CREATE TABLE vendor_bills (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id         UNIQUEIDENTIFIER NOT NULL,

    -- Vendor. GSTIN NULL = unregistered vendor: they cannot pass on credit, so
    -- such a purchase contributes ZERO ITC no matter what tax was charged.
    vendor_name         NVARCHAR(200)    NOT NULL,
    vendor_gstin        NVARCHAR(15)     NULL,
    vendor_state        NVARCHAR(100)    NULL,

    -- The supplier's own invoice identity. Purchases are dated by the vendor's
    -- invoice date, not by when they were entered, so every report filters on
    -- invoice_date rather than created_at.
    invoice_number      NVARCHAR(50)     NOT NULL,
    invoice_date        DATE             NOT NULL,

    -- Money. subtotal is the NET taxable value; total is the invoice value.
    subtotal            DECIMAL(12,2)    NOT NULL DEFAULT 0,
    tax_amount          DECIMAL(12,2)    NOT NULL DEFAULT 0,
    cgst_amount         DECIMAL(12,2)    NOT NULL DEFAULT 0,
    sgst_amount         DECIMAL(12,2)    NOT NULL DEFAULT 0,
    igst_amount         DECIMAL(12,2)    NOT NULL DEFAULT 0,
    cess_amount         DECIMAL(12,2)    NOT NULL DEFAULT 0,
    discount_amount     DECIMAL(12,2)    NOT NULL DEFAULT 0,
    round_off           DECIMAL(10,2)    NOT NULL DEFAULT 0,
    total               DECIMAL(12,2)    NOT NULL DEFAULT 0,

    -- An inter-state purchase attracts IGST instead of a CGST/SGST split. The
    -- flag is STORED rather than re-derived from the GSTIN state code, so a
    -- correction (bill-to/ship-to cases) stays a data fix, not a code change.
    is_interstate       BIT              NOT NULL DEFAULT 0,
    -- 0 = blocked credit under s.17(5) (motor vehicles, personal use, …).
    -- Reported in the GSTR-2 summary but excluded from claimable ITC.
    itc_eligible        BIT              NOT NULL DEFAULT 1,
    -- Reverse charge: the buyer pays the tax. Its ITC is claimed separately
    -- after payment, so it is also excluded from the claimable figure.
    reverse_charge      BIT              NOT NULL DEFAULT 0,

    payment_mode        NVARCHAR(20)     NOT NULL DEFAULT 'cash',
    payment_status      NVARCHAR(20)     NOT NULL DEFAULT 'paid',
    amount_paid         DECIMAL(12,2)    NOT NULL DEFAULT 0,
    notes               NVARCHAR(500)    NULL,

    -- Whether this bill actually moved stock. Inventory can be toggled off
    -- between create and delete; without this flag a delete would reverse a
    -- stock change that was never applied.
    stock_applied       BIT              NOT NULL DEFAULT 0,

    created_by_user_id  UNIQUEIDENTIFIER NOT NULL,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    updated_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_vendor_bills_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    -- NO ACTION: purchase records are financial audit trail (mirrors expenses).
    CONSTRAINT FK_vendor_bills_created_by_user
        FOREIGN KEY (created_by_user_id) REFERENCES users (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT CK_vendor_bills_payment_status
        CHECK (payment_status IN ('paid', 'unpaid', 'partial'))
)
GO

CREATE INDEX IX_vendor_bills_business_date
    ON vendor_bills (business_id, invoice_date DESC)
GO

-- GSTR-2B reconciliation looks bills up by (supplier GSTIN, invoice number).
CREATE INDEX IX_vendor_bills_recon
    ON vendor_bills (business_id, vendor_gstin, invoice_number)
    WHERE vendor_gstin IS NOT NULL
GO

-- A vendor cannot issue two invoices with the same number. Filtered so
-- unregistered vendors (no GSTIN, often no invoice numbering) are exempt.
CREATE UNIQUE INDEX UQ_vendor_bills_invoice
    ON vendor_bills (business_id, vendor_gstin, invoice_number)
    WHERE vendor_gstin IS NOT NULL
GO

CREATE TABLE vendor_bill_items (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    vendor_bill_id   UNIQUEIDENTIFIER NOT NULL,

    -- AT MOST ONE of these three is non-NULL (see CK below). All three NULL is
    -- a service/freight line: it carries tax and ITC but receives no stock.
    item_id          UNIQUEIDENTIFIER NULL,
    variant_id       UNIQUEIDENTIFIER NULL,
    raw_material_id  UNIQUEIDENTIFIER NULL,

    -- Snapshot, so the line still reads correctly after the target is deleted.
    item_name        NVARCHAR(200)    NOT NULL,
    quantity         DECIMAL(10,2)    NOT NULL,
    unit             NVARCHAR(20)     NULL,
    -- 4dp mirrors bill_items.unit_price: a tax-inclusive vendor rate is stored
    -- back-calculated to a net rate, which is rarely exact at 2dp.
    unit_price       DECIMAL(12,4)    NOT NULL,
    tax_rate         DECIMAL(5,2)     NULL,
    hsn_code         NVARCHAR(10)     NULL,
    line_total       DECIMAL(12,2)    NOT NULL,
    sort_order       INT              NOT NULL DEFAULT 0,

    CONSTRAINT FK_vendor_bill_items_bill
        FOREIGN KEY (vendor_bill_id) REFERENCES vendor_bills (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    -- SET NULL: items are soft-deletable; the item_name snapshot survives.
    CONSTRAINT FK_vendor_bill_items_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE NO ACTION ON DELETE SET NULL,

    -- NO ACTION on these two: a cascade here would create multiple cascade
    -- paths (variant -> item -> business) which MSSQL rejects outright.
    CONSTRAINT FK_vendor_bill_items_variant
        FOREIGN KEY (variant_id) REFERENCES item_variants (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT FK_vendor_bill_items_raw_material
        FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    -- At most one stock target per line. `<= 1` rather than `= 1` so a freight
    -- or service line (no stock, but real ITC) can be recorded, which keeps the
    -- entered invoice total equal to the vendor's actual invoice.
    CONSTRAINT CK_vendor_bill_items_single_target CHECK (
        (CASE WHEN item_id         IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN variant_id      IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN raw_material_id IS NOT NULL THEN 1 ELSE 0 END) <= 1
    )
)
GO

CREATE INDEX IX_vendor_bill_items_bill
    ON vendor_bill_items (vendor_bill_id)
GO

CREATE INDEX IX_vendor_bill_items_item
    ON vendor_bill_items (item_id) WHERE item_id IS NOT NULL
GO

CREATE INDEX IX_vendor_bill_items_variant
    ON vendor_bill_items (variant_id) WHERE variant_id IS NOT NULL
GO

CREATE INDEX IX_vendor_bill_items_raw_material
    ON vendor_bill_items (raw_material_id) WHERE raw_material_id IS NOT NULL
GO

-- ---------------------------------------------------------------------------
-- Audit event types
-- ---------------------------------------------------------------------------
-- MSSQL cannot ALTER a CHECK constraint — it must be dropped and recreated with
-- the FULL list. The authoritative previous list is migration 010's (19 values,
-- including the three account_deletion_* events); schema.sql was left stale at
-- 16 and must NOT be used as the source, or those three are silently dropped.
ALTER TABLE audit_logs
    DROP CONSTRAINT CK_audit_logs_event_type
GO

ALTER TABLE audit_logs
    ADD CONSTRAINT CK_audit_logs_event_type CHECK (event_type IN (
        -- Bill lifecycle
        'bill_created',
        'bill_finalized',
        'bill_voided',
        'bill_items_added',
        'bill_items_updated',
        -- Item management
        'item_created',
        'item_price_changed',
        'item_stock_adjusted',
        'item_deleted',
        -- Staff management
        'staff_added',
        'staff_updated',
        'staff_deleted',
        -- Auth events
        'user_login',
        'user_login_failed',
        'user_locked',
        -- Business profile
        'business_profile_updated',
        -- Account deletion lifecycle
        'account_deletion_requested',
        'account_deletion_cancelled',
        'account_deleted',
        -- Vendor bills (new in 034)
        'vendor_bill_created',
        'vendor_bill_updated',
        'vendor_bill_deleted'
    ))
GO
