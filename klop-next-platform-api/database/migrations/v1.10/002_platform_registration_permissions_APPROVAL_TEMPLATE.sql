:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Approval-gated, idempotent seed for the only currently supported RBAC v1.0 priority.
-- Adds no roles, users, runtime grants, role assignments, or non-registration permissions.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Environment NVARCHAR(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase SYSNAME=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
IF LEN(@ApprovalTicket)>100
    THROW 52980, 'Approval ticket must be at most 100 characters for the audit RequestId field.', 1;
IF OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditActionTypes',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditResultTypes',N'U') IS NULL
    THROW 52977, 'Required audit objects are missing; no permission seed can be applied.', 1;
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52970, 'Refused: only the reviewed Development SQL Server is permitted.', 1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
    THROW 52971, 'Refused: this template is restricted to KlopPlatformDB.', 1;

DECLARE @PlatformScopeId BIGINT=
    (SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1);
DECLARE @SuperAdminRoleId BIGINT=
    (SELECT RoleId FROM mst.Roles WHERE RoleId=1 AND Code='SUPER_ADMIN'
      AND RoleScopeId=@PlatformScopeId AND IsActive=1 AND IsSystem=1);
DECLARE @SupportRoleId BIGINT=
    (SELECT RoleId FROM mst.Roles WHERE RoleId=2 AND Code='PLATFORM_SUPPORT'
      AND RoleScopeId=@PlatformScopeId AND IsActive=1 AND IsSystem=1);
IF @PlatformScopeId<>1 OR @SuperAdminRoleId<>1 OR @SupportRoleId<>2
    THROW 52972, 'The approved PLATFORM scope or existing platform roles changed; no seed was applied.', 1;

DECLARE @PermissionCount INT;
SELECT @PermissionCount=COUNT(*)
FROM mst.Permissions
WHERE Code='platform.registrations.read';
IF @PermissionCount>1
    THROW 52973, 'Duplicate platform.registrations.read rows exist; reconcile them manually.', 1;

IF EXISTS
(
    SELECT 1 FROM mst.Permissions
    WHERE Code='platform.registrations.read'
      AND (RoleScopeId<>@PlatformScopeId OR IsActive<>1 OR IsSystem<>1)
)
    THROW 52974, 'The existing registration permission has incompatible scope or security metadata.', 1;

DECLARE @PermissionId BIGINT=
    (SELECT PermissionId FROM mst.Permissions
     WHERE Code='platform.registrations.read' AND RoleScopeId=@PlatformScopeId);
IF EXISTS
(
    SELECT 1
    FROM mst.RolePermissions mapping
    JOIN mst.Roles role ON role.RoleId=mapping.RoleId
    WHERE mapping.PermissionId=@PermissionId
      AND role.RoleId NOT IN(@SuperAdminRoleId,@SupportRoleId)
)
    THROW 52975, 'The registration permission is mapped to a role denied by the approved matrix.', 1;

SELECT N'platform.registrations.read' AS PermissionCode,
       CASE WHEN @PermissionId IS NULL THEN N'WOULD CREATE' ELSE N'PRESERVE EXISTING' END AS PermissionAction;
SELECT role.Code AS RoleCode,
       CASE WHEN mapping.RoleId IS NULL THEN N'WOULD ADD APPROVED READ MAPPING'
            ELSE N'PRESERVE EXISTING MAPPING' END AS MappingAction
FROM (VALUES(@SuperAdminRoleId),(@SupportRoleId)) approved(RoleId)
JOIN mst.Roles role ON role.RoleId=approved.RoleId
LEFT JOIN mst.RolePermissions mapping
  ON mapping.RoleId=role.RoleId AND mapping.PermissionId=@PermissionId
ORDER BY role.RoleId;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
    SELECT N'DRY RUN - NO CHANGES' AS Status,
           N'Explicit Development DBA approval and a change ticket are required.' AS NextStep;
    RETURN;
END;

BEGIN TRY
    DECLARE @PermissionCreated BIT=0;
    DECLARE @AuditActionId BIGINT;
    DECLARE @AuditResultId BIGINT;
    DECLARE @CorrelationId UNIQUEIDENTIFIER=NEWID();
    DECLARE @ChangeSummary NVARCHAR(MAX);
    DECLARE @AddedRoleMappings TABLE(RoleId BIGINT PRIMARY KEY);

    BEGIN TRANSACTION;
    SELECT @PermissionCount=COUNT(*)
    FROM mst.Permissions WITH(UPDLOCK,HOLDLOCK)
    WHERE Code='platform.registrations.read';
    IF @PermissionCount>1
        THROW 52973, 'Duplicate platform.registrations.read rows exist; reconcile them manually.', 1;
    IF EXISTS
    (
        SELECT 1 FROM mst.Permissions
        WHERE Code='platform.registrations.read'
          AND (RoleScopeId<>@PlatformScopeId OR IsActive<>1 OR IsSystem<>1)
    )
        THROW 52974, 'The existing registration permission has incompatible scope or security metadata.', 1;
    SELECT @PermissionId=PermissionId
    FROM mst.Permissions
    WHERE Code='platform.registrations.read' AND RoleScopeId=@PlatformScopeId;

    IF @PermissionId IS NULL
    BEGIN
        INSERT mst.Permissions
            (RoleScopeId,Code,Name,Description,SortOrder,IsActive,IsSystem,CreatedAtUtc)
        VALUES
            (@PlatformScopeId,'platform.registrations.read',N'Read platform registrations',
             N'Read registration summaries, applications, profile details, and persisted timelines.',
             730,1,1,SYSUTCDATETIME());
        SET @PermissionId=CONVERT(BIGINT,SCOPE_IDENTITY());
        SET @PermissionCreated=1;
    END;

    INSERT mst.RolePermissions(RoleId,PermissionId,CreatedAtUtc)
    OUTPUT inserted.RoleId INTO @AddedRoleMappings(RoleId)
    SELECT approved.RoleId,@PermissionId,SYSUTCDATETIME()
    FROM (VALUES(@SuperAdminRoleId),(@SupportRoleId)) approved(RoleId)
    WHERE NOT EXISTS
    (
        SELECT 1 FROM mst.RolePermissions existing WITH(UPDLOCK,HOLDLOCK)
        WHERE existing.RoleId=approved.RoleId AND existing.PermissionId=@PermissionId
    );

    IF EXISTS
    (
        SELECT 1
        FROM (VALUES(@SuperAdminRoleId),(@SupportRoleId)) required(RoleId)
        WHERE NOT EXISTS
        (
            SELECT 1 FROM mst.RolePermissions mapping
            WHERE mapping.RoleId=required.RoleId AND mapping.PermissionId=@PermissionId
        )
    )
        THROW 52976, 'Post-check failed: an approved registration role mapping is missing.', 1;

    IF @PermissionCreated=1
    BEGIN
        SELECT @AuditActionId=AuditActionTypeId
        FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
        SELECT @AuditResultId=AuditResultTypeId
        FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        IF @AuditActionId IS NULL OR @AuditResultId IS NULL
            THROW 52978, 'Required permission-creation audit metadata is missing.', 1;
        SET @ChangeSummary=
        (
            SELECT N'platform.registrations.read' AS PermissionCode,
                   N'PLATFORM' AS RoleScope,
                   N'KLOP-PLATFORM-RBAC-1.0' AS Baseline
            FOR JSON PATH,WITHOUT_ARRAY_WRAPPER
        );
        INSERT aud.AuditEvents
            (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
             ChangeSummaryJson,RequestId,CorrelationId)
        VALUES
            (CONCAT(N'KLOP.RBAC.V1.10 DBA: ',SUSER_SNAME()),@AuditActionId,@AuditResultId,
             N'PLATFORM_PERMISSION',N'platform.registrations.read',
             @ChangeSummary,CONVERT(VARCHAR(100),@ApprovalTicket),@CorrelationId);
    END;

    IF EXISTS(SELECT 1 FROM @AddedRoleMappings)
    BEGIN
        SELECT @AuditActionId=AuditActionTypeId
        FROM mst.AuditActionTypes WHERE Code='UPDATE' AND IsActive=1;
        SELECT @AuditResultId=AuditResultTypeId
        FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        IF @AuditActionId IS NULL OR @AuditResultId IS NULL
            THROW 52979, 'Required role-permission audit metadata is missing.', 1;
        INSERT aud.AuditEvents
            (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
             ChangeSummaryJson,RequestId,CorrelationId)
        SELECT CONCAT(N'KLOP.RBAC.V1.10 DBA: ',SUSER_SNAME()),@AuditActionId,@AuditResultId,
               N'ROLE_PERMISSION',CONCAT(role.Code,N':platform.registrations.read'),
               (SELECT role.Code AS RoleCode,
                       N'platform.registrations.read' AS PermissionCode,
                       N'KLOP-PLATFORM-RBAC-1.0' AS Baseline
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
               CONVERT(VARCHAR(100),@ApprovalTicket),@CorrelationId
        FROM @AddedRoleMappings added
        JOIN mst.Roles role ON role.RoleId=added.RoleId;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT N'PASS' AS SeedStatus,N'platform.registrations.read' AS PermissionCode,
       N'SUPER_ADMIN, PLATFORM_SUPPORT' AS GrantedRoles;
GO
