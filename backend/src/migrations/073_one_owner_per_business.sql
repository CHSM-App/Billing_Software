-- =============================================================================
-- Migration 073: one_owner_per_business
--
-- A business has exactly one owner. The app already holds to this — /register
-- creates the owner together with a new business, and staff.js can only
-- create or change cashier/server/kitchen — but nothing stopped an owner row
-- being added by hand, and Sawant Tyre Service ended up with two. This filtered
-- index is the backstop. It counts inactive owners too: a business still has
-- one owner even when that login is switched off.
--
-- BEFORE RUNNING, find businesses with more than one owner and make the extra
-- ones cashiers:
--   SELECT business_id, COUNT(*) AS n FROM users WHERE role = 'owner'
--   GROUP BY business_id HAVING COUNT(*) > 1
-- This migration refuses to run while any remain, rather than failing halfway.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF EXISTS (SELECT business_id FROM users WHERE role = 'owner' GROUP BY business_id HAVING COUNT(*) > 1)
  THROW 50073, 'users has businesses with more than one owner - resolve them before migration 073 (see the query in this file).', 1
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_users_one_owner' AND object_id = OBJECT_ID('users'))
  CREATE UNIQUE INDEX UQ_users_one_owner ON users (business_id) WHERE role = 'owner'
GO
