-- =============================================================================
-- Migration 031: item_price_nullable
-- =============================================================================
-- An item that sells only through its variants (Chicken 65 → half 180 / Full
-- 280) has no meaningful price of its own. Until now items.price was NOT NULL,
-- so such an item had to carry a placeholder — and that placeholder is exactly
-- what got billed when a size wasn't picked (the Chicken 65 incident: a bill at
-- the 230 base price, which is not on the menu).
--
-- Making price NULL-able lets a variant item say "I have no price of my own".
-- The application enforces the pairing:
--   • price NULL  is allowed ONLY for an item that has active variants
--   • price NOT NULL is required for a plain item
-- See the guards in routes/items.js (create/update) and routes/bills.js, which
-- rejects billing a variant item without choosing a size.
--
-- No data changes: every existing row keeps its price. This only relaxes the
-- column so new variant items can omit it.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

ALTER TABLE items
    ALTER COLUMN price DECIMAL(10,2) NULL
GO
