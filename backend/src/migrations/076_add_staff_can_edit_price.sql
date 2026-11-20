-- =============================================================================
-- Migration 076: owner switch — may staff edit prices and give discounts?
--
-- 1 (the default) = today's behaviour: a cashier can retype a line's price,
-- give a line discount and a bill discount. 0 = only the owner can; staff can
-- still bill at one of the owner's price lists. Enforced in routes/bills.js.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'staff_can_edit_price'
)
  ALTER TABLE businesses ADD staff_can_edit_price BIT NOT NULL DEFAULT 1
GO
