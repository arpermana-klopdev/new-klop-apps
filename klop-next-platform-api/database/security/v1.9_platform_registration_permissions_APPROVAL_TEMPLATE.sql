:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- REVIEW ONLY. Adds one least-privilege read permission to the existing platform
-- SUPER_ADMIN and PLATFORM_SUPPORT roles. No users, roles, or runtime SQL grants are changed.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Environment NVARCHAR(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase SYSNAME=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52930, 'Refused: Development environment and reviewed server are required.', 1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
    THROW 52931, 'Refused: this approval template is restricted to KlopPlatformDB.', 1;

DECLARE @PlatformScopeId BIGINT=
    (SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1);
DECLARE @SuperAdminRoleId BIGINT=
    (SELECT role.RoleId FROM mst.Roles role
     JOIN mst.RoleScopes scope ON scope.RoleScopeId=role.RoleScopeId
     WHERE role.Code='SUPER_ADMIN' AND scope.Code='PLATFORM' AND role.IsActive=1);
DECLARE @PlatformSupportRoleId BIGINT=
    (SELECT role.RoleId FROM mst.Roles role
     JOIN mst.RoleScopes scope ON scope.RoleScopeId=role.RoleScopeId
     WHERE role.Code='PLATFORM_SUPPORT' AND scope.Code='PLATFORM' AND role.IsActive=1);
IF @PlatformScopeId IS NULL OR @SuperAdminRoleId IS NULL OR @PlatformSupportRoleId IS NULL
    THROW 52932, 'The existing PLATFORM scope, SUPER_ADMIN, or PLATFORM_SUPPORT role is unavailable.', 1;
IF EXISTS
(
    SELECT 1 FROM mst.Permissions permission
    WHERE permission.Code='platform.registrations.read'
      AND (permission.RoleScopeId<>@PlatformScopeId OR permission.IsActive<>1 OR permission.IsSystem<>1)
)
    THROW 52933, 'The registration permission exists with incompatible scope or security metadata.', 1;

DECLARE @PermissionId BIGINT=
    (SELECT PermissionId FROM mst.Permissions
     WHERE RoleScopeId=@PlatformScopeId AND Code='platform.registrations.read' AND IsActive=1);
SELECT N'PERMISSION_PLAN' AS Section,
       N'platform.registrations.read' AS PermissionCode,
       CASE WHEN @PermissionId IS NULL THEN N'WOULD CREATE' ELSE N'PRESERVE EXISTING' END AS PermissionAction;
SELECT N'ROLE_PERMISSION_PLAN' AS Section,role.Code AS RoleCode,
       CASE WHEN rolePermission.RoleId IS NULL THEN N'WOULD ASSIGN READ' ELSE N'PRESERVE EXISTING' END AS PlannedAction
FROM (VALUES(@SuperAdminRoleId,N'SUPER_ADMIN'),(@PlatformSupportRoleId,N'PLATFORM_SUPPORT')) roles(RoleId,Code)
JOIN mst.Roles role ON role.RoleId=roles.RoleId
LEFT JOIN mst.RolePermissions rolePermission
    ON rolePermission.RoleId=role.RoleId AND rolePermission.PermissionId=@PermissionId
ORDER BY role.Code;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
    SELECT N'DRY RUN - NO CHANGES' AS Status,
           N'Explicit DBA approval and ticket are required before applying permission and role assignments.' AS NextStep;
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;
    IF @PermissionId IS NULL
    BEGIN
        INSERT mst.Permissions
            (RoleScopeId,Code,Name,Description,SortOrder,IsActive,IsSystem,CreatedAtUtc)
        VALUES
            (@PlatformScopeId,'platform.registrations.read',N'Read platform registrations',
             N'Read registration summaries, applications, profile details, and persisted timelines.',
             730,1,1,SYSUTCDATETIME());
        SET @PermissionId=CONVERT(BIGINT,SCOPE_IDENTITY());
    END;

    INSERT mst.RolePermissions(RoleId,PermissionId,CreatedAtUtc)
    SELECT role.RoleId,@PermissionId,SYSUTCDATETIME()
    FROM (VALUES(@SuperAdminRoleId),(@PlatformSupportRoleId)) roles(RoleId)
    JOIN mst.Roles role ON role.RoleId=roles.RoleId
    WHERE NOT EXISTS
    (
        SELECT 1 FROM mst.RolePermissions existing
        WHERE existing.RoleId=role.RoleId AND existing.PermissionId=@PermissionId
    );

    IF EXISTS
    (
        SELECT 1
        FROM (VALUES(@SuperAdminRoleId),(@PlatformSupportRoleId)) requiredRoles(RoleId)
        WHERE NOT EXISTS
        (
            SELECT 1 FROM mst.RolePermissions rolePermission
            WHERE rolePermission.RoleId=requiredRoles.RoleId
              AND rolePermission.PermissionId=@PermissionId
        )
    )
        THROW 52934, 'Post-check failed: a required platform registration role assignment is missing.', 1;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT N'PASS' AS PermissionStatus,N'platform.registrations.read' AS PermissionCode,
       N'SUPER_ADMIN, PLATFORM_SUPPORT' AS GrantedRoles;
GO
