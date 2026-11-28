:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Add only the reviewed v1.12 codes to both existing PLATFORM authorization procedures.
-- Preserves v1.10/v1.11 session, scope, readiness, and existing-code checks.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53540, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53541, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53542, 'Refused: target database does not match the reviewed Development database.', 1;
IF OBJECT_ID(N'iam.usp_ValidateSessionAccess',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_GetPlatformPermissions',N'P') IS NULL
   OR OBJECT_ID(N'mst.Permissions',N'U') IS NULL
   OR OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NULL
   OR OBJECT_ID(N'mst.PermissionReadinessStatuses',N'U') IS NULL
   OR OBJECT_ID(N'mst.RolePermissions',N'U') IS NULL
   OR OBJECT_ID(N'iam.PlatformRoleAssignments',N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
    THROW 53543, 'The reviewed v1.10/v1.11 PLATFORM authorization prerequisites are required.', 1;
IF EXISTS
(
    SELECT 1 FROM (VALUES
      ('platform.configurations.read'),
      ('platform.configurations.request.create'),
      ('platform.configurations.request.edit'),
      ('platform.configurations.request.submit'),
      ('platform.configurations.request.cancel'),
      ('platform.configurations.approve'),
      ('platform.configurations.apply'),
      ('platform.configurations.history')
    ) proposed(Code)
    LEFT JOIN mst.Permissions permission ON permission.Code=proposed.Code
    LEFT JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    WHERE permission.PermissionId IS NULL OR permission.IsActive<>1 OR permission.IsSystem<>1
       OR matrix.PermissionId IS NULL OR matrix.ReadinessCode<>'HOLD'
)
    THROW 53544, 'All v1.12 permissions must exist on HOLD before the authorization delta.', 1;
IF EXISTS
(
    SELECT 1 FROM mst.Permissions permission
    JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
    WHERE permission.Code LIKE 'platform.configurations.%'
)
    THROW 53545, 'Configuration permissions must remain unassigned; reconcile before altering authorization.', 1;
GO

CREATE OR ALTER PROCEDURE iam.usp_ValidatePlatformPermission
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @PermissionCode VARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;
    IF @PermissionCode NOT IN
    (
        'platform.legal_documents.read',
        'platform.legal_documents.draft.create',
        'platform.legal_documents.draft.edit',
        'platform.legal_documents.draft.preview',
        'platform.legal_documents.submit',
        'platform.legal_documents.approve',
        'platform.legal_documents.publish',
        'platform.legal_documents.archive',
        'platform.registrations.read',
        'platform.role_permissions.read',
        'platform.role_permissions.update',
        'platform.notifications.read',
        'platform.notifications.draft.create',
        'platform.notifications.draft.edit',
        'platform.notifications.draft.preview',
        'platform.notifications.submit',
        'platform.notifications.approve',
        'platform.notifications.activate',
        'platform.notifications.archive',
        'platform.notifications.history',
        'platform.notifications.settings.read',
        'platform.configurations.read',
        'platform.configurations.request.create',
        'platform.configurations.request.edit',
        'platform.configurations.request.submit',
        'platform.configurations.request.cancel',
        'platform.configurations.approve',
        'platform.configurations.apply',
        'platform.configurations.history'
    )
        THROW 52332, 'Platform permission denied.', 1;

    DECLARE @SessionValidation TABLE(IsAuthorized BIT NOT NULL);
    INSERT @SessionValidation(IsAuthorized)
    EXEC iam.usp_ValidateSessionAccess
        @UserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @TenantId=NULL,
        @PermissionCode=NULL;

    IF NOT EXISTS
    (
        SELECT 1
        FROM iam.PlatformRoleAssignments assignment
        JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.IsActive=1
        JOIN mst.RoleScopes roleScope
          ON roleScope.RoleScopeId=role.RoleScopeId AND roleScope.Code='PLATFORM' AND roleScope.IsActive=1
        JOIN mst.RolePermissions mapping ON mapping.RoleId=role.RoleId AND mapping.TenantTypeId IS NULL
        JOIN mst.Permissions permission
          ON permission.PermissionId=mapping.PermissionId
         AND permission.RoleScopeId=roleScope.RoleScopeId
         AND permission.Code=@PermissionCode AND permission.IsActive=1
        JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
        JOIN mst.PermissionReadinessStatuses readiness
          ON readiness.Code=matrix.ReadinessCode AND readiness.IsActive=1 AND readiness.AllowsEffective=1
        WHERE assignment.UserId=@ActorUserId
    )
        THROW 52332, 'Platform permission denied.', 1;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_GetPlatformPermissions
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @SessionValidation TABLE(IsAuthorized BIT NOT NULL);
    INSERT @SessionValidation(IsAuthorized)
    EXEC iam.usp_ValidateSessionAccess
        @UserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @TenantId=NULL,
        @PermissionCode=NULL;

    SELECT DISTINCT permission.Code AS PermissionCode
    FROM iam.PlatformRoleAssignments assignment
    JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.IsActive=1
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
        AND roleScope.Code='PLATFORM' AND roleScope.IsActive=1
    JOIN mst.RolePermissions mapping ON mapping.RoleId=role.RoleId AND mapping.TenantTypeId IS NULL
    JOIN mst.Permissions permission
      ON permission.PermissionId=mapping.PermissionId
     AND permission.RoleScopeId=roleScope.RoleScopeId AND permission.IsActive=1
    JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    JOIN mst.PermissionReadinessStatuses readiness
      ON readiness.Code=matrix.ReadinessCode AND readiness.IsActive=1 AND readiness.AllowsEffective=1
    WHERE assignment.UserId=@ActorUserId
      AND permission.Code IN
      (
        'platform.legal_documents.read',
        'platform.legal_documents.draft.create',
        'platform.legal_documents.draft.edit',
        'platform.legal_documents.draft.preview',
        'platform.legal_documents.submit',
        'platform.legal_documents.approve',
        'platform.legal_documents.publish',
        'platform.legal_documents.archive',
        'platform.registrations.read',
        'platform.role_permissions.read',
        'platform.role_permissions.update',
        'platform.notifications.read',
        'platform.notifications.draft.create',
        'platform.notifications.draft.edit',
        'platform.notifications.draft.preview',
        'platform.notifications.submit',
        'platform.notifications.approve',
        'platform.notifications.activate',
        'platform.notifications.archive',
        'platform.notifications.history',
        'platform.notifications.settings.read',
        'platform.configurations.read',
        'platform.configurations.request.create',
        'platform.configurations.request.edit',
        'platform.configurations.request.submit',
        'platform.configurations.request.cancel',
        'platform.configurations.approve',
        'platform.configurations.apply',
        'platform.configurations.history'
      )
    ORDER BY permission.Code;
END;
GO
