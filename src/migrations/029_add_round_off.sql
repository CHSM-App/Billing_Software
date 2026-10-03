-- =============================================================================
-- Migration 029: add_round_off
-- =============================================================================
-- Adds invoice-level round-off support. All additive and OFF by default so
-- existing businesses bill exactly as before:
--   businesses.round_off_enabled - master toggle (0 = off; no rounding applied)
--   bills.round_off              - signed per-bill adjustment (e.g. -0.22, +0.40)
--
-- Reconciliation model (nothing existing is mutated):
--   subtotal, tax_amount, discount_amount, total stay EXACTLY as computed.
--   round_off is stored separately; the final payable is:
--     final_payable = total - discount_amount + round_off
--   When rounding is disabled, round_off is always 0 and final_payable is
--   unchanged (total - discount_amount), so old bills reconcile untouched.
--
-- Use GO as the batch separator. No BEGIN/COMMIT — runner manages atomicity.
-- =============================================================================

ALTER TABLE businesses
    ADD round_off_enabled BIT NOT NULL DEFAULT 0
GO

ALTER TABLE bills
    ADD round_off DECIMAL(10, 2) NOT NULL DEFAULT 0
GO
