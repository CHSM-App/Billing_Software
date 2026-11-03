-- =============================================================================
-- Migration 000: initial schema
-- Creates all base tables on a blank database.
-- Uses IF NOT EXISTS guards so it is safe to run against an existing database.
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'businesses')
CREATE TABLE businesses (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    name             NVARCHAR(200)    NOT NULL,
    business_type    NVARCHAR(50)     NOT NULL,
    address          NVARCHAR(500)    NULL,
    phone            NVARCHAR(20)     NOT NULL,
    inventory_enabled    BIT          NOT NULL DEFAULT 0,
    has_barcode_scanner  BIT          NOT NULL DEFAULT 0,
    is_verified          BIT          NOT NULL DEFAULT 0,
    created_at       DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users')
CREATE TABLE users (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id      UNIQUEIDENTIFIER NOT NULL,
    name             NVARCHAR(200)    NOT NULL,
    phone            NVARCHAR(20)     NOT NULL,
    pin_hash         NVARCHAR(255)    NOT NULL,
    role             NVARCHAR(20)     NOT NULL,
    failed_attempts  INT              NOT NULL DEFAULT 0,
    locked_until     DATETIME2        NULL,
    created_at       DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'items')
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
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'tables')
CREATE TABLE tables (
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id   UNIQUEIDENTIFIER NOT NULL,
    table_number  NVARCHAR(20)     NOT NULL,
    floor_x       DECIMAL(10,2)    NOT NULL DEFAULT 0,
    floor_y       DECIMAL(10,2)    NOT NULL DEFAULT 0,
    status        NVARCHAR(20)     NOT NULL DEFAULT 'empty',
    created_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'bills')
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
    payment_mode        NVARCHAR(20)     NOT NULL,
    status              NVARCHAR(20)     NOT NULL DEFAULT 'finalized',
    created_by_user_id  UNIQUEIDENTIFIER NOT NULL,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'bill_items')
CREATE TABLE bill_items (
    id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    bill_id     UNIQUEIDENTIFIER NOT NULL,
    item_id     UNIQUEIDENTIFIER NULL,
    item_name   NVARCHAR(200)    NOT NULL,
    quantity    DECIMAL(10,2)    NOT NULL,
    unit_price  DECIMAL(10,2)    NOT NULL,
    tax_rate    DECIMAL(5,2)     NULL,
    line_total  DECIMAL(10,2)    NOT NULL
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'recurring_expenses')
CREATE TABLE recurring_expenses (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id  UNIQUEIDENTIFIER NOT NULL,
    category     NVARCHAR(100)    NOT NULL,
    description  NVARCHAR(500)    NULL,
    amount       DECIMAL(10,2)    NOT NULL,
    payment_mode NVARCHAR(20)     NOT NULL DEFAULT 'cash',
    created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'refresh_tokens')
CREATE TABLE refresh_tokens (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    user_id      UNIQUEIDENTIFIER NOT NULL,
    business_id  UNIQUEIDENTIFIER NOT NULL,
    token_hash   NVARCHAR(64)     NOT NULL,
    expires_at   DATETIME2        NOT NULL,
    revoked      BIT              NOT NULL DEFAULT 0,
    created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'expenses')
CREATE TABLE expenses (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id         UNIQUEIDENTIFIER NOT NULL,
    category            NVARCHAR(100)    NOT NULL,
    description         NVARCHAR(500)    NULL,
    amount              DECIMAL(10,2)    NOT NULL,
    payment_mode        NVARCHAR(20)     NOT NULL DEFAULT 'cash',
    expense_date        DATE             NOT NULL DEFAULT CAST(GETUTCDATE() AS DATE),
    created_by_user_id  UNIQUEIDENTIFIER NOT NULL,
    created_at          DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO
