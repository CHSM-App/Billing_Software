-- =============================================================================
-- Migration 037: add_online_store
-- =============================================================================
-- Adds the ONLINE STORE: a public, shop-level ordering link (no app, no table).
--
-- Flow: the owner turns the store on and shares one link. A customer opens it,
-- browses the same catalog the QR menu serves, verifies their phone once by
-- WhatsApp OTP, picks pickup or delivery, optionally pays an advance into the
-- shop's own UPI QR and types the transaction id, and submits. The order lands
-- in a PENDING queue in the app — it does NOT become a bill yet. The owner
-- accepts it (which creates the draft bill and fires it at the kitchen) or
-- rejects it with a reason.
--
-- Why a queue instead of a draft bill straight away (as table self-ordering
-- does): a table diner is physically in the shop and already trusted by the
-- staff standing next to them. A stranger on the internet is not, and an
-- unattended stranger must not be able to write rows into a shop's books.
--
-- Columns added to businesses (all store_*):
--   store_enabled           - master on/off switch
--   store_token             - unguessable token in the public link
--   store_delivery_enabled  - offer delivery too (address becomes required).
--                             Pickup needs no column: it is always available.
--   store_delivery_charge   - flat delivery fee, folded into the accepted bill
--                             as an `additional_charges` entry (migration 035)
--   store_payment_qr_url    - the shop's own uploaded UPI QR image
--   store_advance_percent   - 0 = ask for nothing, 100 = full prepayment
--   store_payment_required  - refuse an order that carries no transaction id
--
-- Tables added: online_orders, online_order_items.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

-- --- businesses: store settings ----------------------------------------------
IF COL_LENGTH('businesses', 'store_enabled') IS NULL
    ALTER TABLE businesses ADD store_enabled BIT NOT NULL DEFAULT 0
GO

IF COL_LENGTH('businesses', 'store_token') IS NULL
    ALTER TABLE businesses ADD store_token NVARCHAR(32) NULL
GO

-- Backfill unguessable tokens for existing businesses (32 hex chars from NEWID).
-- Every business gets one even while the store is off, so turning the feature on
-- is a single flag flip and the link is stable from day one.
UPDATE businesses
SET store_token = REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', '')
WHERE store_token IS NULL
GO

-- Filtered so a future insert that has not been backfilled yet is not blocked.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_businesses_store_token')
    CREATE UNIQUE INDEX UQ_businesses_store_token
        ON businesses (store_token) WHERE store_token IS NOT NULL
GO

-- There is deliberately no store_pickup_enabled: a customer can always walk in
-- and collect, so a switch for it could only ever be set wrong. Pickup is the
-- baseline every store offers; delivery is the thing a shop opts into.
IF COL_LENGTH('businesses', 'store_delivery_enabled') IS NULL
    ALTER TABLE businesses ADD store_delivery_enabled BIT NOT NULL DEFAULT 0
GO

IF COL_LENGTH('businesses', 'store_delivery_charge') IS NULL
    ALTER TABLE businesses ADD store_delivery_charge DECIMAL(10,2) NOT NULL DEFAULT 0
GO

IF COL_LENGTH('businesses', 'store_payment_qr_url') IS NULL
    ALTER TABLE businesses ADD store_payment_qr_url NVARCHAR(500) NULL
GO

IF COL_LENGTH('businesses', 'store_advance_percent') IS NULL
    ALTER TABLE businesses ADD store_advance_percent DECIMAL(5,2) NOT NULL DEFAULT 0
GO

IF COL_LENGTH('businesses', 'store_payment_required') IS NULL
    ALTER TABLE businesses ADD store_payment_required BIT NOT NULL DEFAULT 0
GO

-- --- online_orders ------------------------------------------------------------
CREATE TABLE online_orders (
    id                 UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id        UNIQUEIDENTIFIER NOT NULL,
    -- 'ORD-0001', numbered per business. Deliberately its OWN series, not the
    -- bill series: a rejected order must not burn a bill number.
    order_number       NVARCHAR(50)     NOT NULL,

    customer_name      NVARCHAR(200)    NULL,
    customer_phone     NVARCHAR(20)     NOT NULL,   -- OTP-verified

    fulfilment         NVARCHAR(20)     NOT NULL,   -- 'pickup' | 'delivery'
    address            NVARCHAR(500)    NULL,       -- required when 'delivery'
    note               NVARCHAR(500)    NULL,

    -- Money. subtotal is the sum of the lines (net rates, like bill_items);
    -- total = subtotal + delivery_charge. No GST is computed here — tax is
    -- applied by the normal billing path once the order is accepted.
    subtotal           DECIMAL(10,2)    NOT NULL DEFAULT 0,
    delivery_charge    DECIMAL(10,2)    NOT NULL DEFAULT 0,
    total              DECIMAL(10,2)    NOT NULL DEFAULT 0,

    -- Payment. amount_due is what the store ASKED for up front (advance % of
    -- total, or the whole total at 100). paid_amount + payment_txn_id are what
    -- the customer CLAIMS — a typed UPI reference cannot be verified from here,
    -- which is exactly why 'claimed' is a distinct state from 'verified'. The
    -- owner cross-checks the reference in their own UPI app when accepting.
    amount_due         DECIMAL(10,2)    NOT NULL DEFAULT 0,
    paid_amount        DECIMAL(10,2)    NOT NULL DEFAULT 0,
    payment_txn_id     NVARCHAR(64)     NULL,
    payment_status     NVARCHAR(20)     NOT NULL DEFAULT 'unpaid',

    status             NVARCHAR(20)     NOT NULL DEFAULT 'pending',
    reject_reason      NVARCHAR(200)    NULL,
    -- Set when accepted: the draft bill this order became.
    bill_id            UNIQUEIDENTIFIER NULL,
    decided_by_user_id UNIQUEIDENTIFIER NULL,
    decided_at         DATETIME2        NULL,
    created_at         DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    -- NO ACTION, matching bills: an order is part of the money trail.
    CONSTRAINT FK_online_orders_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    -- SET NULL: voiding/deleting the bill must not erase the order history.
    CONSTRAINT FK_online_orders_bill
        FOREIGN KEY (bill_id) REFERENCES bills (id)
        ON UPDATE NO ACTION ON DELETE SET NULL,

    CONSTRAINT FK_online_orders_decided_by_user
        FOREIGN KEY (decided_by_user_id) REFERENCES users (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT UQ_online_orders_business_order_number
        UNIQUE (business_id, order_number),

    CONSTRAINT CK_online_orders_fulfilment
        CHECK (fulfilment IN ('pickup', 'delivery')),

    CONSTRAINT CK_online_orders_payment_status
        CHECK (payment_status IN ('unpaid', 'claimed', 'verified')),

    CONSTRAINT CK_online_orders_status
        CHECK (status IN ('pending', 'accepted', 'rejected'))
)
GO

-- The queue screen reads pending-first, newest-first, for one business.
CREATE INDEX IX_online_orders_business_status
    ON online_orders (business_id, status, created_at DESC)
GO

-- The customer's own status poll looks orders up by their verified phone.
CREATE INDEX IX_online_orders_business_phone
    ON online_orders (business_id, customer_phone, created_at DESC)
GO

-- --- online_order_items -------------------------------------------------------
-- Deliberately the same column shape as bill_items, so accepting an order is a
-- straight copy with no re-derivation: unit_price is already the NET rate at
-- 4dp (an MRP/tax-inclusive item was back-calculated when the order was placed).
CREATE TABLE online_order_items (
    id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    order_id    UNIQUEIDENTIFIER NOT NULL,
    item_id     UNIQUEIDENTIFIER NULL,
    variant_id  UNIQUEIDENTIFIER NULL,
    item_name   NVARCHAR(200)    NOT NULL,   -- snapshot; survives item deletion
    quantity    DECIMAL(10,2)    NOT NULL,
    unit_price  DECIMAL(12,4)    NOT NULL,
    tax_rate    DECIMAL(5,2)     NULL,
    line_total  DECIMAL(10,2)    NOT NULL,

    CONSTRAINT FK_online_order_items_order
        FOREIGN KEY (order_id) REFERENCES online_orders (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    -- SET NULL: items are soft-deleted; the item_name snapshot carries the line.
    CONSTRAINT FK_online_order_items_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE NO ACTION ON DELETE SET NULL,

    -- NO ACTION: a cascade here would add a second path (variant -> item).
    CONSTRAINT FK_online_order_items_variant
        FOREIGN KEY (variant_id) REFERENCES item_variants (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
)
GO

CREATE INDEX IX_online_order_items_order
    ON online_order_items (order_id)
GO

-- --- audit event types --------------------------------------------------------
-- MSSQL cannot ALTER a CHECK constraint — it must be dropped and recreated with
-- the FULL list. Source of truth is migration 034's list (23 values); this adds
-- the two online-store decisions.
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
        -- Vendor bills (034)
        'vendor_bill_created',
        'vendor_bill_updated',
        'vendor_bill_deleted',
        -- Online store (new in 037)
        'online_order_accepted',
        'online_order_rejected'
    ))
GO
