-- =============================================================================
-- Migration 054: businesses.print_logo — print the shop logo on bills
--
-- The logo itself already lives in businesses.logo_url (migration 005). This is
-- the owner's opt-in: the logo prints on thermal / PDF bills and shows on the
-- WhatsApp receipt only when it is on. Off by default, so nothing changes for
-- existing shops.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'print_logo'
)
  ALTER TABLE businesses ADD print_logo BIT NOT NULL CONSTRAINT DF_businesses_print_logo DEFAULT 0
GO
