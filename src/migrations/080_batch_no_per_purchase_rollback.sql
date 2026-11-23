-- Back to 079: a unique automatic number per batch row plus a lot no.
-- A typed batch no. becomes the lot no.; every row gets its own number again
-- (a purchase's lines no longer share one), oldest first.
ALTER TABLE stock_batches ADD lot_no NVARCHAR(50) NULL
GO

UPDATE stock_batches SET lot_no = batch_no WHERE batch_seq IS NULL
GO

DROP INDEX IX_stock_batches_seq ON stock_batches
GO

UPDATE b SET b.batch_seq = n.seq
FROM stock_batches b
INNER JOIN (SELECT id, ROW_NUMBER() OVER (PARTITION BY business_id
              ORDER BY received_date, created_at) AS seq
            FROM stock_batches) n ON n.id = b.id
GO

ALTER TABLE stock_batches ALTER COLUMN batch_seq INT NOT NULL
GO

CREATE UNIQUE INDEX UQ_stock_batches_seq ON stock_batches (business_id, batch_seq)
GO

ALTER TABLE stock_batches DROP COLUMN batch_no
GO
