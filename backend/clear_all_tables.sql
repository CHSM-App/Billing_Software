-- =============================================================================
-- clear_all_tables.sql
-- Deletes ALL rows from every table in billing_db.
-- Table structure, constraints, and schema_migrations are preserved.
-- Run order respects FK constraints (children before parents).
-- =============================================================================

-- Leaf / child tables first
DELETE FROM account_deletion_requests;
DELETE FROM audit_logs;
DELETE FROM whatsapp_otp_log;
DELETE FROM bill_items;        -- CASCADE from bills, but delete explicitly
DELETE FROM refresh_tokens;    -- CASCADE from users, but delete explicitly
DELETE FROM expenses;
DELETE FROM recurring_expenses;
DELETE FROM subscriptions;

-- Bills reference users, tables, businesses
DELETE FROM bills;

-- Tables reference businesses
DELETE FROM [tables];

-- Items reference businesses
DELETE FROM items;

-- Users reference businesses
DELETE FROM users;

-- Parent table last
DELETE FROM businesses;

-- Verify all tables are empty
SELECT 'account_deletion_requests' AS tbl, COUNT(*) AS rows FROM account_deletion_requests
UNION ALL SELECT 'audit_logs',           COUNT(*) FROM audit_logs
UNION ALL SELECT 'whatsapp_otp_log',     COUNT(*) FROM whatsapp_otp_log
UNION ALL SELECT 'bill_items',           COUNT(*) FROM bill_items
UNION ALL SELECT 'refresh_tokens',       COUNT(*) FROM refresh_tokens
UNION ALL SELECT 'expenses',             COUNT(*) FROM expenses
UNION ALL SELECT 'recurring_expenses',   COUNT(*) FROM recurring_expenses
UNION ALL SELECT 'subscriptions',        COUNT(*) FROM subscriptions
UNION ALL SELECT 'bills',                COUNT(*) FROM bills
UNION ALL SELECT 'tables',               COUNT(*) FROM [tables]
UNION ALL SELECT 'items',                COUNT(*) FROM items
UNION ALL SELECT 'users',                COUNT(*) FROM users
UNION ALL SELECT 'businesses',           COUNT(*) FROM businesses;
