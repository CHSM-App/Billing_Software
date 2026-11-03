-- =============================================================================
-- Migration 065: add_bill_warranty_extra_data
--
-- Lets a cashier capture warranty details (e.g. a tyre's vehicle KM reading)
-- at the moment of billing, so they print on the receipt itself — the
-- customer's proof for a later warranty claim, without relying on the shop
-- separately remembering a record. Same shape and spirit as
-- bills.additional_charges (migration 035): a JSON array filled at sale
-- time, bill-level (shared by every warranty-eligible line in the bill,
-- which in practice is one vehicle/customer at one moment).
--
-- Copied, unmodified, into every warranties.extra_data row the auto-create
-- hook (routes/bills.js autoCreateWarranties) creates for this bill — see
-- migration 064 for that column.
--
-- NULL-able with no backfill: every existing bill simply has nothing extra
-- to show, which is the state every bill is already in today.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE bills
    ADD warranty_extra_data NVARCHAR(MAX) NULL
GO
