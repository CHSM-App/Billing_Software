-- =============================================================================
-- Migration 061: bill print settings + customer address / GSTIN
--
-- businesses.bill_settings: JSON text of what prints on a bill (header lines,
-- cashier, customer block, HSN summary, terms, bank details). Shape and
-- defaults live in src/billSettings.js. NULL = defaults = today's bill.
--
-- customers.address / gstin: latest known values, auto-filled at billing.
-- bills.customer_address / customer_gstin: snapshot on the bill, so an old
-- invoice never changes when the customer record is edited.
--
-- All columns NULL-able, no defaults: older app builds never send them and
-- keep working unchanged.
-- =============================================================================

IF COL_LENGTH('businesses', 'bill_settings') IS NULL
    ALTER TABLE businesses ADD bill_settings NVARCHAR(2000) NULL
GO

IF COL_LENGTH('customers', 'address') IS NULL
    ALTER TABLE customers ADD address NVARCHAR(500) NULL
GO

IF COL_LENGTH('customers', 'gstin') IS NULL
    ALTER TABLE customers ADD gstin NVARCHAR(15) NULL
GO

IF COL_LENGTH('bills', 'customer_address') IS NULL
    ALTER TABLE bills ADD customer_address NVARCHAR(500) NULL
GO

IF COL_LENGTH('bills', 'customer_gstin') IS NULL
    ALTER TABLE bills ADD customer_gstin NVARCHAR(15) NULL
GO
