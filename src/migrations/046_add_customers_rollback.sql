-- Drops the two tables migration 046 added. bills is untouched by 046, so no
-- invoice data is lost — only opt-outs and the campaign send log. Roll the code
-- back at the same time: routes/customers.js and the billing customer search
-- read these tables.
IF OBJECT_ID('campaign_messages', 'U') IS NOT NULL DROP TABLE campaign_messages
GO
IF OBJECT_ID('customers', 'U') IS NOT NULL DROP TABLE customers
GO
