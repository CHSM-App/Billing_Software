-- Moves batch_no back onto each purchase line (every line gets its bill's).
ALTER TABLE vendor_bill_items ADD batch_no NVARCHAR(50) NULL
GO

UPDATE vbi SET batch_no = vb.batch_no
FROM vendor_bill_items vbi
JOIN vendor_bills vb ON vb.id = vbi.vendor_bill_id
GO

ALTER TABLE vendor_bills DROP COLUMN batch_no
GO
