-- =============================================================================
-- Migration 067: add_user_notify_prefs
--
-- Per-person switches for the two visible push notifications, set from
-- Settings on each person's own phone:
--   users.notify_low_stock     - owner gets a low-stock alert (fcm.js
--                                sendLowStockNotification targets owners only)
--   users.notify_online_orders - online-store and QR table orders
--
-- Default 1 so every existing owner/cashier keeps getting what they get today.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE users
    ADD notify_low_stock     BIT NOT NULL DEFAULT 1,
        notify_online_orders BIT NOT NULL DEFAULT 1
GO
