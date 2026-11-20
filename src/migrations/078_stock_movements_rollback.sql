-- Drops the stock ledger, the sale cost snapshot and the business-day setting.
-- Live stock_quantity values are unaffected.
IF OBJECT_ID('stock_movements') IS NOT NULL DROP TABLE stock_movements
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('bill_items') AND name = 'unit_cost')
  ALTER TABLE bill_items DROP COLUMN unit_cost
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('businesses') AND name = 'day_end_hour')
BEGIN
  ALTER TABLE businesses DROP CONSTRAINT DF_businesses_day_end_hour
  ALTER TABLE businesses DROP COLUMN day_end_hour
END
GO
