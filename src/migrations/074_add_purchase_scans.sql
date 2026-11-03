-- =============================================================================
-- Migration 074: add_purchase_scans
-- =============================================================================
-- AI purchase-bill scanning (src/purchaseScan.js, POST /api/vendor-bills/scan).
-- The owner photographs a supplier invoice, Claude reads it into a DRAFT, the
-- owner reviews it in the Vendor Bills form, and the existing save does the
-- rest. Nothing here lets AI save a bill or move stock.
--
--   * purchase_scans       — one row per scan attempt: the usage log behind the
--                            monthly allowance, the token record for costing,
--                            and the pointer to the stored original file.
--   * vendor_item_aliases  — "this vendor's wording means this stock target",
--                            learned from bills the owner actually saved.
--   * vendor_bills.scan_id — the scan a bill was made from (its original file).
--   * vendor_bill_items.free_quantity — scheme goods: received, not charged.
--   * subscriptions.allow_purchase_scan / purchase_scan_limit — the Vittam
--     admin's per-business switch and monthly free-scan allowance.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

CREATE TABLE purchase_scans (
    id              UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    business_id     UNIQUEIDENTIFIER NOT NULL,
    user_id         UNIQUEIDENTIFIER NOT NULL,
    created_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    model           NVARCHAR(100)    NULL,
    input_tokens    INT              NOT NULL DEFAULT 0,
    output_tokens   INT              NOT NULL DEFAULT 0,
    -- pending: quota reserved, extraction running. Only 'ok' counts against
    -- the allowance; a 'pending' row older than 10 minutes is treated as dead.
    status          NVARCHAR(10)     NOT NULL DEFAULT 'pending',
    -- Relative to backend/private_uploads/purchase-bills. NULL once the file is
    -- gone (failed scan, abandoned scan cleaned up, bill deleted).
    file_path       NVARCHAR(500)    NULL,
    media_type      NVARCHAR(50)     NOT NULL,
    failure_reason  NVARCHAR(500)    NULL,
    page_count      INT              NULL,

    CONSTRAINT FK_purchase_scans_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    -- NO ACTION, mirroring vendor_bills.created_by_user_id.
    CONSTRAINT FK_purchase_scans_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT CK_purchase_scans_status
        CHECK (status IN ('pending', 'ok', 'failed'))
)
GO

-- The monthly allowance counts a business's scans since the 1st.
CREATE INDEX IX_purchase_scans_business_created
    ON purchase_scans (business_id, created_at)
GO

CREATE TABLE vendor_item_aliases (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id      UNIQUEIDENTIFIER NOT NULL,
    -- The vendor's GSTIN, else their lower-cased name (purchaseScan.vendorKey).
    vendor_key       NVARCHAR(200)    NOT NULL,
    -- The vendor's line wording, lower-cased with spacing collapsed.
    vendor_text      NVARCHAR(200)    NOT NULL,

    -- Exactly one target. Deliberately NO foreign keys: an alias is only a hint
    -- the app resolves against the live item list (an id it cannot find is
    -- ignored), and an FK here would block hard-deleting a variant or raw
    -- material, or add a second cascade path MSSQL rejects. Ids are only ever
    -- written from saved bill lines, which resolveTargets has business-scoped.
    item_id          UNIQUEIDENTIFIER NULL,
    variant_id       UNIQUEIDENTIFIER NULL,
    raw_material_id  UNIQUEIDENTIFIER NULL,
    -- The owner received this line in the target's packs (boxes), not units.
    in_packs         BIT              NOT NULL DEFAULT 0,
    updated_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_vendor_item_aliases_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    CONSTRAINT CK_vendor_item_aliases_single_target CHECK (
        (CASE WHEN item_id         IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN variant_id      IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN raw_material_id IS NOT NULL THEN 1 ELSE 0 END) = 1
    )
)
GO

CREATE UNIQUE INDEX UQ_vendor_item_aliases_key
    ON vendor_item_aliases (business_id, vendor_key, vendor_text)
GO

-- No FK: both vendor_bills and purchase_scans cascade from businesses, and a
-- third path between them is a multiple-cascade-path error in MSSQL. Every
-- lookup joins on business_id as well.
ALTER TABLE vendor_bills ADD scan_id UNIQUEIDENTIFIER NULL
GO

-- Existing lines read as 0 free, so old bills keep their exact stock math.
ALTER TABLE vendor_bill_items ADD free_quantity DECIMAL(10,2) NOT NULL
    CONSTRAINT DF_vendor_bill_items_free_quantity DEFAULT 0
GO

ALTER TABLE vendor_bill_items ADD CONSTRAINT CK_vendor_bill_items_free_quantity
    CHECK (free_quantity >= 0)
GO

-- NULL = blocked. Unlike allow_customers (default allowed), every scan costs
-- money, so a business only gets it when the Vittam admin switches it on.
ALTER TABLE subscriptions ADD allow_purchase_scan BIT NULL
GO

-- Free scans per month. NULL = PURCHASE_SCAN_MONTHLY_LIMIT from .env.
ALTER TABLE subscriptions ADD purchase_scan_limit INT NULL
    CONSTRAINT CK_subscriptions_purchase_scan_limit CHECK (purchase_scan_limit >= 0)
GO
