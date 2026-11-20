-- Drops what migration 055 added. Item discounts already sit inside unit_price,
-- so bill totals are unaffected; only the "(Disc ₹x)" annotation is lost.
IF EXISTS (
  SELECT 1 FROM sys.default_constraints WHERE name = 'DF_bill_items_discount_amount'
)
  ALTER TABLE bill_items DROP CONSTRAINT DF_bill_items_discount_amount
GO

IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('bill_items') AND name = 'discount_amount'
)
  ALTER TABLE bill_items DROP COLUMN discount_amount
GO
