-- Migration 007: Add whatsapp_otp_log table
-- Stores hashed OTPs for WhatsApp-based phone verification (register + forgot PIN).
-- Safe to run multiple times — uses IF NOT EXISTS guard.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables WHERE name = 'whatsapp_otp_log'
)
BEGIN
    CREATE TABLE whatsapp_otp_log (
        id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
        phone        NVARCHAR(20)     NOT NULL,
        purpose      NVARCHAR(20)     NOT NULL,  -- 'register' | 'forgot_pin'
        otp_hash     NVARCHAR(64)     NOT NULL,  -- SHA-256 hex of the 6-digit OTP
        used         BIT              NOT NULL DEFAULT 0,
        expires_at   DATETIME2        NOT NULL,
        status       NVARCHAR(20)     NULL,      -- 'sent' | 'failed' | 'skipped'
        campaign_id  NVARCHAR(100)    NULL,
        error_detail NVARCHAR(500)    NULL,
        created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT CK_whatsapp_otp_log_purpose CHECK (purpose IN ('register', 'forgot_pin'))
    );

    CREATE INDEX IX_whatsapp_otp_log_phone_purpose
        ON whatsapp_otp_log (phone, purpose, used, expires_at);

    PRINT 'Migration 007: whatsapp_otp_log created.';
END
ELSE
BEGIN
    PRINT 'Migration 007: whatsapp_otp_log already exists — skipped.';
END
