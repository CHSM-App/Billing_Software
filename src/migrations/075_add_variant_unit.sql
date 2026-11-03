-- =============================================================================
-- Migration 075: a size's own unit — Rice "Loose" by kg, "5 kg bag" by bag
--
-- NULL = the size is counted in its item's unit (items.unit), which is every
-- size that existed before this. Display and quantity entry only: stock and
-- bill quantities are already per size, so nothing converts between units.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('item_variants') AND name = 'unit'
)
  ALTER TABLE item_variants ADD unit NVARCHAR(20) NULL
GO
