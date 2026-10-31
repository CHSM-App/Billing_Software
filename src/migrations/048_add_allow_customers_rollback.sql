-- Drops subscriptions.allow_customers (and its DEFAULT constraint). Every
-- business silently regains the Customers feature, so roll the code back too —
-- login, license, admin and routes/customers.js read this column.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_customers'
)
BEGIN
    DECLARE @df NVARCHAR(200) = (
        SELECT dc.name FROM sys.default_constraints dc
        JOIN sys.columns c ON c.default_object_id = dc.object_id
        WHERE dc.parent_object_id = OBJECT_ID('subscriptions') AND c.name = 'allow_customers'
    );
    IF @df IS NOT NULL EXEC('ALTER TABLE subscriptions DROP CONSTRAINT ' + @df);
    ALTER TABLE subscriptions DROP COLUMN allow_customers;
END
GO
