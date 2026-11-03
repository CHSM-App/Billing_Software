-- =============================================================================
-- Migration 063: add_warranty_field_templates
--
-- "Retail & Warranty" shops sell very different kinds of product under one
-- roof (tyres, batteries, electronics, "etc."), each needing different extra
-- details on a warranty record — a tyre wants "KM reading"/"vehicle number",
-- an electronics item wants "serial number"/"IMEI". Rather than hard-code a
-- fixed set of fields, each business defines its own field list once per
-- item CATEGORY (items.category — a free-text group, with deliberately no
-- categories table, same convention followed here: this table has no FK to
-- a category row, just a plain string that happens to match).
--
-- One row per (business, category). `fields` is a UI-authored JSON array of
-- {key, label, type} — see routes/warranty_field_templates.js for the shape
-- and validation. Values entered against a template are stored on the
-- warranty record itself (warranties.extra_data, migration 064), not here —
-- so editing a template later never rewrites past records.
--
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

IF OBJECT_ID('warranty_field_templates', 'U') IS NULL
CREATE TABLE warranty_field_templates (
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id   UNIQUEIDENTIFIER NOT NULL,
    category      NVARCHAR(100)    NOT NULL,
    fields        NVARCHAR(MAX)    NOT NULL,
    created_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    updated_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_warranty_field_templates_business
        FOREIGN KEY (business_id) REFERENCES businesses (id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT UQ_warranty_field_templates_business_category
        UNIQUE (business_id, category)
)
GO
