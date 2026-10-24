-- =============================================================================
-- Migration 035: add_additional_charges
-- =============================================================================
-- Adds bill-level additional charges (delivery, packaging, service, ...).
-- Additive and zero by default, so every existing bill is untouched:
--   bills.charges_amount      - sum of the charges on the bill (0 = none)
--   bills.additional_charges  - JSON detail: [{"name":"Delivery","amount":30}]
--
-- Reconciliation model:
--   total = subtotal + tax_amount + charges_amount
--   The final payable stays  total - discount_amount + round_off,  so reports,
--   credit outstanding and round-off derivation keep working unchanged.
--   Charges are outside the taxable base: no GST applies to them and the
--   discount (clamped to the item subtotal) never reduces them.
--
-- Use GO as the batch separator. No BEGIN/COMMIT — runner manages atomicity.
-- =============================================================================

ALTER TABLE bills
    ADD charges_amount DECIMAL(10, 2) NOT NULL DEFAULT 0
GO

ALTER TABLE bills
    ADD additional_charges NVARCHAR(MAX) NULL
GO
