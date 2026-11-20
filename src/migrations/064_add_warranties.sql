-- =============================================================================
-- Migration 064: add_warranties
--
-- "Retail & Warranty" shops (tyre/battery/electronics retailers) need to
-- answer "is this still under warranty?" months after the sale, by phone
-- number or serial number. This is the record of that: one row per
-- warranted item sold (or registered) to a customer.
--
-- customer_name/customer_phone are stored directly (same reasoning as
-- bills.customer_name/customer_phone): the `customers` table (migration 046)
-- is a derived, phone-keyed cache backfilled from bills, not an
-- authoritative identity store, so a warranty record must stand on its own
-- even when no matching `customers` row exists. customer_id is kept as a
-- best-effort link when one does exist.
--
-- item_id/bill_id/bill_item_id are nullable because a warranty can be
-- registered manually, off any sale (e.g. a fitting-only job, or a product
-- bought before this feature existed).
--
-- extra_data holds both the category template's filled values AND any
-- ad-hoc label/value pairs staff typed on the spot — one flat JSON array
-- of {label, value}; the backend never needs to tell the two apart.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('warranties', 'U') IS NULL
CREATE TABLE warranties (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id         UNIQUEIDENTIFIER NOT NULL,
    customer_id         UNIQUEIDENTIFIER NULL,
    customer_name       NVARCHAR(200)    NULL,
    customer_phone      NVARCHAR(20)     NOT NULL,
    item_id             UNIQUEIDENTIFIER NULL,
    item_name           NVARCHAR(200)    NOT NULL,
    category            NVARCHAR(100)    NULL,
    bill_id             UNIQUEIDENTIFIER NULL,
    bill_item_id        UNIQUEIDENTIFIER NULL,
    serial_number       NVARCHAR(100)    NULL,
    purchase_date       DATE             NOT NULL,
    warranty_months     INT              NOT NULL,
    expiry_date         DATE             NOT NULL,
    extra_data          NVARCHAR(MAX)    NULL,
    notes               NVARCHAR(500)    NULL,
    created_by_user_id  UNIQUEIDENTIFIER NOT NULL,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_warranties_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    -- SET NULL: a warranty record must survive a customer row being
    -- removed; the denormalized customer_name/customer_phone remain.
    CONSTRAINT FK_warranties_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id)
        ON UPDATE NO ACTION ON DELETE SET NULL,

    -- NO ACTION on item/bill/bill_item: these are sale-adjacent records that
    -- must not be deletable out from under a warranty; the app does not
    -- hard-delete items or bills today.
    CONSTRAINT FK_warranties_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT FK_warranties_bill
        FOREIGN KEY (bill_id) REFERENCES bills (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT FK_warranties_bill_item
        FOREIGN KEY (bill_item_id) REFERENCES bill_items (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT FK_warranties_created_by_user
        FOREIGN KEY (created_by_user_id) REFERENCES users (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_warranties_business_phone')
CREATE INDEX IX_warranties_business_phone ON warranties (business_id, customer_phone)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_warranties_business_serial')
CREATE INDEX IX_warranties_business_serial ON warranties (business_id, serial_number) WHERE serial_number IS NOT NULL
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_warranties_business_expiry')
CREATE INDEX IX_warranties_business_expiry ON warranties (business_id, expiry_date)
GO
