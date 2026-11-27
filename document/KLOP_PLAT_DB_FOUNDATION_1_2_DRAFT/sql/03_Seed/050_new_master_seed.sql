SET NOCOUNT ON;
GO
-- New v1.2 master seed proposals: codes remain stable; no changes to v1.1 master rows.
IF NOT EXISTS (SELECT 1 FROM mst.IdentityProviders WHERE [Code] = 'AZURE_ENTRA')
BEGIN
    INSERT INTO mst.IdentityProviders ([Code],[Name],[Description],[IsActive],[IsSystem])
    VALUES ('AZURE_ENTRA', N'Microsoft Entra ID', N'v1.2 DRAFT foundation seed', 1, 1);
END;
GO
IF NOT EXISTS (SELECT 1 FROM mst.VerificationPurposes WHERE [Code] = 'EMAIL_CONFIRMATION')
BEGIN
    INSERT INTO mst.VerificationPurposes ([Code],[Name],[Description],[IsActive],[IsSystem])
    VALUES ('EMAIL_CONFIRMATION', N'Email Confirmation', N'v1.2 DRAFT foundation seed', 1, 1);
END;
GO
IF NOT EXISTS (SELECT 1 FROM mst.VerificationPurposes WHERE [Code] = 'PASSWORD_RESET')
BEGIN
    INSERT INTO mst.VerificationPurposes ([Code],[Name],[Description],[IsActive],[IsSystem])
    VALUES ('PASSWORD_RESET', N'Password Reset', N'v1.2 DRAFT foundation seed', 1, 1);
END;
GO
IF NOT EXISTS (SELECT 1 FROM mst.BusinessEventTypes WHERE [Code] = 'TENANT_CREATED')
BEGIN
    INSERT INTO mst.BusinessEventTypes ([Code],[Name],[Description],[IsActive],[IsSystem])
    VALUES ('TENANT_CREATED', N'Tenant Created', N'v1.2 DRAFT foundation seed', 1, 1);
END;
GO
IF NOT EXISTS (SELECT 1 FROM mst.BusinessEventTypes WHERE [Code] = 'MEMBERSHIP_CHANGED')
BEGIN
    INSERT INTO mst.BusinessEventTypes ([Code],[Name],[Description],[IsActive],[IsSystem])
    VALUES ('MEMBERSHIP_CHANGED', N'Membership Changed', N'v1.2 DRAFT foundation seed', 1, 1);
END;
GO
IF NOT EXISTS (SELECT 1 FROM mst.BusinessEventTypes WHERE [Code] = 'ORGANIZATION_VERIFICATION_CHANGED')
BEGIN
    INSERT INTO mst.BusinessEventTypes ([Code],[Name],[Description],[IsActive],[IsSystem])
    VALUES ('ORGANIZATION_VERIFICATION_CHANGED', N'Organization Verification Changed', N'v1.2 DRAFT foundation seed', 1, 1);
END;
GO
