:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Permission catalog definitions only. This proposal assigns zero permissions to any role.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53150, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53151, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53152, 'Refused: target database does not match the reviewed Development database.', 1;

DECLARE @PlatformScopeId BIGINT=(SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1);
IF @PlatformScopeId IS NULL THROW 53153, 'The PLATFORM scope is not configured.', 1;
DECLARE @Permissions TABLE(Code VARCHAR(150) PRIMARY KEY,Name NVARCHAR(200),Description NVARCHAR(500),SortOrder INT);
INSERT @Permissions(Code,Name,Description,SortOrder) VALUES
('platform.notifications.read',N'Read notification templates',N'Read platform notification templates and channel catalog.',810),
('platform.notifications.draft.create',N'Create notification drafts',N'Create platform notification template drafts.',811),
('platform.notifications.draft.edit',N'Edit notification drafts',N'Edit draft platform notification template versions.',812),
('platform.notifications.draft.preview',N'Preview notification drafts',N'Preview drafts with synthetic nonfunctional values.',813),
('platform.notifications.submit',N'Submit notification templates',N'Submit notification versions for approval.',814),
('platform.notifications.approve',N'Approve notification templates',N'Approve or reject submitted notification versions.',815),
('platform.notifications.activate',N'Activate notification templates',N'Activate approved notification versions.',816),
('platform.notifications.archive',N'Archive notification templates',N'Archive eligible notification versions.',817),
('platform.notifications.history',N'Read notification delivery history',N'Read paginated redacted delivery outcomes.',818),
('platform.notifications.settings.read',N'Read notification readiness',N'Read safe SMTP configuration readiness metadata.',819);

IF EXISTS
(
    SELECT 1 FROM @Permissions proposed JOIN mst.Permissions existing ON existing.Code=proposed.Code
    WHERE existing.RoleScopeId<>@PlatformScopeId OR existing.IsActive<>1 OR existing.IsSystem<>1
)
    THROW 53154, 'An existing notification permission has incompatible scope or security metadata.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @CreatedPermissions TABLE(Code VARCHAR(150) PRIMARY KEY);
    INSERT mst.Permissions(RoleScopeId,Code,Name,Description,SortOrder,IsActive,IsSystem,CreatedAtUtc)
    OUTPUT inserted.Code INTO @CreatedPermissions(Code)
    SELECT @PlatformScopeId,proposed.Code,proposed.Name,proposed.Description,proposed.SortOrder,1,1,SYSUTCDATETIME()
    FROM @Permissions proposed
    WHERE NOT EXISTS(SELECT 1 FROM mst.Permissions existing WITH(UPDLOCK,HOLDLOCK)
                     WHERE existing.Code=proposed.Code AND existing.RoleScopeId=@PlatformScopeId);

    DECLARE @AuditActionId BIGINT=(SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1);
    DECLARE @AuditResultId BIGINT=(SELECT AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1);
    IF @AuditActionId IS NULL OR @AuditResultId IS NULL
        THROW 53155, 'Required CREATE/SUCCESS audit definitions are missing.', 1;
    INSERT aud.AuditEvents
        (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
         ChangeSummaryJson,RequestId,CorrelationId)
    SELECT CONCAT(N'KLOP.NOTIFICATIONS.V1.11 DBA: ',SUSER_SNAME()),@AuditActionId,@AuditResultId,
           N'PLATFORM_PERMISSION',created.Code,
           (SELECT created.Code AS PermissionCode,N'PLATFORM' AS Scope,N'NO_ROLE_MAPPINGS' AS RoleAssignments
            FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
           CONVERT(VARCHAR(100),@ApprovalTicket),NEWID()
    FROM @CreatedPermissions created;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
