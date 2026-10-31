-- Drops what migration 061 added. Bill settings and customer address/GSTIN
-- are lost. Roll the code back too.
IF COL_LENGTH('bills', 'customer_gstin') IS NOT NULL
    ALTER TABLE bills DROP COLUMN customer_gstin
GO

IF COL_LENGTH('bills', 'customer_address') IS NOT NULL
    ALTER TABLE bills DROP COLUMN customer_address
GO

IF COL_LENGTH('customers', 'gstin') IS NOT NULL
    ALTER TABLE customers DROP COLUMN gstin
GO

IF COL_LENGTH('customers', 'address') IS NOT NULL
    ALTER TABLE customers DROP COLUMN address
GO

IF COL_LENGTH('businesses', 'bill_settings') IS NOT NULL
    ALTER TABLE businesses DROP COLUMN bill_settings
GO
