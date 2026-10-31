-- Deliberately a no-op.
--
-- The forward migration folded 'restaurant_no_tables' into
-- 'restaurant_with_tables', and nothing records which businesses were converted
-- — so there is no way to tell an ex-takeaway shop apart from one that has
-- always had tables. Guessing would re-flag the wrong businesses and take the
-- Tables tab away from shops that depend on it.
--
-- To genuinely reverse this, restore from a backup taken before it ran, or set
-- the affected businesses back by id:
--   UPDATE businesses SET business_type = 'restaurant_no_tables' WHERE id IN (...)
-- and re-add the value to VALID_BUSINESS_TYPES in routes/auth.js.
SELECT 1
GO
