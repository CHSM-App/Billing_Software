-- =============================================================================
-- Migration 046: customers + campaign_messages
--
-- Until now a customer existed only as the name/phone typed onto a bill. The
-- Customers screen needs somewhere to keep things a bill cannot hold — above
-- all the opt-out ("stop sending me offers"), which WhatsApp's rules require
-- us to honour and which protects the one shared sending number every shop
-- uses.
--
-- bills is NOT touched: bills.customer_name / customer_phone stay exactly as
-- issued (an invoice must not change afterwards), and every existing route and
-- installed app keeps reading them. This table is filled FROM bills, one way:
--   * once here, by the backfill below;
--   * then by routes/bills.js etc. after each bill commits (never inside the
--     bill's transaction, so a sale can never fail because of it);
--   * and by a throttled catch-up sync (src/customers.js) for anything missed.
--
-- Visit count / spend / last visit are NOT stored — they are always computed
-- from bills, so they cannot drift.
--
-- phone is stored trimmed, exactly as on bills, so it joins back to
-- bills.customer_phone (indexed by IX from migration 022).
-- =============================================================================

IF OBJECT_ID('customers', 'U') IS NULL
CREATE TABLE customers (
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id   UNIQUEIDENTIFIER NOT NULL,
    phone         NVARCHAR(20)     NOT NULL,
    name          NVARCHAR(200)    NULL,
    opted_out     BIT              NOT NULL DEFAULT 0,
    opted_out_at  DATETIME2        NULL,
    created_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    updated_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_customers_business_phone UNIQUE (business_id, phone)
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customers_business_name')
CREATE INDEX IX_customers_business_name ON customers (business_id, name)
GO

-- Backfill: one row per (business, trimmed phone) from every bill that has a
-- phone — drafts too, they are real customers for name suggestions. The name is
-- the latest non-blank one; created_at is that phone's first bill. Read-only on
-- bills.
INSERT INTO customers (business_id, phone, name, created_at, updated_at)
SELECT p.business_id, p.phone, n.name, p.first_at, GETUTCDATE()
FROM (
    SELECT business_id, LTRIM(RTRIM(customer_phone)) AS phone, MIN(created_at) AS first_at
    FROM bills
    WHERE customer_phone IS NOT NULL AND LTRIM(RTRIM(customer_phone)) <> ''
    GROUP BY business_id, LTRIM(RTRIM(customer_phone))
) p
OUTER APPLY (
    SELECT TOP 1 LTRIM(RTRIM(b.customer_name)) AS name
    FROM bills b
    WHERE b.business_id = p.business_id
      AND LTRIM(RTRIM(b.customer_phone)) = p.phone
      AND b.customer_name IS NOT NULL AND LTRIM(RTRIM(b.customer_name)) <> ''
    ORDER BY b.created_at DESC
) n
WHERE NOT EXISTS (
    SELECT 1 FROM customers c WHERE c.business_id = p.business_id AND c.phone = p.phone
)
GO

-- One row per campaign message: the send log, and what the per-business daily
-- cap counts.
IF OBJECT_ID('campaign_messages', 'U') IS NULL
CREATE TABLE campaign_messages (
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id   UNIQUEIDENTIFIER NOT NULL,
    customer_id   UNIQUEIDENTIFIER NULL,
    phone         NVARCHAR(20)     NOT NULL,
    status        NVARCHAR(20)     NOT NULL,   -- 'sent' | 'failed' | 'skipped'
    error_detail  NVARCHAR(500)    NULL,
    provider_ref  NVARCHAR(100)    NULL,
    created_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_campaign_messages_business_created')
CREATE INDEX IX_campaign_messages_business_created ON campaign_messages (business_id, created_at)
GO
