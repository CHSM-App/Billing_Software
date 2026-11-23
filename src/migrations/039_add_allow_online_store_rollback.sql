IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_online_store'
)
BEGIN
    ALTER TABLE subscriptions DROP COLUMN allow_online_store
END
GO
