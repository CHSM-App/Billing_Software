-- =============================================================================
-- Rollback for Migration 021: add_table_qr_ordering
-- =============================================================================
-- Reverses the columns/indexes/constraint added by 021. Restores the original
-- whatsapp_otp_log purpose CHECK ('register' | 'forgot_pin').
-- =============================================================================

-- --- whatsapp_otp_log purpose CHECK back to original -------------------------
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_whatsapp_otp_log_purpose')
    ALTER TABLE whatsapp_otp_log DROP CONSTRAINT CK_whatsapp_otp_log_purpose
GO

ALTER TABLE whatsapp_otp_log
    ADD CONSTRAINT CK_whatsapp_otp_log_purpose
    CHECK (purpose IN ('register', 'forgot_pin'))
GO

-- --- businesses ---------------------------------------------------------------
IF COL_LENGTH('businesses', 'self_order_radius_m') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN self_order_radius_m
GO
IF COL_LENGTH('businesses', 'self_order_lng') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN self_order_lng
GO
IF COL_LENGTH('businesses', 'self_order_lat') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN self_order_lat
GO
-- Default constraint must be dropped before the column on some SQL Server setups.
DECLARE @df sysname
SELECT @df = dc.name FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE c.object_id = OBJECT_ID('businesses') AND c.name = 'self_order_enabled'
IF @df IS NOT NULL EXEC('ALTER TABLE businesses DROP CONSTRAINT ' + @df)
IF COL_LENGTH('businesses', 'self_order_enabled') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN self_order_enabled
GO

-- --- items --------------------------------------------------------------------
IF COL_LENGTH('items', 'image_url') IS NOT NULL
    ALTER TABLE items DROP COLUMN image_url
GO

-- --- bill_items ---------------------------------------------------------------
IF COL_LENGTH('bill_items', 'diner_name') IS NOT NULL
    ALTER TABLE bill_items DROP COLUMN diner_name
GO
IF COL_LENGTH('bill_items', 'diner_phone') IS NOT NULL
    ALTER TABLE bill_items DROP COLUMN diner_phone
GO
DECLARE @df2 sysname
SELECT @df2 = dc.name FROM sys.default_constraints dc
    JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE c.object_id = OBJECT_ID('bill_items') AND c.name = 'source'
IF @df2 IS NOT NULL EXEC('ALTER TABLE bill_items DROP CONSTRAINT ' + @df2)
IF COL_LENGTH('bill_items', 'source') IS NOT NULL
    ALTER TABLE bill_items DROP COLUMN source
GO

-- --- tables -------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_tables_qr_token')
    DROP INDEX UQ_tables_qr_token ON tables
GO
IF COL_LENGTH('tables', 'qr_token') IS NOT NULL
    ALTER TABLE tables DROP COLUMN qr_token
GO
