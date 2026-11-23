-- =============================================================================
-- Migration 028: add per-business entitlements to subscriptions
--
--   max_staff     — cap on staff (cashier/server/kitchen) a business may add.
--                   Owners never count. Default 10 (backfills existing rows).
--   allow_mobile  — may the business use the app on mobile (Android/iOS)?
--   allow_desktop — may the business use the app on desktop (Windows/web)?
--
-- Both device flags default to 1 (no restriction) so no existing or new
-- business is locked out; admin narrows them per business via /admin/activate.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'max_staff'
)
BEGIN
    ALTER TABLE subscriptions ADD max_staff INT NOT NULL DEFAULT 10
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_mobile'
)
BEGIN
    ALTER TABLE subscriptions ADD allow_mobile BIT NOT NULL DEFAULT 1
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_desktop'
)
BEGIN
    ALTER TABLE subscriptions ADD allow_desktop BIT NOT NULL DEFAULT 1
END
GO
