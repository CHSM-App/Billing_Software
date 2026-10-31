-- =============================================================================
-- Migration 058: pack units — "1 box = 15 bottle"
--
-- pack_unit / pack_size let billing show 17 bottles as "1 box + 2" and add a
-- whole box in one tap, and let a purchase be entered in boxes. A shortcut for
-- entry and display only: stock and bill quantities stay in the base unit
-- (items.unit), so billing, stock and reports never read these columns.
--
-- A plain item carries its pack on items; a sized item carries one per size on
-- item_variants (and its items row stays NULL, like its price and stock).
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('items') AND name = 'pack_unit'
)
  ALTER TABLE items ADD pack_unit NVARCHAR(20) NULL, pack_size DECIMAL(10,2) NULL
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('item_variants') AND name = 'pack_unit'
)
  ALTER TABLE item_variants ADD pack_unit NVARCHAR(20) NULL, pack_size DECIMAL(10,2) NULL
GO
