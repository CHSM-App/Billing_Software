-- =============================================================================
-- Migration 047: one customer per real phone number
--
-- The billing app saves 9876543210, while the online store and QR table orders
-- save 919876543210 (normalisePhone's WhatsApp format). Migration 046 keyed
-- customers on the raw text, so the same person appeared twice.
--
-- From now on customers.phone holds the canonical 10-digit form. bills are
-- still NOT touched — they keep the number exactly as typed; queries match a
-- customer to their bills across every format (src/customers.js
-- billPhoneMatch).
--
-- dbo.canonical_phone MUST stay identical to canonicalPhone() in
-- src/customers.js.
-- =============================================================================

IF OBJECT_ID('dbo.canonical_phone', 'FN') IS NOT NULL DROP FUNCTION dbo.canonical_phone
GO

CREATE FUNCTION dbo.canonical_phone (@p NVARCHAR(40))
RETURNS NVARCHAR(20)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @d NVARCHAR(40) =
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            LTRIM(RTRIM(ISNULL(@p, N''))),
            N'+', N''), N' ', N''), N'-', N''), N'(', N''), N')', N''), N'.', N'');
    IF LEN(@d) = 12 AND LEFT(@d, 2) = N'91' RETURN RIGHT(@d, 10);
    IF LEN(@d) = 11 AND LEFT(@d, 1) = N'0' RETURN RIGHT(@d, 10);
    RETURN LEFT(@d, 20);
END
GO

-- Merge rows that are the same number, then store every phone canonically.
-- One batch + one transaction: the temp table must survive, and a failure must
-- leave customers exactly as it was.
SET XACT_ABORT ON;
BEGIN TRANSACTION;

SELECT id, business_id, name, opted_out, opted_out_at, updated_at,
       dbo.canonical_phone(phone) AS canon,
       ROW_NUMBER() OVER (
           PARTITION BY business_id, dbo.canonical_phone(phone)
           ORDER BY updated_at DESC, created_at DESC) AS rn
INTO #c
FROM customers;

-- The kept row inherits an opt-out from ANY duplicate: someone who asked to
-- stop receiving offers must not start getting them because of a merge.
UPDATE s
SET opted_out = 1, opted_out_at = COALESCE(s.opted_out_at, d.oa)
FROM customers s
JOIN #c k ON k.id = s.id AND k.rn = 1
JOIN (SELECT business_id, canon, MAX(opted_out_at) AS oa
      FROM #c WHERE opted_out = 1 GROUP BY business_id, canon) d
  ON d.business_id = k.business_id AND d.canon = k.canon
WHERE s.opted_out = 0;

-- Keep a name if the surviving row has none.
UPDATE s
SET name = l.name
FROM customers s
JOIN #c k ON k.id = s.id AND k.rn = 1
CROSS APPLY (SELECT TOP 1 x.name FROM #c x
             WHERE x.business_id = k.business_id AND x.canon = k.canon AND x.name IS NOT NULL
             ORDER BY x.updated_at DESC) l
WHERE s.name IS NULL;

-- Point the send log at the surviving row, then drop the duplicates.
UPDATE m
SET customer_id = k.id
FROM campaign_messages m
JOIN #c dup ON dup.id = m.customer_id AND dup.rn > 1
JOIN #c k ON k.business_id = dup.business_id AND k.canon = dup.canon AND k.rn = 1;

DELETE c FROM customers c JOIN #c dup ON dup.id = c.id AND dup.rn > 1;

UPDATE c
SET phone = k.canon, updated_at = GETUTCDATE()
FROM customers c
JOIN #c k ON k.id = c.id AND k.rn = 1
WHERE c.phone <> k.canon;

DROP TABLE #c;
COMMIT TRANSACTION;
GO
