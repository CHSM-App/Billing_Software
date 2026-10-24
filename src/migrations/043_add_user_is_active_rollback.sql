-- Drops users.is_active. Every disabled account silently becomes active again,
-- so roll the code back at the same time — login, the license check and the
-- staff routes all read this column.
IF COL_LENGTH('users', 'is_active') IS NOT NULL
BEGIN
    DECLARE @df NVARCHAR(200) = (
        SELECT dc.name FROM sys.default_constraints dc
        JOIN sys.columns c ON c.default_object_id = dc.object_id
        WHERE dc.parent_object_id = OBJECT_ID('users') AND c.name = 'is_active'
    );
    IF @df IS NOT NULL EXEC('ALTER TABLE users DROP CONSTRAINT ' + @df);
    ALTER TABLE users DROP COLUMN is_active;
END
GO
