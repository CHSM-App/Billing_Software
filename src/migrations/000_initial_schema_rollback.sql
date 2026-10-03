-- =============================================================================
-- Rollback 000: initial schema
-- WARNING: drops all application tables and all data.
-- Only use on a dev/test database — never on production.
-- =============================================================================

-- Drop in reverse dependency order (children before parents).
DROP TABLE IF EXISTS expenses
GO
DROP TABLE IF EXISTS refresh_tokens
GO
DROP TABLE IF EXISTS recurring_expenses
GO
DROP TABLE IF EXISTS bill_items
GO
DROP TABLE IF EXISTS bills
GO
DROP TABLE IF EXISTS tables
GO
DROP TABLE IF EXISTS items
GO
DROP TABLE IF EXISTS users
GO
DROP TABLE IF EXISTS businesses
GO
