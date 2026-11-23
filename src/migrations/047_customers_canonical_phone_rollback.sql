-- Drops dbo.canonical_phone. The duplicate merge is NOT undone (the extra rows
-- were the same person) and phones stay in canonical 10-digit form. Roll the
-- code back too: the customer sync calls this function, and 046-era code
-- matched bills by exact text, so it would no longer find bills saved as
-- 91XXXXXXXXXX for a merged customer.
IF OBJECT_ID('dbo.canonical_phone', 'FN') IS NOT NULL DROP FUNCTION dbo.canonical_phone
GO
