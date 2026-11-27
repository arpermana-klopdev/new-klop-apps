:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Additive authorization delta after v1.10 RBAC and v1.11 notification permission definitions.
-- No role-permission mappings are created or changed by this proposal.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53160, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53161, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53162, 'Refused: target database does not match the reviewed Development database.', 1;
IF OBJECT_ID(N'iam.usp_ValidateSessionAccess',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_GetPlatformPermissions',N'P') IS NULL
   OR OBJECT_ID(N'iam.PlatformRoleAssignments',N'U') IS NULL
   OR OBJECT_ID(N'mst.Roles',N'U') IS NULL
   OR OBJECT_ID(N'mst.RoleScopes',N'U') IS NULL
   OR OBJECT_ID(N'mst.RolePermissions',N'U') IS NULL
   OR OBJECT_ID(N'mst.Permissions',N'U') IS NULL
   OR OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NULL
   OR OBJECT_ID(N'mst.PermissionReadinessStatuses',N'U') IS NULL
    THROW 53163, 'Apply the reviewed v1.10 authorization migration and v1.11 permission catalog first.', 1;

DECLARE @PlatformScopeId BIGINT=
    (SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1);
IF @PlatformScopeId IS NULL
    THROW 53164, 'The active PLATFORM role scope is unavailable.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM mst.PermissionReadinessStatuses
    WHERE Code='HOLD' AND IsActive=1 AND AllowsEffective=0 AND AllowsMatrixEdit=0
)
    THROW 53165, 'The fail-closed HOLD readiness status is unavailable or has incompatible policy.', 1;

DECLARE @NotificationPermissions TABLE(Code VARCHAR(150) PRIMARY KEY);
INSERT @NotificationPermissions(Code) VALUES
('platform.notifications.read'),
('platform.notifications.draft.create'),
('platform.notifications.draft.edit'),
('platform.notifications.draft.preview'),
('platform.notifications.submit'),
('platform.notifications.approve'),
('platform.notifications.activate'),
('platform.notifications.archive'),
('platform.notifications.history'),
('platform.notifications.settings.read');

IF (SELECT COUNT_BIG(*) FROM @NotificationPermissions)<>10
   OR EXISTS
   (
       SELECT 1 FROM @NotificationPermissions proposed
       LEFT JOIN mst.Permissions permission ON permission.Code=proposed.Code
       WHERE permission.PermissionId IS NULL OR permission.RoleScopeId<>@PlatformScopeId
          OR permission.IsActive<>1 OR permission.IsSystem<>1
   )
    THROW 53166, 'All ten active system notification capabilities must exist in the PLATFORM permission scope.', 1;

IF EXISTS
(
    SELECT 1 FROM @NotificationPermissions proposed
    JOIN mst.Permissions permission ON permission.Code=proposed.Code
    JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
)
    THROW 53167, 'Notification role mappings already exist; stop for explicit owner matrix reconciliation.', 1;

IF EXISTS
(
    SELECT 1 FROM @NotificationPermissions proposed
    JOIN mst.Permissions permission ON permission.Code=proposed.Code
    JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    WHERE matrix.ReadinessCode<>'HOLD'
)
    THROW 53168, 'Existing notification matrix readiness is not HOLD; stop for explicit owner review.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT mst.PermissionMatrixMetadata
        (PermissionId,ModuleCode,ResourceCode,ActionCode,PermissionDescription,ReadinessCode,RestrictionReason)
    SELECT permission.PermissionId,'platform','notifications',
           SUBSTRING(permission.Code,LEN('platform.notifications.')+1,120),
           permission.Description,'HOLD',
           N'Notification capability is unassigned and held for owner review; no role grant is implied.'
    FROM @NotificationPermissions proposed
    JOIN mst.Permissions permission ON permission.Code=proposed.Code
    WHERE NOT EXISTS
    (
        SELECT 1 FROM mst.PermissionMatrixMetadata matrix
        WHERE matrix.PermissionId=permission.PermissionId
    );

    IF EXISTS
    (
        SELECT 1 FROM @NotificationPermissions proposed
        JOIN mst.Permissions permission ON permission.Code=proposed.Code
        LEFT JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
        WHERE matrix.PermissionId IS NULL OR matrix.ReadinessCode<>'HOLD'
    )
        THROW 53169, 'Notification matrix definitions must remain held for owner review.', 1;

    INSERT aud.AuditEvents
        (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
         ChangeSummaryJson,RequestId,CorrelationId)
    SELECT CONCAT(N'KLOP.NOTIFICATIONS.V1.11 DBA: ',SUSER_SNAME()),actionType.AuditActionTypeId,
           resultType.AuditResultTypeId,N'PLATFORM_PERMISSION_MATRIX',proposed.Code,
           (SELECT proposed.Code AS PermissionCode,N'HOLD' AS Readiness,
                   N'UNASSIGNED' AS RoleMapping FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
           CONVERT(VARCHAR(100),@ApprovalTicket),NEWID()
    FROM @NotificationPermissions proposed
    CROSS JOIN mst.AuditActionTypes actionType
    CROSS JOIN mst.AuditResultTypes resultType
    WHERE actionType.Code='UPDATE' AND actionType.IsActive=1
      AND resultType.Code='SUCCESS' AND resultType.IsActive=1;

    IF @@ROWCOUNT<>10
        THROW 53170, 'Notification authorization audit metadata is unavailable.', 1;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
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
        'platform.notifications.settings.read'
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
          ON roleScope.RoleScopeId=role.RoleScopeId
         AND roleScope.Code='PLATFORM'
         AND roleScope.IsActive=1
        JOIN mst.RolePermissions mapping
          ON mapping.RoleId=role.RoleId
         AND mapping.TenantTypeId IS NULL
        JOIN mst.Permissions permission
          ON permission.PermissionId=mapping.PermissionId
         AND permission.RoleScopeId=roleScope.RoleScopeId
         AND permission.Code=@PermissionCode
         AND permission.IsActive=1
        JOIN mst.PermissionMatrixMetadata matrix
          ON matrix.PermissionId=permission.PermissionId
        JOIN mst.PermissionReadinessStatuses readiness
          ON readiness.Code=matrix.ReadinessCode
         AND readiness.IsActive=1
         AND readiness.AllowsEffective=1
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
    JOIN mst.RolePermissions mapping
      ON mapping.RoleId=role.RoleId
     AND mapping.TenantTypeId IS NULL
    JOIN mst.Permissions permission
      ON permission.PermissionId=mapping.PermissionId
     AND permission.RoleScopeId=roleScope.RoleScopeId
     AND permission.IsActive=1
    JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    JOIN mst.PermissionReadinessStatuses readiness
      ON readiness.Code=matrix.ReadinessCode
     AND readiness.IsActive=1
     AND readiness.AllowsEffective=1
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
        'platform.notifications.settings.read'
      )
    ORDER BY permission.Code;
END;
GO
