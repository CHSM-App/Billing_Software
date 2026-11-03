-- Drops the default only. The backfilled tokens are deliberately left in place:
-- they are live public store links by now, and clearing them would 404 every
-- storefront that has been shared.
IF EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE name = 'DF_businesses_store_token'
)
BEGIN
    ALTER TABLE businesses DROP CONSTRAINT DF_businesses_store_token
END
GO
