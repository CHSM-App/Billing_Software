-- =============================================================================
-- Migration 038: add_store_upi_id
-- =============================================================================
-- Adds the shop's own UPI ID (VPA) for the online store.
--
-- Why, when 037 already stores an uploaded payment QR: that QR is a JPEG. The
-- VPA lives inside its pixels, so nothing server-side can read it back — which
-- means the checkout page cannot build a payment link, and a customer paying on
-- the SAME phone they ordered from is shown a QR they cannot scan.
--
-- With a VPA the page can emit a `upi://pay?pa=..&am=..` intent: one tap opens
-- their UPI app with the payee AND the amount already filled in. The uploaded
-- QR stays as the fallback for shops that never enter one, and for iOS/desktop
-- where the upi:// scheme does not exist.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF COL_LENGTH('businesses', 'store_upi_id') IS NULL
    ALTER TABLE businesses ADD store_upi_id NVARCHAR(100) NULL
GO
