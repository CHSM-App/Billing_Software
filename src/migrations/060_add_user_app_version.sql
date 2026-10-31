-- =============================================================================
-- Migration 060: users.app_version — which app build each person is running
--
-- The app sends its version ("1.1.15+28") on GET /api/license, which it calls
-- on every open. Stored per user, not per business: an owner and a cashier on
-- different phones can be on different builds. Shown in the admin dashboard.
--
-- NULL = never reported (user hasn't opened a build that sends it yet).
-- =============================================================================

IF COL_LENGTH('users', 'app_version') IS NULL
    ALTER TABLE users ADD app_version NVARCHAR(30) NULL
GO
