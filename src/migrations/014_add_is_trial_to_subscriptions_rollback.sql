-- Rollback 014: remove is_trial from subscriptions
-- The default constraint must be dropped before the column.

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'is_trial'
)
BEGIN
    DECLARE @constraint NVARCHAR(200)
    SELECT @constraint = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c
        ON c.object_id = dc.parent_object_id
       AND c.column_id = dc.parent_column_id
    WHERE c.object_id = OBJECT_ID('subscriptions') AND c.name = 'is_trial'

    IF @constraint IS NOT NULL
        EXEC('ALTER TABLE subscriptions DROP CONSTRAINT ' + @constraint)

    ALTER TABLE subscriptions DROP COLUMN is_trial
END
GO
