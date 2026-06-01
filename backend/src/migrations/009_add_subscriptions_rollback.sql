-- Rollback 009: Drop subscriptions table
IF EXISTS (
    SELECT 1 FROM sys.objects WHERE name = 'subscriptions' AND type = 'U'
)
BEGIN
    DROP TABLE subscriptions
END
GO
