-- Rollback 077: drops the WhatsApp send log. Send history is LOST. Roll the
-- code back too — whatsapp.js writes to it and admin.js counts from it.

IF OBJECT_ID('whatsapp_bill_log', 'U') IS NOT NULL
    DROP TABLE whatsapp_bill_log
GO
