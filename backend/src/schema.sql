-- Billing App Database Schema
-- Run this against the billing_db database (DB is selected via connection config)

CREATE TABLE businesses (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    name             NVARCHAR(200)    NOT NULL,
    business_type    NVARCHAR(50)     NOT NULL, -- 'retail', 'restaurant_with_tables', 'restaurant_no_tables'
    address          NVARCHAR(500)    NULL,
    phone            NVARCHAR(20)     NOT NULL,
    inventory_enabled    BIT          NOT NULL DEFAULT 0,
    has_barcode_scanner  BIT          NOT NULL DEFAULT 0,
    is_verified          BIT          NOT NULL DEFAULT 0,
    created_at       DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE users (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id  UNIQUEIDENTIFIER NOT NULL,
    name         NVARCHAR(200)    NOT NULL,
    phone        NVARCHAR(20)     NOT NULL,
    pin_hash     NVARCHAR(255)    NOT NULL,
    role         NVARCHAR(20)     NOT NULL, -- 'owner' or 'cashier'
    created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE items (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id     UNIQUEIDENTIFIER NOT NULL,
    name            NVARCHAR(200)    NOT NULL,
    barcode         NVARCHAR(100)    NULL,
    category        NVARCHAR(100)    NULL,
    price           DECIMAL(10,2)    NOT NULL,
    tax_rate        DECIMAL(5,2)     NULL,
    stock_quantity  DECIMAL(10,2)    NULL,
    is_active       BIT              NOT NULL DEFAULT 1,
    created_at      DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE tables (
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id   UNIQUEIDENTIFIER NOT NULL,
    table_number  NVARCHAR(20)     NOT NULL,
    floor_x       DECIMAL(10,2)    NOT NULL DEFAULT 0,
    floor_y       DECIMAL(10,2)    NOT NULL DEFAULT 0,
    status        NVARCHAR(20)     NOT NULL DEFAULT 'empty', -- 'empty', 'occupied', 'billed'
    created_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);

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
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE bill_items (
    id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    bill_id     UNIQUEIDENTIFIER NOT NULL,
    item_id     UNIQUEIDENTIFIER NULL,
    item_name   NVARCHAR(200)    NOT NULL,
    quantity    DECIMAL(10,2)    NOT NULL,
    unit_price  DECIMAL(10,2)    NOT NULL,
    tax_rate    DECIMAL(5,2)     NULL,
    line_total  DECIMAL(10,2)    NOT NULL
);
