-- =============================================================================
-- Rollback 001: remove foreign key constraints, unique constraints, and indexes
-- =============================================================================

-- Supporting indexes
DROP INDEX IF EXISTS IX_recurring_expenses_biz_id   ON recurring_expenses
GO
DROP INDEX IF EXISTS IX_expenses_created_by_user_id ON expenses
GO
DROP INDEX IF EXISTS IX_expenses_business_id        ON expenses
GO
DROP INDEX IF EXISTS IX_refresh_tokens_user_id      ON refresh_tokens
GO
DROP INDEX IF EXISTS IX_bill_items_item_id          ON bill_items
GO
DROP INDEX IF EXISTS IX_bill_items_bill_id          ON bill_items
GO
DROP INDEX IF EXISTS IX_bills_created_by_user_id    ON bills
GO
DROP INDEX IF EXISTS IX_bills_table_id              ON bills
GO
DROP INDEX IF EXISTS IX_bills_business_id           ON bills
GO
DROP INDEX IF EXISTS IX_tables_business_id          ON tables
GO
DROP INDEX IF EXISTS IX_items_business_id           ON items
GO
DROP INDEX IF EXISTS IX_users_business_id           ON users
GO

-- Partial unique index (was created with CREATE UNIQUE INDEX, not ALTER TABLE)
DROP INDEX IF EXISTS UQ_items_business_barcode ON items
GO

-- Unique constraints
ALTER TABLE tables DROP CONSTRAINT IF EXISTS UQ_tables_business_table_number
GO
ALTER TABLE bills  DROP CONSTRAINT IF EXISTS UQ_bills_business_bill_number
GO
ALTER TABLE users  DROP CONSTRAINT IF EXISTS UQ_users_business_phone
GO

-- Foreign keys
ALTER TABLE recurring_expenses DROP CONSTRAINT IF EXISTS FK_recurring_expenses_business
GO
ALTER TABLE expenses           DROP CONSTRAINT IF EXISTS FK_expenses_created_by_user
GO
ALTER TABLE expenses           DROP CONSTRAINT IF EXISTS FK_expenses_business
GO
ALTER TABLE refresh_tokens     DROP CONSTRAINT IF EXISTS FK_refresh_tokens_business
GO
ALTER TABLE refresh_tokens     DROP CONSTRAINT IF EXISTS FK_refresh_tokens_user
GO
ALTER TABLE bill_items         DROP CONSTRAINT IF EXISTS FK_bill_items_item
GO
ALTER TABLE bill_items         DROP CONSTRAINT IF EXISTS FK_bill_items_bill
GO
ALTER TABLE bills              DROP CONSTRAINT IF EXISTS FK_bills_created_by_user
GO
ALTER TABLE bills              DROP CONSTRAINT IF EXISTS FK_bills_table
GO
ALTER TABLE bills              DROP CONSTRAINT IF EXISTS FK_bills_business
GO
ALTER TABLE tables             DROP CONSTRAINT IF EXISTS FK_tables_business
GO
ALTER TABLE items              DROP CONSTRAINT IF EXISTS FK_items_business
GO
ALTER TABLE users              DROP CONSTRAINT IF EXISTS FK_users_business
GO
