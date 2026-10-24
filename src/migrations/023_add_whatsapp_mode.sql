-- =============================================================================
-- Migration 023: WhatsApp delivery mode per business
--
-- Two ways a business sends receipts over WhatsApp:
--   'deeplink' — FREE (default). The app opens the cashier's own WhatsApp with
--                a prefilled message; the cashier taps Send.
--   'api'      — PAID. The backend sends via the WhatsApp Business API template
--                automatically, no cashier action.
--
-- Every existing/new business defaults to 'deeplink'. A platform admin flips a
-- paying customer to 'api' with a one-line UPDATE (no self-serve UI).
-- =============================================================================

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('businesses') AND name = 'whatsapp_mode'
)
  ALTER TABLE businesses
    ADD whatsapp_mode NVARCHAR(20) NOT NULL DEFAULT 'deeplink'
GO
