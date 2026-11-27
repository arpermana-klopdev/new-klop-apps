-- KLOP DEVELOPMENT - READ-ONLY VALIDATION
-- Based on original v1.1, v1.2 and v1.2.1 artifacts.
-- READ-ONLY: no INSERT / UPDATE / DELETE / CREATE / ALTER / DROP on user objects, no stored procedure invocation.
-- Run via SSMS or sqlcmd, against the intended DEVELOPMENT database, with metadata/read privileges.
-- IMPORTANT: output is evidence only when executed and saved from the actual SQL Server.
SET NOCOUNT ON;
GO
-- Expected physical tables (16 v1.1 + 17 v1.2)
;WITH E(SchemaName,ObjectName,IntroducedIn) AS (
    SELECT V.SchemaName,V.ObjectName,V.IntroducedIn FROM (VALUES
    (N'cfg', N'SystemConfigurations', N'v1.1'),
    (N'mst', N'AuditActionTypes', N'v1.1'),
    (N'mst', N'AuditResultTypes', N'v1.1'),
    (N'mst', N'IdentityDocumentTypes', N'v1.1'),
    (N'mst', N'MembershipStatuses', N'v1.1'),
    (N'mst', N'OrganizationIdentityRequirementGroups', N'v1.1'),
    (N'mst', N'OrganizationIdentityRequirements', N'v1.1'),
    (N'mst', N'OrganizationTypes', N'v1.1'),
    (N'mst', N'Permissions', N'v1.1'),
    (N'mst', N'RolePermissions', N'v1.1'),
    (N'mst', N'RoleScopes', N'v1.1'),
    (N'mst', N'Roles', N'v1.1'),
    (N'mst', N'SecurityEventTypes', N'v1.1'),
    (N'mst', N'TenantStatuses', N'v1.1'),
    (N'mst', N'TenantTypes', N'v1.1'),
    (N'mst', N'VerificationStatuses', N'v1.1'),
    (N'aud', N'AuditEvents', N'v1.2'),
    (N'aud', N'BusinessEvents', N'v1.2'),
    (N'aud', N'SecurityEvents', N'v1.2'),
    (N'iam', N'AuthSessions', N'v1.2'),
    (N'iam', N'ExternalIdentities', N'v1.2'),
    (N'iam', N'PlatformRoleAssignments', N'v1.2'),
    (N'iam', N'RefreshTokens', N'v1.2'),
    (N'iam', N'TenantRoleAssignments', N'v1.2'),
    (N'iam', N'UserCredentials', N'v1.2'),
    (N'iam', N'Users', N'v1.2'),
    (N'iam', N'VerificationChallenges', N'v1.2'),
    (N'mst', N'BusinessEventTypes', N'v1.2'),
    (N'mst', N'IdentityProviders', N'v1.2'),
    (N'mst', N'VerificationPurposes', N'v1.2'),
    (N'ten', N'Organizations', N'v1.2'),
    (N'ten', N'TenantMemberships', N'v1.2'),
    (N'ten', N'Tenants', N'v1.2')
    ) AS V(SchemaName,ObjectName,IntroducedIn)
)
SELECT E.IntroducedIn, N'TABLE' AS ObjectType, E.SchemaName, E.ObjectName,
 CASE WHEN T.object_id IS NULL THEN N'FAIL_MISSING' ELSE N'PASS' END AS CheckResult,
 T.create_date AS CreatedAt, T.modify_date AS ModifiedAt
FROM E LEFT JOIN sys.schemas S ON S.name=E.SchemaName
       LEFT JOIN sys.tables T ON T.schema_id=S.schema_id AND T.name=E.ObjectName
ORDER BY E.IntroducedIn, E.SchemaName, E.ObjectName;
GO
-- Expected procedures (16 v1.1 + 8 v1.2.1)
;WITH E(SchemaName,ObjectName,IntroducedIn) AS (
    SELECT V.SchemaName,V.ObjectName,V.IntroducedIn FROM (VALUES
    (N'cfg', N'usp_Configuration_GetAll', N'v1.1'),
    (N'cfg', N'usp_Configuration_GetByKey', N'v1.1'),
    (N'mst', N'usp_AuditActionType_GetAll', N'v1.1'),
    (N'mst', N'usp_AuditResultType_GetAll', N'v1.1'),
    (N'mst', N'usp_IdentityDocumentType_GetAll', N'v1.1'),
    (N'mst', N'usp_MembershipStatuse_GetAll', N'v1.1'),
    (N'mst', N'usp_OrganizationIdentityRequirementGroup_GetAll', N'v1.1'),
    (N'mst', N'usp_OrganizationIdentityRequirement_GetByOrganizationType', N'v1.1'),
    (N'mst', N'usp_OrganizationType_GetAll', N'v1.1'),
    (N'mst', N'usp_Permission_GetAll', N'v1.1'),
    (N'mst', N'usp_RoleScope_GetAll', N'v1.1'),
    (N'mst', N'usp_Role_GetAll', N'v1.1'),
    (N'mst', N'usp_SecurityEventType_GetAll', N'v1.1'),
    (N'mst', N'usp_TenantStatuse_GetAll', N'v1.1'),
    (N'mst', N'usp_TenantType_GetAll', N'v1.1'),
    (N'mst', N'usp_VerificationStatuse_GetAll', N'v1.1'),
    (N'iam', N'usp_AssignTenantRole', N'v1.2.1'),
    (N'iam', N'usp_ConfirmEmail', N'v1.2.1'),
    (N'iam', N'usp_RegisterLocalUser', N'v1.2.1'),
    (N'iam', N'usp_RevokeTenantRole', N'v1.2.1'),
    (N'ten', N'usp_AcceptMembership', N'v1.2.1'),
    (N'ten', N'usp_CreateTenantWithOwner', N'v1.2.1'),
    (N'ten', N'usp_InviteExistingUser', N'v1.2.1'),
    (N'ten', N'usp_RemoveTenantMember', N'v1.2.1')
    ) AS V(SchemaName,ObjectName,IntroducedIn)
)
SELECT E.IntroducedIn, N'PROCEDURE' AS ObjectType, E.SchemaName, E.ObjectName,
 CASE WHEN P.object_id IS NULL THEN N'FAIL_MISSING' ELSE N'PASS' END AS CheckResult,
 P.create_date AS CreatedAt, P.modify_date AS ModifiedAt
FROM E LEFT JOIN sys.schemas S ON S.name=E.SchemaName
       LEFT JOIN sys.procedures P ON P.schema_id=S.schema_id AND P.name=E.ObjectName
ORDER BY E.IntroducedIn, E.SchemaName,E.ObjectName;
GO
