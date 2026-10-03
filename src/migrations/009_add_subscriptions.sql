-- Migration 009: Add subscriptions table for license management
-- Each business has one subscription row controlling app access.

IF NOT EXISTS (
    SELECT 1 FROM sys.objects WHERE name = 'subscriptions' AND type = 'U'
)
BEGIN
    CREATE TABLE subscriptions (
        business_id        UNIQUEIDENTIFIER NOT NULL,
        status             NVARCHAR(20)     NOT NULL DEFAULT 'pending',
        expires_at         DATETIME2        NOT NULL,
        max_offline_days   INT              NOT NULL DEFAULT 30,
        grace_period_days  INT              NOT NULL DEFAULT 5,
        created_at         DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
        updated_at         DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT PK_subscriptions PRIMARY KEY (business_id),
        CONSTRAINT FK_subscriptions_business FOREIGN KEY (business_id)
            REFERENCES businesses(id),
        CONSTRAINT CK_subscriptions_status CHECK (status IN (
            'pending', 'active', 'suspended', 'expired'
        ))
    )
END
GO

-- Index: status lookup (to quickly find all active/expired subscriptions)
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes WHERE name = 'IX_subscriptions_status'
)
BEGIN
    CREATE INDEX IX_subscriptions_status
        ON subscriptions (status, expires_at)
END
GO
