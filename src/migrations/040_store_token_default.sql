-- =============================================================================
-- Migration 040: give businesses.store_token a DEFAULT (and backfill again)
--
-- Migration 037 added store_token and backfilled every business that existed
-- AT THAT MOMENT, on the promise that "every business gets one even while the
-- store is off, so turning the feature on is a single flag flip and the link is
-- stable from day one". Nothing kept that promise for businesses registered
-- afterwards: the column is nullable with no default, and the sign-up INSERT in
-- routes/auth.js never listed it. So every business created since 037 shipped
-- has store_token = NULL.
--
-- The symptom is silent, which is why it went unnoticed: the unique index is
-- filtered (WHERE store_token IS NOT NULL), so a NULL never raises; and
-- store_settings_screen.dart renders a null token as an EMPTY link card rather
-- than an error. The owner just sees a blank link and nothing to copy.
--
-- Fixed with a column DEFAULT rather than by editing the sign-up INSERT: the
-- default holds for every insert path there will ever be, including any future
-- one that forgets the column exactly the way auth.js did.
--
-- Same expression as 037's backfill (32 hex chars from NEWID) so old and new
-- tokens are indistinguishable in shape.
--
-- NOTE: routes/auth.js now DOES set store_token explicitly, to a readable slug
-- of the business name (src/storeToken.js) — /store/vengurla-tech rather than
-- /store/a658e220…. This default is therefore the safety net, not the usual
-- path: it only fires for an insert that omits the column, and guarantees such
-- a business still gets a working link instead of the NULL described above.
-- The backfill below deliberately hands out RANDOM tokens, not slugs: these
-- businesses' links may already be shared or printed, and this migration is not
-- the place to rename them.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

-- --- 1. The default, for every business created from here on -----------------
IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE name = 'DF_businesses_store_token'
)
BEGIN
    ALTER TABLE businesses
        ADD CONSTRAINT DF_businesses_store_token
        DEFAULT REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', '') FOR store_token
END
GO

-- --- 2. Backfill the ones that slipped through between 037 and now -----------
-- NEWID() is evaluated per row, so this hands out a distinct token to each
-- business rather than one token repeated (which the unique index would reject).
UPDATE businesses
SET store_token = REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', '')
WHERE store_token IS NULL
GO
