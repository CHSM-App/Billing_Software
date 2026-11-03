-- =============================================================================
-- Migration 071: users_phone_unique
--
-- One phone number = one login, across all businesses. POST /api/login finds
-- the user by phone alone; with the old (business_id, phone) uniqueness any
-- owner could add someone else's number as "staff", and login then picked one
-- of the two rows — locking the real person out, or landing them in the wrong
-- shop. staff.js and /register now check globally; this is the backstop.
--
-- BEFORE RUNNING, find duplicates and resolve each with the shop owners:
--   SELECT phone, COUNT(*) AS n FROM users GROUP BY phone HAVING COUNT(*) > 1
-- This migration refuses to run while any remain, rather than failing halfway.
--
-- users is small (a few rows per business), so the index builds in moments.
-- The old UQ_users_business_phone is kept: it is implied by the new one, and
-- dropping it buys nothing.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF EXISTS (SELECT phone FROM users GROUP BY phone HAVING COUNT(*) > 1)
  THROW 50071, 'users has duplicate phone numbers - resolve them before migration 071 (see the query in this file).', 1
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_users_phone' AND object_id = OBJECT_ID('users'))
  CREATE UNIQUE INDEX UQ_users_phone ON users (phone)
GO
