-- =============================================================================
-- Migration 017: add_kitchen
-- =============================================================================
-- Adds Kitchen Display support for restaurants. Each bill line item now carries
-- a kitchen preparation status so the kitchen chef can mark individual dishes as
-- ready. When every line on an order (draft bill) is 'ready', the waiter/owner
-- sees the order as ready.
--
-- The Kitchen Chef is modelled as a new user role ('kitchen'); users.role is a
-- free NVARCHAR(20) so no schema change is needed for the role itself.
-- =============================================================================

ALTER TABLE bill_items ADD kitchen_status NVARCHAR(20) NOT NULL DEFAULT 'pending'
GO

ALTER TABLE bill_items ADD kitchen_done_at DATETIME2 NULL
GO

-- Index used by the kitchen order feed to find pending lines quickly.
CREATE INDEX IX_bill_items_kitchen_status ON bill_items (kitchen_status)
GO
