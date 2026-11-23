-- Drops users.app_version. Roll the code back too — GET /api/license writes it
-- and the admin dashboard reads it.
IF COL_LENGTH('users', 'app_version') IS NOT NULL
    ALTER TABLE users DROP COLUMN app_version
GO
