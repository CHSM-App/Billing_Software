-- =============================================================================
-- Migration 021: add_table_qr_ordering
-- =============================================================================
-- Adds customer self-ordering by table QR code.
--
-- Flow: a permanent QR sticker on each table encodes an unguessable qr_token.
-- The customer scans it, the menu opens in a plain browser page (no app),
-- verifies their phone once per table session via WhatsApp OTP, and places
-- orders that land straight on the table's open draft bill and fly to the
-- kitchen. All batches merge into one bill; payment is taken at the counter.
--
-- Columns added:
--   tables.qr_token           - unguessable per-table token used in the QR URL
--   bill_items.source         - 'staff' (POS) | 'customer' (self-order)
--   bill_items.diner_phone    - OTP-verified phone of the ordering diner
--   bill_items.diner_name     - optional name the diner typed
--   items.image_url           - dish photo, shown ONLY on the customer menu
--   businesses.self_order_enabled - per-shop on/off switch
--   businesses.self_order_lat / _lng / _radius_m - geolocation gate PROVISION
--       (columns only; enforcement is intentionally NOT implemented yet)
--
-- Also extends whatsapp_otp_log.purpose to allow 'order'.
--
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

-- --- tables.qr_token ---------------------------------------------------------
IF COL_LENGTH('tables', 'qr_token') IS NULL
    ALTER TABLE tables ADD qr_token NVARCHAR(32) NULL
GO

-- Backfill unguessable tokens for existing tables (32 hex chars from NEWID pair).
UPDATE tables
SET qr_token = REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', '')
WHERE qr_token IS NULL
GO

-- Enforce uniqueness (NULLs excluded so future inserts before backfill are ok).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_tables_qr_token')
    CREATE UNIQUE INDEX UQ_tables_qr_token ON tables (qr_token) WHERE qr_token IS NOT NULL
GO

-- --- bill_items customer-order provenance ------------------------------------
IF COL_LENGTH('bill_items', 'source') IS NULL
    ALTER TABLE bill_items ADD source NVARCHAR(20) NOT NULL DEFAULT 'staff'
GO

IF COL_LENGTH('bill_items', 'diner_phone') IS NULL
    ALTER TABLE bill_items ADD diner_phone NVARCHAR(20) NULL
GO

IF COL_LENGTH('bill_items', 'diner_name') IS NULL
    ALTER TABLE bill_items ADD diner_name NVARCHAR(200) NULL
GO

-- --- items.image_url (customer-facing only) ----------------------------------
IF COL_LENGTH('items', 'image_url') IS NULL
    ALTER TABLE items ADD image_url NVARCHAR(500) NULL
GO

-- --- businesses self-order switch + geolocation provision --------------------
IF COL_LENGTH('businesses', 'self_order_enabled') IS NULL
    ALTER TABLE businesses ADD self_order_enabled BIT NOT NULL DEFAULT 0
GO

-- Geolocation gate: PROVISION ONLY. Columns exist so a later release can verify
-- the customer is physically at the restaurant; nothing enforces them today.
IF COL_LENGTH('businesses', 'self_order_lat') IS NULL
    ALTER TABLE businesses ADD self_order_lat DECIMAL(9,6) NULL
GO

IF COL_LENGTH('businesses', 'self_order_lng') IS NULL
    ALTER TABLE businesses ADD self_order_lng DECIMAL(9,6) NULL
GO

IF COL_LENGTH('businesses', 'self_order_radius_m') IS NULL
    ALTER TABLE businesses ADD self_order_radius_m INT NULL
GO

-- --- whatsapp_otp_log: allow purpose = 'order' -------------------------------
-- The existing CHECK constraint only permits 'register' | 'forgot_pin'. Drop and
-- recreate it to also allow 'order' so customer self-order can reuse the OTP flow.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_whatsapp_otp_log_purpose')
    ALTER TABLE whatsapp_otp_log DROP CONSTRAINT CK_whatsapp_otp_log_purpose
GO

ALTER TABLE whatsapp_otp_log
    ADD CONSTRAINT CK_whatsapp_otp_log_purpose
    CHECK (purpose IN ('register', 'forgot_pin', 'order'))
GO
