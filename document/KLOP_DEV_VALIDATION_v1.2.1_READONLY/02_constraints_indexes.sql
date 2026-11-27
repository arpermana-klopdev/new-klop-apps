-- KLOP DEVELOPMENT - READ-ONLY VALIDATION
-- Based on original v1.1, v1.2 and v1.2.1 artifacts.
-- READ-ONLY: no INSERT / UPDATE / DELETE / CREATE / ALTER / DROP on user objects, no stored procedure invocation.
-- Run via SSMS or sqlcmd, against the intended DEVELOPMENT database, with metadata/read privileges.
-- IMPORTANT: output is evidence only when executed and saved from the actual SQL Server.
SET NOCOUNT ON;
GO
-- Expected foreign keys (7 v1.1 + 39 v1.2); enabled AND trusted required.
;WITH E(SchemaName,TableName,ConstraintName,IntroducedIn) AS (
    SELECT V.SchemaName,V.TableName,V.ConstraintName,V.IntroducedIn FROM (VALUES
    (N'mst', N'OrganizationIdentityRequirementGroups', N'FK_ReqGroup_OrgType', N'v1.1'),
    (N'mst', N'OrganizationIdentityRequirements', N'FK_Requirement_Group', N'v1.1'),
    (N'mst', N'OrganizationIdentityRequirements', N'FK_Requirement_DocumentType', N'v1.1'),
    (N'mst', N'Roles', N'FK_Roles_Scope', N'v1.1'),
    (N'mst', N'Permissions', N'FK_Permissions_Scope', N'v1.1'),
    (N'mst', N'RolePermissions', N'FK_RolePermissions_Role', N'v1.1'),
    (N'mst', N'RolePermissions', N'FK_RolePermissions_Permission', N'v1.1'),
    (N'iam', N'UserCredentials', N'FK_iam_UserCredentials_UserId', N'v1.2'),
    (N'iam', N'ExternalIdentities', N'FK_iam_ExternalIdentities_UserId', N'v1.2'),
    (N'iam', N'ExternalIdentities', N'FK_iam_ExternalIdentities_IdentityProviderId', N'v1.2'),
    (N'iam', N'VerificationChallenges', N'FK_iam_VerificationChallenges_UserId', N'v1.2'),
    (N'iam', N'VerificationChallenges', N'FK_iam_VerificationChallenges_VerificationPurposeId', N'v1.2'),
    (N'ten', N'Tenants', N'FK_ten_Tenants_TenantTypeId', N'v1.2'),
    (N'ten', N'Tenants', N'FK_ten_Tenants_TenantStatusId', N'v1.2'),
    (N'ten', N'Tenants', N'FK_ten_Tenants_CreatedByUserId', N'v1.2'),
    (N'ten', N'Tenants', N'FK_ten_Tenants_UpdatedByUserId', N'v1.2'),
    (N'ten', N'Organizations', N'FK_ten_Organizations_TenantId', N'v1.2'),
    (N'ten', N'Organizations', N'FK_ten_Organizations_OrganizationTypeId', N'v1.2'),
    (N'ten', N'Organizations', N'FK_ten_Organizations_VerificationStatusId', N'v1.2'),
    (N'ten', N'Organizations', N'FK_ten_Organizations_VerifiedByUserId', N'v1.2'),
    (N'ten', N'TenantMemberships', N'FK_ten_TenantMemberships_TenantId', N'v1.2'),
    (N'ten', N'TenantMemberships', N'FK_ten_TenantMemberships_UserId', N'v1.2'),
    (N'ten', N'TenantMemberships', N'FK_ten_TenantMemberships_MembershipStatusId', N'v1.2'),
    (N'ten', N'TenantMemberships', N'FK_ten_TenantMemberships_CreatedByUserId', N'v1.2'),
    (N'ten', N'TenantMemberships', N'FK_ten_TenantMemberships_UpdatedByUserId', N'v1.2'),
    (N'iam', N'PlatformRoleAssignments', N'FK_iam_PlatformRoleAssignments_UserId', N'v1.2'),
    (N'iam', N'PlatformRoleAssignments', N'FK_iam_PlatformRoleAssignments_RoleId', N'v1.2'),
    (N'iam', N'PlatformRoleAssignments', N'FK_iam_PlatformRoleAssignments_AssignedByUserId', N'v1.2'),
    (N'iam', N'TenantRoleAssignments', N'FK_iam_TenantRoleAssignments_MembershipId', N'v1.2'),
    (N'iam', N'TenantRoleAssignments', N'FK_iam_TenantRoleAssignments_RoleId', N'v1.2'),
    (N'iam', N'TenantRoleAssignments', N'FK_iam_TenantRoleAssignments_AssignedByUserId', N'v1.2'),
    (N'iam', N'AuthSessions', N'FK_iam_AuthSessions_UserId', N'v1.2'),
    (N'iam', N'AuthSessions', N'FK_iam_AuthSessions_TenantId', N'v1.2'),
    (N'iam', N'RefreshTokens', N'FK_iam_RefreshTokens_AuthSessionId', N'v1.2'),
    (N'iam', N'RefreshTokens', N'FK_iam_RefreshTokens_PreviousTokenId', N'v1.2'),
    (N'aud', N'AuditEvents', N'FK_aud_AuditEvents_TenantId', N'v1.2'),
    (N'aud', N'AuditEvents', N'FK_aud_AuditEvents_ActorUserId', N'v1.2'),
    (N'aud', N'AuditEvents', N'FK_aud_AuditEvents_AuditActionTypeId', N'v1.2'),
    (N'aud', N'AuditEvents', N'FK_aud_AuditEvents_AuditResultTypeId', N'v1.2'),
    (N'aud', N'SecurityEvents', N'FK_aud_SecurityEvents_TenantId', N'v1.2'),
    (N'aud', N'SecurityEvents', N'FK_aud_SecurityEvents_ActorUserId', N'v1.2'),
    (N'aud', N'SecurityEvents', N'FK_aud_SecurityEvents_SubjectUserId', N'v1.2'),
    (N'aud', N'SecurityEvents', N'FK_aud_SecurityEvents_SecurityEventTypeId', N'v1.2'),
    (N'aud', N'BusinessEvents', N'FK_aud_BusinessEvents_TenantId', N'v1.2'),
    (N'aud', N'BusinessEvents', N'FK_aud_BusinessEvents_ActorUserId', N'v1.2'),
    (N'aud', N'BusinessEvents', N'FK_aud_BusinessEvents_BusinessEventTypeId', N'v1.2')
    ) AS V(SchemaName,TableName,ConstraintName,IntroducedIn)
)
SELECT E.IntroducedIn,N'FOREIGN_KEY' AS ObjectType,E.SchemaName,E.TableName,E.ConstraintName,
 CASE WHEN FK.object_id IS NULL THEN N'FAIL_MISSING'
      WHEN FK.is_disabled=1 THEN N'FAIL_DISABLED'
      WHEN FK.is_not_trusted=1 THEN N'FAIL_UNTRUSTED'
      ELSE N'PASS' END AS CheckResult
FROM E LEFT JOIN sys.schemas S ON S.name=E.SchemaName
       LEFT JOIN sys.tables T ON T.schema_id=S.schema_id AND T.name=E.TableName
       LEFT JOIN sys.foreign_keys FK ON FK.parent_object_id=T.object_id AND FK.name=E.ConstraintName
ORDER BY E.IntroducedIn,E.SchemaName,E.TableName,E.ConstraintName;
GO
-- Expected secondary indexes from v1.2, including uniqueness where specified.
;WITH E(SchemaName,TableName,IndexName,ExpectedUniqueness) AS (
    SELECT V.SchemaName,V.TableName,V.IndexName,V.ExpectedUniqueness FROM (VALUES
    (N'mst', N'IdentityProviders', N'UX_IdentityProviders_Code', N'UNIQUE'),
    (N'mst', N'VerificationPurposes', N'UX_VerificationPurposes_Code', N'UNIQUE'),
    (N'mst', N'BusinessEventTypes', N'UX_BusinessEventTypes_Code', N'UNIQUE'),
    (N'iam', N'Users', N'UX_Users_PublicUserId', N'UNIQUE'),
    (N'iam', N'Users', N'UX_Users_NormalizedEmail', N'UNIQUE'),
    (N'iam', N'UserCredentials', N'UX_UserCredentials_UserId', N'UNIQUE'),
    (N'iam', N'ExternalIdentities', N'UX_ExternalIdentities_ProviderIssuerSubject', N'UNIQUE'),
    (N'iam', N'ExternalIdentities', N'IX_ExternalIdentities_UserId', N'NONUNIQUE'),
    (N'iam', N'VerificationChallenges', N'UX_VerificationChallenges_TokenHash', N'UNIQUE'),
    (N'iam', N'VerificationChallenges', N'IX_VerificationChallenges_UserPurposeExpiry', N'NONUNIQUE'),
    (N'ten', N'Tenants', N'UX_Tenants_PublicTenantId', N'UNIQUE'),
    (N'ten', N'Tenants', N'UX_Tenants_TenantCode', N'UNIQUE'),
    (N'ten', N'Tenants', N'IX_Tenants_StatusType', N'NONUNIQUE'),
    (N'ten', N'Organizations', N'IX_Organizations_TypeStatus', N'NONUNIQUE'),
    (N'ten', N'TenantMemberships', N'UX_Memberships_TenantUser', N'UNIQUE'),
    (N'ten', N'TenantMemberships', N'IX_Memberships_UserStatus', N'NONUNIQUE'),
    (N'iam', N'PlatformRoleAssignments', N'UX_PlatformRoles_UserRole', N'UNIQUE'),
    (N'iam', N'TenantRoleAssignments', N'UX_TenantRoles_MembershipRole', N'UNIQUE'),
    (N'iam', N'TenantRoleAssignments', N'IX_TenantRoles_RoleId', N'NONUNIQUE'),
    (N'iam', N'AuthSessions', N'UX_AuthSessions_PublicSessionId', N'UNIQUE'),
    (N'iam', N'AuthSessions', N'IX_AuthSessions_UserActive', N'NONUNIQUE'),
    (N'iam', N'RefreshTokens', N'UX_RefreshTokens_TokenHash', N'UNIQUE'),
    (N'iam', N'RefreshTokens', N'UX_RefreshTokens_PreviousToken', N'UNIQUE'),
    (N'iam', N'RefreshTokens', N'IX_RefreshTokens_SessionExpiry', N'NONUNIQUE'),
    (N'aud', N'AuditEvents', N'IX_AuditEvents_TenantTime', N'NONUNIQUE'),
    (N'aud', N'AuditEvents', N'IX_AuditEvents_Correlation', N'NONUNIQUE'),
    (N'aud', N'SecurityEvents', N'IX_SecurityEvents_TenantTime', N'NONUNIQUE'),
    (N'aud', N'SecurityEvents', N'IX_SecurityEvents_SubjectTime', N'NONUNIQUE'),
    (N'aud', N'BusinessEvents', N'IX_BusinessEvents_TenantTime', N'NONUNIQUE'),
    (N'aud', N'BusinessEvents', N'IX_BusinessEvents_Target', N'NONUNIQUE')
    ) AS V(SchemaName,TableName,IndexName,ExpectedUniqueness)
)
SELECT N'INDEX' AS ObjectType,E.SchemaName,E.TableName,E.IndexName,E.ExpectedUniqueness,
 CASE WHEN I.index_id IS NULL THEN N'FAIL_MISSING'
      WHEN I.is_disabled=1 THEN N'FAIL_DISABLED'
      WHEN E.ExpectedUniqueness=N'UNIQUE' AND I.is_unique<>1 THEN N'FAIL_NOT_UNIQUE'
      ELSE N'PASS' END AS CheckResult
FROM E LEFT JOIN sys.schemas S ON S.name=E.SchemaName
       LEFT JOIN sys.tables T ON T.schema_id=S.schema_id AND T.name=E.TableName
       LEFT JOIN sys.indexes I ON I.object_id=T.object_id AND I.name=E.IndexName
ORDER BY E.SchemaName,E.TableName,E.IndexName;
GO
-- Expected CHECK constraints from v1.2; enabled AND trusted required.
;WITH E(SchemaName,TableName,ConstraintName) AS (
    SELECT V.SchemaName,V.TableName,V.ConstraintName FROM (VALUES
    (N'iam', N'UserCredentials', N'CK_UserCredentials_FailedLoginCount'),
    (N'iam', N'VerificationChallenges', N'CK_VerificationChallenges_Expiry'),
    (N'ten', N'TenantMemberships', N'CK_TenantMemberships_Period'),
    (N'iam', N'AuthSessions', N'CK_AuthSessions_Expiry'),
    (N'iam', N'RefreshTokens', N'CK_RefreshTokens_Expiry'),
    (N'aud', N'AuditEvents', N'CK_AuditEvents_Actor'),
    (N'aud', N'AuditEvents', N'CK_AuditEvents_Json'),
    (N'aud', N'SecurityEvents', N'CK_SecurityEvents_Severity'),
    (N'aud', N'SecurityEvents', N'CK_SecurityEvents_Json'),
    (N'aud', N'BusinessEvents', N'CK_BusinessEvents_Json')
    ) AS V(SchemaName,TableName,ConstraintName)
)
SELECT N'CHECK_CONSTRAINT' AS ObjectType,E.SchemaName,E.TableName,E.ConstraintName,
 CASE WHEN C.object_id IS NULL THEN N'FAIL_MISSING'
      WHEN C.is_disabled=1 THEN N'FAIL_DISABLED'
      WHEN C.is_not_trusted=1 THEN N'FAIL_UNTRUSTED'
      ELSE N'PASS' END AS CheckResult
FROM E LEFT JOIN sys.schemas S ON S.name=E.SchemaName
       LEFT JOIN sys.tables T ON T.schema_id=S.schema_id AND T.name=E.TableName
       LEFT JOIN sys.check_constraints C ON C.parent_object_id=T.object_id AND C.name=E.ConstraintName
ORDER BY E.SchemaName,E.TableName,E.ConstraintName;
GO
