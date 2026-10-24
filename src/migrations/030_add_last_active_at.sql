-- =============================================================================
-- Migration 030: add_last_active_at
-- =============================================================================
-- Tracks the last time any user of a business used the app. Stamped whenever an
-- authenticated user hits GET /api/license (fired on every app open / resume),
-- so the admin dashboard can show how recently each business was active.
--
-- Nullable: existing businesses that have not opened the app since this ships
-- read as NULL ("never" / "—") until their next app open.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE businesses
    ADD last_active_at DATETIME2 NULL
GO
