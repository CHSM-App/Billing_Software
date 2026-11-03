-- =============================================================================
-- Migration 041: retire the 'restaurant_no_tables' business type
--
-- A restaurant now always runs with tables. The takeaway-only variant is gone
-- from the sign-up picker and from VALID_BUSINESS_TYPES in routes/auth.js, so
-- no new business can be created with it — this converts the ones that already
-- exist so a single value means "restaurant" everywhere.
--
-- WHY CONVERT RATHER THAN LEAVE THEM. business_type is read as a feature flag
-- all over the app (the Tables tab, the kitchen queue, stock targets, the staff
-- roles offered). Leaving stragglers on a value the code is no longer written
-- around means those shops slowly drift into untested branches as the old value
-- is dropped from each check. One value, one behaviour.
--
-- WHAT THIS CHANGES FOR AN AFFECTED SHOP: they gain the Tables tab and table
-- management. Nothing is lost — a table-less restaurant is a restaurant with no
-- tables defined yet, which is exactly the state they end up in. Their items,
-- bills and staff are untouched; only the flag moves.
--
-- There is no CHECK constraint on the column to update: the permitted values
-- live in application code (routes/auth.js), and schema.sql documents them in
-- a comment only.
-- =============================================================================

UPDATE businesses
SET business_type = 'restaurant_with_tables'
WHERE business_type = 'restaurant_no_tables'
GO
