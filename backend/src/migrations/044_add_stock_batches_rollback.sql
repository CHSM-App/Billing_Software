-- Drops batch-wise stock. Item/size stock totals are untouched, so selling
-- keeps working; only batch choice and cost-of-goods history are lost.
ALTER TABLE bill_items DROP COLUMN batch_id, unit_cost
GO

ALTER TABLE vendor_bill_items DROP COLUMN batch_no
GO

DROP TABLE stock_batches
GO
