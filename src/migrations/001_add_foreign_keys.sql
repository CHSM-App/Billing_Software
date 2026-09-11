-- =============================================================================
-- Migration 001: add foreign key constraints, unique constraints, and indexes
-- All statements are idempotent (IF NOT EXISTS / IF EXISTS guards) so this
-- migration is safe to apply against a database that already has some or all
-- of these objects from a manual run.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PRE-FLIGHT: verify no orphan rows exist before adding constraints.
-- Each block raises an error on violation, aborting the batch so the runner
-- will not mark the migration as applied.
-- ---------------------------------------------------------------------------

IF EXISTS (
  SELECT 1 FROM users u
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.id = u.business_id)
)
  RAISERROR('Orphan rows in users.business_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM items i
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.id = i.business_id)
)
  RAISERROR('Orphan rows in items.business_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM tables t
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.id = t.business_id)
)
  RAISERROR('Orphan rows in tables.business_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM bills bl
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.id = bl.business_id)
)
  RAISERROR('Orphan rows in bills.business_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM bills bl
  WHERE bl.table_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM tables t WHERE t.id = bl.table_id)
)
  RAISERROR('Orphan rows in bills.table_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM bills bl
  WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = bl.created_by_user_id)
)
  RAISERROR('Orphan rows in bills.created_by_user_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM bill_items bi
  WHERE NOT EXISTS (SELECT 1 FROM bills bl WHERE bl.id = bi.bill_id)
)
  RAISERROR('Orphan rows in bill_items.bill_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM bill_items bi
  WHERE bi.item_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM items i WHERE i.id = bi.item_id)
)
  RAISERROR('Orphan rows in bill_items.item_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM refresh_tokens rt
  WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = rt.user_id)
)
  RAISERROR('Orphan rows in refresh_tokens.user_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM refresh_tokens rt
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.id = rt.business_id)
)
  RAISERROR('Orphan rows in refresh_tokens.business_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM expenses e
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.id = e.business_id)
)
  RAISERROR('Orphan rows in expenses.business_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM expenses e
  WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = e.created_by_user_id)
)
  RAISERROR('Orphan rows in expenses.created_by_user_id — fix data before migrating', 16, 1)
GO

IF EXISTS (
  SELECT 1 FROM recurring_expenses re
  WHERE NOT EXISTS (SELECT 1 FROM businesses b WHERE b.id = re.business_id)
)
  RAISERROR('Orphan rows in recurring_expenses.business_id — fix data before migrating', 16, 1)
GO

-- ---------------------------------------------------------------------------
-- FOREIGN KEY CONSTRAINTS (skip if already present)
-- ---------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_users_business')
  ALTER TABLE users
    ADD CONSTRAINT FK_users_business
    FOREIGN KEY (business_id) REFERENCES businesses (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_items_business')
  ALTER TABLE items
    ADD CONSTRAINT FK_items_business
    FOREIGN KEY (business_id) REFERENCES businesses (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tables_business')
  ALTER TABLE tables
    ADD CONSTRAINT FK_tables_business
    FOREIGN KEY (business_id) REFERENCES businesses (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bills_business')
  ALTER TABLE bills
    ADD CONSTRAINT FK_bills_business
    FOREIGN KEY (business_id) REFERENCES businesses (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

-- SET NULL: preserves bill record when a table is hard-deleted.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bills_table')
  ALTER TABLE bills
    ADD CONSTRAINT FK_bills_table
    FOREIGN KEY (table_id) REFERENCES tables (id)
    ON UPDATE NO ACTION ON DELETE SET NULL
GO

-- NO ACTION: bills are financial records — must survive staff deletion.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bills_created_by_user')
  ALTER TABLE bills
    ADD CONSTRAINT FK_bills_created_by_user
    FOREIGN KEY (created_by_user_id) REFERENCES users (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

-- CASCADE: line items are owned by the bill.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bill_items_bill')
  ALTER TABLE bill_items
    ADD CONSTRAINT FK_bill_items_bill
    FOREIGN KEY (bill_id) REFERENCES bills (id)
    ON UPDATE NO ACTION ON DELETE CASCADE
GO

-- SET NULL: items are soft-deleted; item_name snapshot preserved in the row.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bill_items_item')
  ALTER TABLE bill_items
    ADD CONSTRAINT FK_bill_items_item
    FOREIGN KEY (item_id) REFERENCES items (id)
    ON UPDATE NO ACTION ON DELETE SET NULL
GO

-- CASCADE: tokens die with the user.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_refresh_tokens_user')
  ALTER TABLE refresh_tokens
    ADD CONSTRAINT FK_refresh_tokens_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON UPDATE NO ACTION ON DELETE CASCADE
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_refresh_tokens_business')
  ALTER TABLE refresh_tokens
    ADD CONSTRAINT FK_refresh_tokens_business
    FOREIGN KEY (business_id) REFERENCES businesses (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_expenses_business')
  ALTER TABLE expenses
    ADD CONSTRAINT FK_expenses_business
    FOREIGN KEY (business_id) REFERENCES businesses (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

-- NO ACTION: expense records are financial audit trail.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_expenses_created_by_user')
  ALTER TABLE expenses
    ADD CONSTRAINT FK_expenses_created_by_user
    FOREIGN KEY (created_by_user_id) REFERENCES users (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_recurring_expenses_business')
  ALTER TABLE recurring_expenses
    ADD CONSTRAINT FK_recurring_expenses_business
    FOREIGN KEY (business_id) REFERENCES businesses (id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
GO

-- ---------------------------------------------------------------------------
-- UNIQUE CONSTRAINTS (skip if already present)
-- ---------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'UQ_users_business_phone' AND type = 'UQ')
  ALTER TABLE users
    ADD CONSTRAINT UQ_users_business_phone UNIQUE (business_id, phone)
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'UQ_bills_business_bill_number' AND type = 'UQ')
  ALTER TABLE bills
    ADD CONSTRAINT UQ_bills_business_bill_number UNIQUE (business_id, bill_number)
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'UQ_tables_business_table_number' AND type = 'UQ')
  ALTER TABLE tables
    ADD CONSTRAINT UQ_tables_business_table_number UNIQUE (business_id, table_number)
GO

-- ---------------------------------------------------------------------------
-- PARTIAL UNIQUE INDEX: one barcode per business (NULLs excluded).
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_items_business_barcode' AND object_id = OBJECT_ID('items'))
  CREATE UNIQUE INDEX UQ_items_business_barcode
    ON items (business_id, barcode)
    WHERE barcode IS NOT NULL
GO

-- ---------------------------------------------------------------------------
-- SUPPORTING INDEXES for FK columns (skip if already present)
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_users_business_id' AND object_id = OBJECT_ID('users'))
  CREATE INDEX IX_users_business_id ON users (business_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_items_business_id' AND object_id = OBJECT_ID('items'))
  CREATE INDEX IX_items_business_id ON items (business_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tables_business_id' AND object_id = OBJECT_ID('tables'))
  CREATE INDEX IX_tables_business_id ON tables (business_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bills_business_id' AND object_id = OBJECT_ID('bills'))
  CREATE INDEX IX_bills_business_id ON bills (business_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bills_table_id' AND object_id = OBJECT_ID('bills'))
  CREATE INDEX IX_bills_table_id ON bills (table_id) WHERE table_id IS NOT NULL
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bills_created_by_user_id' AND object_id = OBJECT_ID('bills'))
  CREATE INDEX IX_bills_created_by_user_id ON bills (created_by_user_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bill_items_bill_id' AND object_id = OBJECT_ID('bill_items'))
  CREATE INDEX IX_bill_items_bill_id ON bill_items (bill_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bill_items_item_id' AND object_id = OBJECT_ID('bill_items'))
  CREATE INDEX IX_bill_items_item_id ON bill_items (item_id) WHERE item_id IS NOT NULL
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_refresh_tokens_user_id' AND object_id = OBJECT_ID('refresh_tokens'))
  CREATE INDEX IX_refresh_tokens_user_id ON refresh_tokens (user_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_expenses_business_id' AND object_id = OBJECT_ID('expenses'))
  CREATE INDEX IX_expenses_business_id ON expenses (business_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_expenses_created_by_user_id' AND object_id = OBJECT_ID('expenses'))
  CREATE INDEX IX_expenses_created_by_user_id ON expenses (created_by_user_id)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_recurring_expenses_biz_id' AND object_id = OBJECT_ID('recurring_expenses'))
  CREATE INDEX IX_recurring_expenses_biz_id ON recurring_expenses (business_id)
GO
