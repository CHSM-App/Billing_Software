-- Drops what migration 081 added. Closed stock goes back into the batches'
-- remaining (it was never a loss); 'return' ledger rows must be gone first.
ALTER TABLE stock_movements DROP CONSTRAINT CK_stock_movements_type
GO

ALTER TABLE stock_movements ADD CONSTRAINT CK_stock_movements_type
  CHECK (movement_type IN ('opening','purchase','sale','void','adjust'))
GO

ALTER TABLE businesses DROP CONSTRAINT DF_businesses_staff_see_cost
GO
ALTER TABLE businesses DROP COLUMN staff_see_cost
GO

ALTER TABLE stock_batches DROP COLUMN qty_remaining
GO
ALTER TABLE stock_batches DROP CONSTRAINT DF_stock_batches_qty_closed
GO
ALTER TABLE stock_batches DROP COLUMN qty_closed
GO
ALTER TABLE stock_batches ADD qty_remaining AS (qty_received - qty_sold - qty_lost)
GO

ALTER TABLE bill_items DROP CONSTRAINT DF_bill_items_stock_taken
GO
ALTER TABLE bill_items DROP COLUMN stock_taken
GO

ALTER TABLE item_variants DROP COLUMN buying_price
GO
ALTER TABLE items DROP COLUMN buying_price
GO

ALTER TABLE items DROP CONSTRAINT DF_items_is_service
GO
ALTER TABLE items DROP COLUMN is_service
GO
