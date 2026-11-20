-- Drops what migration 082 added. Returned stock stays where it is (it was
-- real stock); 'return' ledger rows remain.
IF OBJECT_ID('sales_return_items') IS NOT NULL DROP TABLE sales_return_items
GO

IF OBJECT_ID('sales_returns') IS NOT NULL DROP TABLE sales_returns
GO
