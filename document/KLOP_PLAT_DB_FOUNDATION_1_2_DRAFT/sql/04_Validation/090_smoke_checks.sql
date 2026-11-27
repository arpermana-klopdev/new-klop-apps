SET NOCOUNT ON;
GO
-- Run in a non-production Development database AFTER all prior scripts.
IF OBJECT_ID(N'iam.Users',N'U') IS NULL OR OBJECT_ID(N'ten.Tenants',N'U') IS NULL
   OR OBJECT_ID(N'ten.TenantMemberships',N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
   OR OBJECT_ID(N'aud.SecurityEvents',N'U') IS NULL
   OR OBJECT_ID(N'aud.BusinessEvents',N'U') IS NULL
   THROW 51002, 'v1.2 critical operational tables missing.', 1;
GO
IF (SELECT COUNT(*) FROM mst.VerificationPurposes WHERE Code IN ('EMAIL_CONFIRMATION','PASSWORD_RESET')) <> 2
   THROW 51003, 'v1.2 verification purpose seed missing.', 1;
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID(N'iam.RefreshTokens') AND name=N'UX_RefreshTokens_TokenHash'
) THROW 51004, 'Refresh token uniqueness index missing.', 1;
GO
-- THIS IS NOT A SQL SERVER INTEGRATION TEST. Manual transactional/security tests remain mandatory.
PRINT 'Structural smoke checks passed. Security invariants and audited write SPs remain DRAFT/NOT IMPLEMENTED.';
GO
