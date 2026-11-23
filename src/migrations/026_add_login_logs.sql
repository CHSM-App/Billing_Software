-- =============================================================================
-- Migration 026: add_login_logs
--
-- Dedicated login history table. Unlike audit_logs (a general append-only trail),
-- this captures a row for every successful login together with the client IP
-- address and user-agent (device / app identifier) for security review.
--
-- Rows are INSERT-only. No UPDATE or DELETE from application code.
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

CREATE TABLE login_logs (
    -- Surrogate primary key
    id            UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,

    -- Tenant isolation — every row belongs to a business
    business_id   UNIQUEIDENTIFIER NOT NULL,

    -- Who logged in
    user_id       UNIQUEIDENTIFIER NOT NULL,
    user_name     NVARCHAR(200)    NULL,   -- snapshot, survives user rename/deletion
    phone         NVARCHAR(20)     NULL,   -- snapshot of the phone used to log in

    -- Where from / with what
    ip_address    NVARCHAR(64)     NULL,   -- fits IPv4, IPv6, and "ip:port"
    user_agent    NVARCHAR(500)    NULL,   -- device / app identifier

    -- Immutable timestamp (UTC)
    created_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_login_logs_business FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE,
    CONSTRAINT FK_login_logs_user     FOREIGN KEY (user_id)     REFERENCES users(id)      ON DELETE NO ACTION
)
GO

-- Index: filter by business + time (most common query shape — recent logins)
CREATE INDEX IX_login_logs_business_created
    ON login_logs (business_id, created_at DESC)
GO

-- Index: filter by actor (e.g. "login history for user X")
CREATE INDEX IX_login_logs_user_created
    ON login_logs (user_id, created_at DESC)
GO
