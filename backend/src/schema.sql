-- Billing App Database Schema
-- Run this against the billing_db database (DB is selected via connection config)
-- For existing databases use migrations/001_add_foreign_keys.sql instead.

CREATE TABLE businesses (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    name             NVARCHAR(200)    NOT NULL,
    business_type    NVARCHAR(50)     NOT NULL, -- 'retail', 'restaurant_with_tables', 'restaurant_no_tables'
    address          NVARCHAR(500)    NULL,
    phone            NVARCHAR(20)     NOT NULL,
    inventory_enabled    BIT          NOT NULL DEFAULT 0,
    has_barcode_scanner  BIT          NOT NULL DEFAULT 0,
    is_verified          BIT          NOT NULL DEFAULT 0,
    -- GST (added via migration 025) — optional, OFF by default.
    gst_enabled      BIT              NOT NULL DEFAULT 0,   -- master toggle for all GST UI/receipt
    default_sac_code NVARCHAR(10)     NULL,   -- bill-level fallback HSN/SAC (e.g. restaurant 9963)
    -- Extended profile fields (added via migration 005)
    gst_number       NVARCHAR(15)     NULL,   -- 15-char GSTIN
    pan_number       NVARCHAR(10)     NULL,   -- 10-char PAN
    email            NVARCHAR(200)    NULL,
    website          NVARCHAR(500)    NULL,
    city             NVARCHAR(100)    NULL,
    state            NVARCHAR(100)    NULL,
    pincode          NVARCHAR(10)     NULL,
    logo_url         NVARCHAR(1000)   NULL,
    bill_prefix      NVARCHAR(10)     NULL DEFAULT 'INV',
    bill_footer_note NVARCHAR(500)    NULL,
    created_at       DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);

-- Partial unique index: GSTIN must be unique across businesses if provided.
CREATE UNIQUE INDEX UQ_businesses_gst_number
    ON businesses (gst_number)
    WHERE gst_number IS NOT NULL;

CREATE TABLE users (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id      UNIQUEIDENTIFIER NOT NULL,
    name             NVARCHAR(200)    NOT NULL,
    phone            NVARCHAR(20)     NOT NULL,
    pin_hash         NVARCHAR(255)    NOT NULL,
    role             NVARCHAR(20)     NOT NULL, -- 'owner' or 'cashier'
    failed_attempts  INT              NOT NULL DEFAULT 0,
    locked_until     DATETIME2        NULL,     -- NULL = not locked
    created_at       DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_users_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT UQ_users_business_phone
        UNIQUE (business_id, phone)
);

CREATE INDEX IX_users_business_id ON users (business_id);

CREATE TABLE items (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id     UNIQUEIDENTIFIER NOT NULL,
    name            NVARCHAR(200)    NOT NULL,
    barcode         NVARCHAR(100)    NULL,
    category        NVARCHAR(100)    NULL,
    price           DECIMAL(10,2)    NOT NULL,
    tax_rate        DECIMAL(5,2)     NULL,
    hsn_code        NVARCHAR(10)     NULL,   -- optional per-item HSN/SAC (GST)
    stock_quantity  DECIMAL(10,2)    NULL,
    unit            NVARCHAR(20)     NOT NULL DEFAULT 'piece',
    is_active       BIT              NOT NULL DEFAULT 1,
    created_at      DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_items_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IX_items_business_id ON items (business_id);

-- Partial unique index: one barcode per business, NULLs excluded.
CREATE UNIQUE INDEX UQ_items_business_barcode
    ON items (business_id, barcode)
    WHERE barcode IS NOT NULL;

-- Product variants (e.g. sizes S/M/L/XL) with independent stock.
CREATE TABLE item_variants (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    item_id             UNIQUEIDENTIFIER NOT NULL,
    label               NVARCHAR(50)     NOT NULL,
    price               DECIMAL(10,2)    NULL,
    barcode             NVARCHAR(100)    NULL,
    stock_quantity      DECIMAL(10,2)    NULL,
    low_stock_threshold DECIMAL(10,2)    NULL,
    sort_order          INT              NOT NULL DEFAULT 0,
    is_active           BIT              NOT NULL DEFAULT 1,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_item_variants_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE INDEX IX_item_variants_item_id ON item_variants (item_id);

CREATE UNIQUE INDEX UQ_item_variants_item_barcode
    ON item_variants (item_id, barcode)
    WHERE barcode IS NOT NULL;

CREATE TABLE tables (
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id   UNIQUEIDENTIFIER NOT NULL,
    table_number  NVARCHAR(20)     NOT NULL,
    floor_x       DECIMAL(10,2)    NOT NULL DEFAULT 0,
    floor_y       DECIMAL(10,2)    NOT NULL DEFAULT 0,
    status        NVARCHAR(20)     NOT NULL DEFAULT 'empty', -- 'empty', 'occupied', 'billed'
    created_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_tables_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT UQ_tables_business_table_number
        UNIQUE (business_id, table_number)
);

CREATE INDEX IX_tables_business_id ON tables (business_id);

CREATE TABLE bills (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id         UNIQUEIDENTIFIER NOT NULL,
    bill_number         NVARCHAR(50)     NOT NULL,
    table_id            UNIQUEIDENTIFIER NULL,
    customer_name       NVARCHAR(200)    NULL,
    customer_phone      NVARCHAR(20)     NULL,
    subtotal            DECIMAL(10,2)    NOT NULL,
    tax_amount          DECIMAL(10,2)    NOT NULL DEFAULT 0,
    total               DECIMAL(10,2)    NOT NULL,
    payment_mode        NVARCHAR(20)     NOT NULL, -- 'cash', 'upi', 'card', 'credit', 'other'
    status              NVARCHAR(20)     NOT NULL DEFAULT 'finalized', -- 'draft', 'finalized', 'voided'
    created_by_user_id  UNIQUEIDENTIFIER NOT NULL,
    client_bill_id      NVARCHAR(36)     NULL,     -- idempotency key from Flutter offline queue (UUID v4)
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_bills_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    -- SET NULL: preserves bill record when a table is hard-deleted.
    -- The app guards against deleting tables with active bills first.
    CONSTRAINT FK_bills_table
        FOREIGN KEY (table_id) REFERENCES tables (id)
        ON UPDATE NO ACTION ON DELETE SET NULL,

    -- NO ACTION: bills are financial records and must survive staff deletion.
    CONSTRAINT FK_bills_created_by_user
        FOREIGN KEY (created_by_user_id) REFERENCES users (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT UQ_bills_business_bill_number
        UNIQUE (business_id, bill_number)
);

CREATE INDEX IX_bills_business_id        ON bills (business_id);
CREATE INDEX IX_bills_table_id           ON bills (table_id)          WHERE table_id IS NOT NULL;
CREATE INDEX IX_bills_created_by_user_id ON bills (created_by_user_id);

CREATE TABLE bill_items (
    id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    bill_id     UNIQUEIDENTIFIER NOT NULL,
    item_id     UNIQUEIDENTIFIER NULL,
    variant_id  UNIQUEIDENTIFIER NULL,
    item_name   NVARCHAR(200)    NOT NULL,
    quantity    DECIMAL(10,2)    NOT NULL,
    unit_price  DECIMAL(10,2)    NOT NULL,
    tax_rate    DECIMAL(5,2)     NULL,
    hsn_code    NVARCHAR(10)     NULL,   -- snapshot of the item's HSN/SAC at sale time
    line_total  DECIMAL(10,2)    NOT NULL,

    -- CASCADE: line items are owned by the bill.
    CONSTRAINT FK_bill_items_bill
        FOREIGN KEY (bill_id) REFERENCES bills (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    -- SET NULL: items are soft-deleted (is_active=0); item_name snapshot is preserved.
    CONSTRAINT FK_bill_items_item
        FOREIGN KEY (item_id) REFERENCES items (id)
        ON UPDATE NO ACTION ON DELETE SET NULL,

    -- NO ACTION: variant stock target; item_name snapshot preserved on delete.
    CONSTRAINT FK_bill_items_variant
        FOREIGN KEY (variant_id) REFERENCES item_variants (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IX_bill_items_bill_id ON bill_items (bill_id);
CREATE INDEX IX_bill_items_item_id ON bill_items (item_id) WHERE item_id IS NOT NULL;
CREATE INDEX IX_bill_items_variant_id ON bill_items (variant_id) WHERE variant_id IS NOT NULL;

CREATE TABLE recurring_expenses (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id  UNIQUEIDENTIFIER NOT NULL,
    category     NVARCHAR(100)    NOT NULL,
    description  NVARCHAR(500)    NULL,
    amount       DECIMAL(10,2)    NOT NULL,
    payment_mode NVARCHAR(20)     NOT NULL DEFAULT 'cash',
    created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_recurring_expenses_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IX_recurring_expenses_biz_id ON recurring_expenses (business_id);

CREATE TABLE refresh_tokens (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    user_id      UNIQUEIDENTIFIER NOT NULL,
    business_id  UNIQUEIDENTIFIER NOT NULL,
    token_hash   NVARCHAR(64)     NOT NULL,  -- SHA-256 hex of the raw refresh token
    family_id    UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(), -- groups all rotated tokens from one login
    expires_at   DATETIME2        NOT NULL,
    revoked      BIT              NOT NULL DEFAULT 0,
    created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    -- CASCADE: tokens are owned by the user; hard-deleting a user cleans up tokens.
    CONSTRAINT FK_refresh_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON UPDATE NO ACTION ON DELETE CASCADE,

    CONSTRAINT FK_refresh_tokens_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IX_refresh_tokens_hash      ON refresh_tokens (token_hash);
CREATE INDEX IX_refresh_tokens_user_id   ON refresh_tokens (user_id);
CREATE INDEX IX_refresh_tokens_family_id ON refresh_tokens (family_id);

CREATE TABLE expenses (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id         UNIQUEIDENTIFIER NOT NULL,
    category            NVARCHAR(100)    NOT NULL, -- e.g. 'Rent', 'Salary', 'Utilities', 'Stock Purchase', 'Other'
    description         NVARCHAR(500)    NULL,
    amount              DECIMAL(10,2)    NOT NULL,
    payment_mode        NVARCHAR(20)     NOT NULL DEFAULT 'cash', -- 'cash', 'upi', 'card', 'other'
    expense_date        DATE             NOT NULL DEFAULT CAST(GETUTCDATE() AS DATE),
    created_by_user_id  UNIQUEIDENTIFIER NOT NULL,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_expenses_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    -- NO ACTION: expense records are financial audit trail.
    CONSTRAINT FK_expenses_created_by_user
        FOREIGN KEY (created_by_user_id) REFERENCES users (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IX_expenses_business_id        ON expenses (business_id);
CREATE INDEX IX_expenses_created_by_user_id ON expenses (created_by_user_id);

-- =============================================================================
-- audit_logs: immutable append-only trail of every significant action.
-- Rows are never updated or deleted.
-- =============================================================================
CREATE TABLE audit_logs (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id     UNIQUEIDENTIFIER NOT NULL,
    user_id         UNIQUEIDENTIFIER NULL,      -- NULL for system events
    user_name       NVARCHAR(200)    NULL,      -- snapshot; survives user deletion
    event_type      NVARCHAR(50)     NOT NULL,
    entity_id       UNIQUEIDENTIFIER NULL,
    entity_label    NVARCHAR(200)    NULL,
    old_value       NVARCHAR(MAX)    NULL,      -- JSON
    new_value       NVARCHAR(MAX)    NULL,      -- JSON
    description     NVARCHAR(1000)   NULL,
    created_at      DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT CK_audit_logs_event_type CHECK (event_type IN (
        'bill_created', 'bill_finalized', 'bill_voided',
        'bill_items_added', 'bill_items_updated',
        'item_created', 'item_price_changed', 'item_stock_adjusted', 'item_deleted',
        'staff_added', 'staff_updated', 'staff_deleted',
        'user_login', 'user_login_failed', 'user_locked',
        'business_profile_updated'
    ))
);

CREATE INDEX IX_audit_logs_business_created
    ON audit_logs (business_id, created_at DESC);

CREATE INDEX IX_audit_logs_entity
    ON audit_logs (entity_id, created_at DESC)
    WHERE entity_id IS NOT NULL;

CREATE INDEX IX_audit_logs_user
    ON audit_logs (user_id, created_at DESC)
    WHERE user_id IS NOT NULL;

CREATE INDEX IX_audit_logs_event_type
    ON audit_logs (business_id, event_type, created_at DESC);

-- =============================================================================
-- whatsapp_otp_log: stores hashed OTPs for phone verification flows.
-- Rows are never hard-deleted — used=1 means consumed or superseded.
-- =============================================================================
CREATE TABLE whatsapp_otp_log (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    phone        NVARCHAR(20)     NOT NULL,  -- normalised: "91XXXXXXXXXX"
    purpose      NVARCHAR(20)     NOT NULL,  -- 'register' | 'forgot_pin'
    otp_hash     NVARCHAR(64)     NOT NULL,  -- SHA-256 hex of the 6-digit OTP
    used         BIT              NOT NULL DEFAULT 0,
    expires_at   DATETIME2        NOT NULL,
    status       NVARCHAR(20)     NULL,      -- 'sent' | 'failed' | 'skipped'
    campaign_id  NVARCHAR(100)    NULL,      -- SMSala ReturnData
    error_detail NVARCHAR(500)    NULL,
    created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT CK_whatsapp_otp_log_purpose CHECK (purpose IN ('register', 'forgot_pin'))
);

CREATE INDEX IX_whatsapp_otp_log_phone_purpose
    ON whatsapp_otp_log (phone, purpose, used, expires_at);
