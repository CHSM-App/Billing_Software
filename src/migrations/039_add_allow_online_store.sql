-- =============================================================================
-- Migration 039: add allow_online_store entitlement
--
-- A platform-admin kill switch for the online store, separate from
-- businesses.store_enabled (the OWNER's own on/off switch, added in 037).
-- Mirrors allow_mobile / allow_desktop from migration 028: same table, same
-- default-allowed backfill, same admin-only write path (/admin/api/businesses).
--
-- Enforcement:
--   * public_store.js's resolveStore() checks it — a de-entitled business's
--     storefront 404s exactly like store_enabled=0 does, so revoking access
--     actually cuts the public link off, not just the Settings menu.
--   * The client hides the "Online Store" entry in Settings when the login
--     response says allow_online_store is false, so a business that was
--     never entitled to it never sees the option to begin with.
--
-- Defaults to 1 (no existing business loses anything it already had).
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_online_store'
)
BEGIN
    ALTER TABLE subscriptions ADD allow_online_store BIT NOT NULL DEFAULT 1
END
GO
