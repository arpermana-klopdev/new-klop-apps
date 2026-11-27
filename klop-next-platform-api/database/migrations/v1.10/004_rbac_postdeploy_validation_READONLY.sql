-- Read-only post-deployment checks. Does not test an authenticated API session.
SET NOCOUNT ON;

IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS' OR DB_NAME()<>N'KlopPlatformDB'
    THROW 52990, 'This report is restricted to the reviewed Development database.', 1;

SELECT permission.Code AS PermissionCode,scope.Code AS ScopeCode,
       permission.IsActive,permission.IsSystem,COUNT(mapping.RoleId) AS RoleMappingCount
FROM mst.Permissions permission
JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
LEFT JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
WHERE permission.Code='platform.registrations.read'
GROUP BY permission.Code,scope.Code,permission.IsActive,permission.IsSystem;

SELECT role.Code AS RoleCode,COUNT(permission.PermissionId) AS RegistrationReadMappingCount
FROM mst.Roles role
LEFT JOIN mst.RolePermissions mapping ON mapping.RoleId=role.RoleId
LEFT JOIN mst.Permissions permission
  ON permission.PermissionId=mapping.PermissionId
 AND permission.Code='platform.registrations.read'
WHERE role.Code IN('SUPER_ADMIN','PLATFORM_SUPPORT','OWNER','ADMIN','MEMBER','VIEWER')
GROUP BY role.Code
ORDER BY role.Code;

IF NOT EXISTS
(
    SELECT 1 FROM mst.Permissions permission
    JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
    WHERE permission.Code='platform.registrations.read'
      AND scope.Code='PLATFORM' AND permission.IsActive=1 AND permission.IsSystem=1
)
    THROW 52991, 'Registration permission master validation failed.', 1;

IF EXISTS
(
    SELECT role.Code
    FROM mst.Roles role
    LEFT JOIN mst.RolePermissions mapping ON mapping.RoleId=role.RoleId
    LEFT JOIN mst.Permissions permission
      ON permission.PermissionId=mapping.PermissionId
     AND permission.Code='platform.registrations.read'
    WHERE role.Code IN('SUPER_ADMIN','PLATFORM_SUPPORT')
    GROUP BY role.Code
    HAVING COUNT(permission.PermissionId)<>1
)
    THROW 52992, 'An approved platform role is missing its exact registration permission mapping.', 1;

IF EXISTS
(
    SELECT 1
    FROM mst.RolePermissions mapping
    JOIN mst.Permissions permission ON permission.PermissionId=mapping.PermissionId
    JOIN mst.Roles role ON role.RoleId=mapping.RoleId
    WHERE permission.Code='platform.registrations.read'
      AND role.Code NOT IN('SUPER_ADMIN','PLATFORM_SUPPORT')
)
    THROW 52993, 'Registration permission is mapped outside the approved roles.', 1;

IF OBJECT_ID(N'iam.usp_ValidateSessionAccess',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_GetTenantPermissions',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_AssignTenantRole',N'P') IS NULL
    THROW 52994, 'One or more v1.10 authorization procedures are missing.', 1;

IF OBJECT_ID(N'iam.usp_GetUnifiedRolePermissionMatrix',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_SaveRolePermissionBatch',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_GetRolePermissionChangeHistory',N'P') IS NULL
   OR OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NULL
   OR OBJECT_ID(N'mst.AccountSelfServicePolicies',N'U') IS NULL
    THROW 52997, 'Unified matrix database objects are missing.', 1;

IF EXISTS(SELECT 1 FROM mst.RoleScopes WHERE Code='ACCOUNT')
    THROW 52998, 'Account self-service must remain outside the role-scope hierarchy.', 1;
IF (SELECT COUNT(*) FROM mst.AccountSelfServicePolicies WHERE IsActive=1)<>16
    THROW 52999, 'The account self-service policy catalog does not match the reconciled source rows.', 1;
IF EXISTS
(
    SELECT 1
    FROM mst.AccountSelfServicePolicies policy
    JOIN mst.Permissions permission ON permission.Code=policy.PolicyCode
)
    THROW 52999, 'Read-only account policy identifiers must not exist in the grantable permission master.', 1;
IF EXISTS
(
    SELECT 1
    FROM mst.RolePermissions mapping
    JOIN mst.Permissions permission ON permission.PermissionId=mapping.PermissionId
    JOIN mst.Roles role ON role.RoleId=mapping.RoleId
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
    JOIN mst.RoleScopes permissionScope ON permissionScope.RoleScopeId=permission.RoleScopeId
    WHERE roleScope.Code<>permissionScope.Code
       OR roleScope.Code NOT IN('PLATFORM','TENANT')
       OR (roleScope.Code='PLATFORM' AND mapping.TenantTypeId IS NOT NULL)
       OR (roleScope.Code='TENANT' AND mapping.TenantTypeId IS NULL)
)
    THROW 52999, 'A role-permission mapping has an invalid scope or tenant-type context.', 1;

IF EXISTS
(
    SELECT permission.Code
    FROM mst.Permissions permission
    JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
    LEFT JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
    LEFT JOIN mst.Roles role
      ON role.RoleId=mapping.RoleId
     AND role.Code='SUPER_ADMIN'
     AND role.RoleScopeId=scope.RoleScopeId
    WHERE permission.Code IN('platform.role_permissions.read','platform.role_permissions.update')
    GROUP BY permission.Code
    HAVING COUNT(role.RoleId)<>1
)
OR EXISTS
(
    SELECT 1
    FROM mst.RolePermissions mapping
    JOIN mst.Permissions permission ON permission.PermissionId=mapping.PermissionId
    JOIN mst.Roles role ON role.RoleId=mapping.RoleId
    WHERE permission.Code IN('platform.role_permissions.read','platform.role_permissions.update')
      AND role.Code<>'SUPER_ADMIN'
)
    THROW 52999, 'Matrix read/update permissions must be assigned only to SUPER_ADMIN.', 1;

IF OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P') IS NULL
   OR ISNULL(CHARINDEX('platform.registrations.read',
       OBJECT_DEFINITION(OBJECT_ID(N'iam.usp_ValidatePlatformPermission'))),0) = 0
    THROW 52995, 'The platform permission validator does not include registration read.', 1;
IF OBJECT_ID(N'iam.usp_GetPlatformPermissions',N'P') IS NULL
   OR ISNULL(CHARINDEX('platform.registrations.read',
       OBJECT_DEFINITION(OBJECT_ID(N'iam.usp_GetPlatformPermissions'))),0) = 0
    THROW 52996, 'Platform permission discovery does not include registration read.', 1;

SELECT type.Code AS TenantTypeCode,type.AllowMultipleMembers,
       status.Code AS TenantStatusCode,COUNT(*) AS TenantCount
FROM ten.Tenants tenant
JOIN mst.TenantTypes type ON type.TenantTypeId=tenant.TenantTypeId
JOIN mst.TenantStatuses status ON status.TenantStatusId=tenant.TenantStatusId
GROUP BY type.Code,type.AllowMultipleMembers,status.Code
ORDER BY type.Code,status.Code;

SELECT N'REGISTRATION_COUNTS' AS ReportSection,status.Code AS OnboardingStatusCode,
       CASE WHEN usr.EmailVerifiedAtUtc IS NULL THEN N'EMAIL_PENDING' ELSE N'VERIFIED' END AS EmailState,
       tenantType.Code AS TenantTypeCode,COUNT(*) AS ApplicationCount
FROM reg.RegistrationApplications application
JOIN mst.OnboardingStatuses status
  ON status.OnboardingStatusId=application.OnboardingStatusId
JOIN iam.Users usr ON usr.UserId=application.UserId
JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=application.TenantTypeId
GROUP BY status.Code,
         CASE WHEN usr.EmailVerifiedAtUtc IS NULL THEN N'EMAIL_PENDING' ELSE N'VERIFIED' END,
         tenantType.Code
ORDER BY status.Code,EmailState,tenantType.Code;

SELECT N'POSTDEPLOY DATABASE CHECKS PASSED' AS ValidationStatus,
       N'Authenticated role behavior and runtime identity require separate manual validation.' AS Limitation;
GO
