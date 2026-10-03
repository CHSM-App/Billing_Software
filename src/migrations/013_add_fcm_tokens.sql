-- =============================================================================
-- Migration 013: add_fcm_tokens
-- =============================================================================
CREATE TABLE fcm_tokens (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    business_id  UNIQUEIDENTIFIER NOT NULL,
    user_id      UNIQUEIDENTIFIER NOT NULL,
    token        NVARCHAR(500)    NOT NULL,
    created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_fcm_tokens_business FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE,
    CONSTRAINT FK_fcm_tokens_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE NO ACTION
)
GO

CREATE UNIQUE INDEX UQ_fcm_tokens_token ON fcm_tokens (token)
GO
