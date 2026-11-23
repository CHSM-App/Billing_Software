-- Rollback 074: removes AI bill scanning's tables and columns. Scan history,
-- learned vendor item mappings and free quantities on purchase lines are LOST,
-- and stored bill files under backend/private_uploads are orphaned (delete the
-- folder by hand). Roll the code back too — vendor_bills.js reads these columns.

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('subscriptions') AND name = 'purchase_scan_limit')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_subscriptions_purchase_scan_limit')
        ALTER TABLE subscriptions DROP CONSTRAINT CK_subscriptions_purchase_scan_limit;
    ALTER TABLE subscriptions DROP COLUMN purchase_scan_limit;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('subscriptions') AND name = 'allow_purchase_scan')
    ALTER TABLE subscriptions DROP COLUMN allow_purchase_scan
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('vendor_bill_items') AND name = 'free_quantity')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_vendor_bill_items_free_quantity')
        ALTER TABLE vendor_bill_items DROP CONSTRAINT CK_vendor_bill_items_free_quantity;
    IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_vendor_bill_items_free_quantity')
        ALTER TABLE vendor_bill_items DROP CONSTRAINT DF_vendor_bill_items_free_quantity;
    ALTER TABLE vendor_bill_items DROP COLUMN free_quantity;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('vendor_bills') AND name = 'scan_id')
    ALTER TABLE vendor_bills DROP COLUMN scan_id
GO

IF OBJECT_ID('vendor_item_aliases', 'U') IS NOT NULL
    DROP TABLE vendor_item_aliases
GO

IF OBJECT_ID('purchase_scans', 'U') IS NOT NULL
    DROP TABLE purchase_scans
GO
