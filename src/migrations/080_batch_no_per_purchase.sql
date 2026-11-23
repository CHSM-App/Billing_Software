-- =============================================================================
-- Migration 080: one batch no. per purchase, typed or automatic
--
-- 079 gave every purchase LINE its own unique code (B-0001, B-0002 ...) plus
-- a separate supplier lot no. — two ids for one idea. Now a batch no. names a
-- delivery: all lines of one purchase share it (Rice and Sugar both "B-0007"),
-- and the owner may type the supplier's own batch number instead. Stock and
-- cost are still kept per item inside it; the item + batch no. pair is what
-- billing and reports read, so a shared code is never ambiguous.
--
--   * stock_batches.batch_no — the shown code. Not unique.
--   * stock_batches.batch_seq — the automatic number behind "B-0007", NULL
--     for a typed code; no longer unique (a purchase's lines share it).
--   * stock_batches.lot_no — dropped, folded into batch_no.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE stock_batches ADD batch_no NVARCHAR(50) NULL
GO

-- Existing batches: the lot the owner typed, else their automatic code.
UPDATE stock_batches SET batch_no = COALESCE(NULLIF(LTRIM(RTRIM(lot_no)), ''),
  'B-' + CASE WHEN batch_seq >= 10000 THEN CAST(batch_seq AS NVARCHAR(10))
              ELSE RIGHT('0000' + CAST(batch_seq AS NVARCHAR(10)), 4) END)
GO

ALTER TABLE stock_batches ALTER COLUMN batch_no NVARCHAR(50) NOT NULL
GO

DROP INDEX UQ_stock_batches_seq ON stock_batches
GO

ALTER TABLE stock_batches ALTER COLUMN batch_seq INT NULL
GO

-- A batch named by its typed lot holds no automatic number, so the next
-- purchase's B-code doesn't skip past it.
UPDATE stock_batches SET batch_seq = NULL
WHERE batch_no <> 'B-' + CASE WHEN batch_seq >= 10000 THEN CAST(batch_seq AS NVARCHAR(10))
                              ELSE RIGHT('0000' + CAST(batch_seq AS NVARCHAR(10)), 4) END
GO

-- The next automatic number is MAX(batch_seq) + 1 per business.
CREATE INDEX IX_stock_batches_seq ON stock_batches (business_id, batch_seq)
GO

ALTER TABLE stock_batches DROP COLUMN lot_no
GO
