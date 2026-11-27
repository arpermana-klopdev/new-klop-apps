-- Read-only preflight for KLOP-PLATFORM-RBAC-1.0.
-- Targets the existing Development database only; never edits schema or data.
SET NOCOUNT ON;

IF @@SERVERNAME <> N'DEV-PC\SQLEXPRESS'
    THROW 52960, 'Expected the reviewed Development SQL Server.', 1;
IF DB_NAME() <> N'KlopPlatformDB'
    THROW 52961, 'Expected the existing KlopPlatformDB database.', 1;

IF OBJECT_ID(N'mst.RoleScopes', N'U') IS NULL
   OR OBJECT_ID(N'mst.Roles', N'U') IS NULL
   OR OBJECT_ID(N'mst.Permissions', N'U') IS NULL
   OR OBJECT_ID(N'mst.RolePermissions', N'U') IS NULL
   OR OBJECT_ID(N'iam.PlatformRoleAssignments', N'U') IS NULL
   OR OBJECT_ID(N'iam.TenantRoleAssignments', N'U') IS NULL
   OR OBJECT_ID(N'ten.Tenants', N'U') IS NULL
   OR OBJECT_ID(N'ten.TenantMemberships', N'U') IS NULL
   OR OBJECT_ID(N'mst.TenantTypes', N'U') IS NULL
   OR OBJECT_ID(N'iam.AuthSessions', N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents', N'U') IS NULL
    THROW 52962, 'An expected existing RBAC table is missing; stop for DBA review.', 1;

DECLARE @ExpectedRoles TABLE
(
    RoleId BIGINT NOT NULL PRIMARY KEY,
    RoleScopeId BIGINT NOT NULL,
    Code VARCHAR(50) NOT NULL,
    IsAssignable BIT NOT NULL
);
INSERT @ExpectedRoles(RoleId,RoleScopeId,Code,IsAssignable) VALUES
    (1,1,'SUPER_ADMIN',1),
    (2,1,'PLATFORM_SUPPORT',1),
    (3,2,'OWNER',1),
    (4,2,'ADMIN',1),
    (5,2,'MEMBER',1),
    (6,2,'VIEWER',0);

IF EXISTS
(
    SELECT 1
    FROM @ExpectedRoles expected
    LEFT JOIN mst.Roles role ON role.RoleId=expected.RoleId
    LEFT JOIN mst.RoleScopes scope ON scope.RoleScopeId=role.RoleScopeId
    WHERE role.RoleId IS NULL
       OR role.RoleScopeId<>expected.RoleScopeId
       OR role.Code<>expected.Code
       OR role.IsAssignable<>expected.IsAssignable
       OR role.IsActive<>1
       OR role.IsSystem<>1
       OR scope.IsActive<>1
       OR scope.Code<>CASE expected.RoleScopeId WHEN 1 THEN 'PLATFORM' ELSE 'TENANT' END
)
    THROW 52963, 'The six approved role records or scope assignments differ from the workbook.', 1;

IF (SELECT COUNT(*) FROM mst.RoleScopes WHERE RoleScopeId IN(1,2) AND IsActive=1)<>2
    THROW 52964, 'The approved PLATFORM and TENANT scopes are not both active.', 1;

SELECT role.RoleId,scope.Code AS ScopeCode,role.Code AS RoleCode,role.IsAssignable,role.IsActive,role.IsSystem,
       (SELECT COUNT(DISTINCT assignment.UserId)
        FROM iam.PlatformRoleAssignments assignment
        WHERE assignment.RoleId=role.RoleId) AS AssignedPlatformUsers,
       (SELECT COUNT(*) FROM mst.RolePermissions mapping WHERE mapping.RoleId=role.RoleId) AS PermissionMappings
FROM mst.Roles role
JOIN mst.RoleScopes scope ON scope.RoleScopeId=role.RoleScopeId
WHERE role.RoleId BETWEEN 1 AND 6
ORDER BY role.RoleId;

SELECT scope.Code AS ScopeCode,permission.Code AS PermissionCode,permission.IsActive,permission.IsSystem,
       COUNT(mapping.RoleId) AS MappingRows
FROM mst.Permissions permission
JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
LEFT JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
GROUP BY scope.Code,permission.Code,permission.IsActive,permission.IsSystem
ORDER BY scope.Code,permission.Code;

SELECT Code AS TenantTypeCode,IsActive,AllowMultipleMembers
FROM mst.TenantTypes
WHERE Code IN('PERSONAL','ORGANIZATION')
ORDER BY Code;

SELECT type.Code AS TenantTypeCode,role.Code AS RoleCode,COUNT(*) AS ActiveAssignments
FROM ten.Tenants tenant
JOIN mst.TenantTypes type ON type.TenantTypeId=tenant.TenantTypeId
JOIN ten.TenantMemberships membership ON membership.TenantId=tenant.TenantId
JOIN mst.MembershipStatuses membershipStatus
  ON membershipStatus.MembershipStatusId=membership.MembershipStatusId
 AND membershipStatus.Code='ACTIVE'
 AND membershipStatus.IsActive=1
JOIN iam.TenantRoleAssignments assignment ON assignment.MembershipId=membership.MembershipId
JOIN mst.Roles role ON role.RoleId=assignment.RoleId
WHERE role.Code='OWNER'
GROUP BY type.Code,role.Code
ORDER BY type.Code;

SELECT COUNT(*) AS TenantsWithMultipleActiveOwners
FROM
(
    SELECT membership.TenantId
    FROM ten.TenantMemberships membership
    JOIN mst.MembershipStatuses status
      ON status.MembershipStatusId=membership.MembershipStatusId
     AND status.Code='ACTIVE'
     AND status.IsActive=1
    JOIN iam.TenantRoleAssignments assignment ON assignment.MembershipId=membership.MembershipId
    JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.Code='OWNER'
    GROUP BY membership.TenantId
    HAVING COUNT(*)>1
) ownerCounts;

SELECT schemaInfo.name AS SchemaName,procedureInfo.name AS ProcedureName
FROM sys.procedures procedureInfo
JOIN sys.schemas schemaInfo ON schemaInfo.schema_id=procedureInfo.schema_id
WHERE (schemaInfo.name='iam' AND procedureInfo.name IN
       ('usp_ValidateSessionAccess','usp_ValidatePlatformPermission','usp_GetPlatformPermissions'))
   OR (schemaInfo.name='reg' AND procedureInfo.name IN
       ('usp_GetPlatformRegistrationSummary','usp_ListPlatformRegistrations',
        'usp_GetPlatformRegistration','usp_GetPlatformRegistrationTimeline'))
ORDER BY schemaInfo.name,procedureInfo.name;

SELECT CASE WHEN EXISTS
(
    SELECT 1 FROM sys.tables
    WHERE name LIKE '%Migration%' OR name LIKE '%SchemaVersion%' OR name LIKE '%DeploymentHistory%'
) THEN N'LEDGER TABLE FOUND - REVIEW REQUIRED'
  ELSE N'NO MIGRATION LEDGER TABLE FOUND' END AS MigrationProvenance;
GO
