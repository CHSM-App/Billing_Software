-- =============================================================================
-- Migration 043: add users.is_active — disable a staff account without deleting
--
-- There was no way to revoke a staff member's access. DELETE /api/staff/:id
-- refuses anyone who has ever created a bill or an expense (their
-- created_by_user_id is NO ACTION on purpose — financial history must not be
-- rewritten), and tells the owner to "deactivate the account instead" — a
-- capability that did not exist anywhere in the product.
--
-- So for any staff member who had actually worked a shift, the owner's only
-- options were to change their PIN or their role. Neither revokes access: a
-- role change just moves them to a different set of screens.
--
-- DEFAULT 1 so every existing user stays active. Owners are covered by the
-- column too, but routes/staff.js only ever writes it for the managed roles
-- (cashier, server, kitchen) — an owner locked out of their own business would
-- have no way back in.
-- =============================================================================

IF COL_LENGTH('users', 'is_active') IS NULL
    ALTER TABLE users ADD is_active BIT NOT NULL DEFAULT 1
GO
