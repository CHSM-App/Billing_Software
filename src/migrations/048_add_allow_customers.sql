-- =============================================================================
-- Migration 048: add allow_customers entitlement
--
-- A platform-admin switch for the owner's Customers & campaigns feature
-- (routes/customers.js — customer list, bills by customer, WhatsApp offers).
-- Mirrors allow_online_store (039): same table, default-allowed, same
-- admin-only write path (PUT /admin/api/businesses/:id).
--
-- Enforcement:
--   * routes/customers.js refuses every /api/customers call (403
--     customers_disabled) while it is 0 — including sending messages, which
--     cost money on the shared WhatsApp account.
--   * /api/login and /api/license send it, and the app hides the Customers
--     entry in Profile when it is false.
--
-- Defaults to 1: every business, existing and new, has the feature unless an
-- admin turns it off.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_customers'
)
BEGIN
    ALTER TABLE subscriptions ADD allow_customers BIT NOT NULL DEFAULT 1
END
GO
