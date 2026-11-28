:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Seed PLATFORM permission definitions and HOLD/unassigned matrix metadata only.
-- Never creates a role mapping, user, role assignment, grant, or readiness activation.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53520, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53521, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53522, 'Refused: target database does not match the reviewed Development database.', 1;
IF OBJECT_ID(N'mst.Permissions',N'U') IS NULL OR OBJECT_ID(N'mst.RoleScopes',N'U') IS NULL
   OR OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NULL
   OR OBJECT_ID(N'mst.PermissionReadinessStatuses',N'U') IS NULL
   OR OBJECT_ID(N'mst.RolePermissions',N'U') IS NULL OR OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
    THROW 53523, 'Apply the reviewed v1.10 RBAC and v1.11 notification prerequisites first.', 1;

DECLARE @PlatformScopeId BIGINT=
    (SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1);
IF @PlatformScopeId IS NULL
    THROW 53524, 'The active PLATFORM scope is unavailable.', 1;
IF NOT EXISTS(SELECT 1 FROM mst.PermissionReadinessStatuses
              WHERE Code='HOLD' AND IsActive=1 AND AllowsEffective=0 AND AllowsMatrixEdit=0)
    THROW 53525, 'The fail-closed HOLD readiness policy is unavailable.', 1;

DECLARE @PermissionSeeds TABLE
(
    Code VARCHAR(150) PRIMARY KEY,
    Name NVARCHAR(300) NOT NULL,
    Description NVARCHAR(1000) NOT NULL,
    ResourceCode VARCHAR(100) NOT NULL,
    ActionCode VARCHAR(120) NOT NULL,
    SortOrder INT NOT NULL
);
INSERT @PermissionSeeds VALUES
('platform.configurations.read',N'Read configuration catalog',N'Read only explicitly classified safe configuration metadata.',N'configurations',N'read',830),
('platform.configurations.request.create',N'Create configuration request',N'Create a draft for an explicitly eligible policy key.',N'configurations',N'request.create',831),
('platform.configurations.request.edit',N'Edit configuration request',N'Edit an owned draft before submission.',N'configurations',N'request.edit',832),
('platform.configurations.request.submit',N'Submit configuration request',N'Submit a draft for independent approval.',N'configurations',N'request.submit',833),
('platform.configurations.request.cancel',N'Cancel configuration request',N'Cancel an owned draft or submitted request.',N'configurations',N'request.cancel',834),
('platform.configurations.approve',N'Approve configuration request',N'Approve or reject a submitted request; self-approval is denied.',N'configurations',N'approve',835),
('platform.configurations.apply',N'Apply approved configuration',N'Apply a separately approved configuration request exactly once.',N'configurations',N'apply',836),
('platform.configurations.history',N'Read configuration history',N'Read paginated safe applied-change history.',N'configurations',N'history',837);

IF EXISTS
(
    SELECT 1 FROM @PermissionSeeds seed JOIN mst.Permissions permission ON permission.Code=seed.Code
    WHERE permission.RoleScopeId<>@PlatformScopeId OR permission.IsActive<>1 OR permission.IsSystem<>1
)
    THROW 53526, 'An existing configuration permission has incompatible scope or security metadata.', 1;
IF EXISTS
(
    SELECT 1 FROM @PermissionSeeds seed JOIN mst.Permissions permission ON permission.Code=seed.Code
    JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
)
    THROW 53527, 'A configuration permission is already mapped; stop for explicit owner reconciliation.', 1;
IF EXISTS
(
    SELECT 1 FROM @PermissionSeeds seed JOIN mst.Permissions permission ON permission.Code=seed.Code
    JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    WHERE matrix.ReadinessCode<>'HOLD'
)
    THROW 53528, 'Configuration permission readiness is not HOLD; stop for owner review.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT mst.Permissions(RoleScopeId,Code,Name,Description,SortOrder,IsActive,IsSystem,CreatedAtUtc)
    SELECT @PlatformScopeId,seed.Code,seed.Name,seed.Description,seed.SortOrder,1,1,SYSUTCDATETIME()
    FROM @PermissionSeeds seed
    WHERE NOT EXISTS(SELECT 1 FROM mst.Permissions existing WITH(UPDLOCK,HOLDLOCK)
                     WHERE existing.Code=seed.Code AND existing.RoleScopeId=@PlatformScopeId);

    INSERT mst.PermissionMatrixMetadata
        (PermissionId,ModuleCode,ResourceCode,ActionCode,PermissionDescription,ReadinessCode,RestrictionReason)
    SELECT permission.PermissionId,'platform',seed.ResourceCode,seed.ActionCode,seed.Description,'HOLD',
           N'Unassigned and held for separate owner review; no effective grant is implied.'
    FROM @PermissionSeeds seed
    JOIN mst.Permissions permission ON permission.Code=seed.Code AND permission.RoleScopeId=@PlatformScopeId
    WHERE NOT EXISTS(SELECT 1 FROM mst.PermissionMatrixMetadata matrix
                     WHERE matrix.PermissionId=permission.PermissionId);

    IF EXISTS
    (
        SELECT 1 FROM @PermissionSeeds seed JOIN mst.Permissions permission ON permission.Code=seed.Code
        LEFT JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
        WHERE permission.RoleScopeId<>@PlatformScopeId OR permission.IsActive<>1 OR permission.IsSystem<>1
           OR matrix.PermissionId IS NULL OR matrix.ReadinessCode<>'HOLD'
           OR EXISTS(SELECT 1 FROM mst.RolePermissions mapping WHERE mapping.PermissionId=permission.PermissionId)
    )
        THROW 53529, 'Configuration permission catalog must remain unassigned and on HOLD.', 1;

    INSERT aud.AuditEvents
        (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
         ChangeSummaryJson,RequestId,CorrelationId)
    SELECT CONCAT(N'KLOP.CONFIG.V1.12 DBA: ',SUSER_SNAME()),actionType.AuditActionTypeId,
           resultType.AuditResultTypeId,N'PLATFORM_PERMISSION_MATRIX',seed.Code,
           (SELECT seed.Code AS PermissionCode,N'HOLD' AS Readiness,
                   N'UNASSIGNED' AS RoleMapping FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
           CONVERT(VARCHAR(100),@ApprovalTicket),NEWID()
    FROM @PermissionSeeds seed
    CROSS JOIN mst.AuditActionTypes actionType
    CROSS JOIN mst.AuditResultTypes resultType
    WHERE actionType.Code='CREATE' AND actionType.IsActive=1
      AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
    IF @@ROWCOUNT<>8 THROW 53530, 'Configuration permission audit metadata is unavailable.', 1;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
