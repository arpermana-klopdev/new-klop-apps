-- Only roles in TENANT scope can be used. All OWNER-affecting mutations share tenant lock.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE iam.usp_AssignTenantRole
    @MembershipId BIGINT,
    @ActorUserId BIGINT,
    @RoleCode VARCHAR(50),
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52170, 'Procedure must own the transaction.', 1;
    DECLARE @TenantId BIGINT, @RoleId BIGINT, @RoleName VARCHAR(50)=UPPER(LTRIM(RTRIM(@RoleCode)));
    DECLARE @ActiveStatusId BIGINT, @OwnerRoleId BIGINT, @ActionId BIGINT, @ResultId BIGINT;
    DECLARE @LockResult INT, @LockResource NVARCHAR(255), @Json NVARCHAR(MAX);
    IF @MembershipId IS NULL OR @ActorUserId IS NULL OR @RoleName IS NULL OR @RoleName=''
       THROW 52171, 'Invalid role assignment parameters.', 1;
    SELECT @TenantId=TenantId FROM ten.TenantMemberships WHERE MembershipId=@MembershipId;
    IF @TenantId IS NULL THROW 52172, 'Target membership not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @LockResource=CONCAT(N'KLOP/TENANT/',CONVERT(NVARCHAR(20),@TenantId));
        EXEC @LockResult=sys.sp_getapplock
             @Resource=@LockResource,
             @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
        IF @LockResult<0 THROW 52173, 'Tenant operation is busy.', 1;
        SELECT @ActiveStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='ACTIVE' AND IsActive=1;
        SELECT @RoleId=r.RoleId FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
          WHERE s.Code='TENANT' AND r.Code=@RoleName AND r.IsActive=1 AND r.IsAssignable=1;
        SELECT @OwnerRoleId=r.RoleId FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
          WHERE s.Code='TENANT' AND r.Code='OWNER' AND r.IsActive=1;
        SELECT @ActionId=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='ASSIGN_ROLE' AND IsActive=1;
        SELECT @ResultId=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        IF @ActiveStatusId IS NULL OR @RoleId IS NULL OR @OwnerRoleId IS NULL
           OR @ActionId IS NULL OR @ResultId IS NULL
           THROW 52174, 'Role or required master data unavailable.', 1;
        IF NOT EXISTS (SELECT 1 FROM ten.TenantMemberships WITH (UPDLOCK,HOLDLOCK)
                       WHERE MembershipId=@MembershipId AND TenantId=@TenantId AND MembershipStatusId=@ActiveStatusId)
           THROW 52175, 'Target must be an active tenant member.', 1;
        IF NOT EXISTS (
            SELECT 1 FROM ten.TenantMemberships am
            JOIN iam.TenantRoleAssignments ar ON ar.MembershipId=am.MembershipId
            JOIN mst.Roles r ON r.RoleId=ar.RoleId AND r.IsActive=1
            JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId AND s.Code='TENANT'
            JOIN mst.RolePermissions rp ON rp.RoleId=r.RoleId
            JOIN mst.Permissions p ON p.PermissionId=rp.PermissionId AND p.IsActive=1
            WHERE am.TenantId=@TenantId AND am.UserId=@ActorUserId
              AND am.MembershipStatusId=@ActiveStatusId AND p.Code='tenant.roles.assign')
           THROW 52176, 'Actor lacks tenant role assignment permission.', 1;
        -- Scope-specific elevation guard: only current OWNER may assign OWNER.
        IF @RoleId=@OwnerRoleId AND NOT EXISTS (
            SELECT 1 FROM ten.TenantMemberships am
            JOIN iam.TenantRoleAssignments ar ON ar.MembershipId=am.MembershipId AND ar.RoleId=@OwnerRoleId
            WHERE am.TenantId=@TenantId AND am.UserId=@ActorUserId AND am.MembershipStatusId=@ActiveStatusId)
           THROW 52177, 'Only an active OWNER may assign OWNER.', 1;
        IF @RoleId=@OwnerRoleId AND EXISTS (
            SELECT 1 FROM ten.Tenants t JOIN mst.TenantTypes ty ON ty.TenantTypeId=t.TenantTypeId
            WHERE t.TenantId=@TenantId AND ty.AllowMultipleMembers=0)
           THROW 52179, 'PERSONAL tenant cannot receive another OWNER assignment.', 1;
        IF EXISTS (SELECT 1 FROM iam.TenantRoleAssignments WITH (UPDLOCK,HOLDLOCK)
                   WHERE MembershipId=@MembershipId AND RoleId=@RoleId)
           THROW 52178, 'Role is already assigned.', 1;

        INSERT INTO iam.TenantRoleAssignments (MembershipId,RoleId,AssignedByUserId)
        VALUES (@MembershipId,@RoleId,@ActorUserId);
        SELECT @Json=(SELECT @MembershipId AS MembershipId,@RoleName AS RoleCode
                       FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents
             (TenantId,ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
              ChangeSummaryJson,RequestId,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@ActionId,@ResultId,'TENANT_ROLE',
                CONVERT(NVARCHAR(150),@MembershipId),@Json,@RequestId,@CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_RevokeTenantRole
    @MembershipId BIGINT,
    @ActorUserId BIGINT,
    @RoleCode VARCHAR(50),
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 THROW 52180, 'Procedure must own the transaction.', 1;
    DECLARE @TenantId BIGINT, @RoleName VARCHAR(50)=UPPER(LTRIM(RTRIM(@RoleCode)));
    DECLARE @RoleId BIGINT, @OwnerRoleId BIGINT, @ActiveStatusId BIGINT;
    DECLARE @ActionId BIGINT, @ResultId BIGINT, @LockResult INT, @LockResource NVARCHAR(255), @Json NVARCHAR(MAX), @OwnerCount BIGINT;
    IF @MembershipId IS NULL OR @ActorUserId IS NULL OR @RoleName IS NULL OR @RoleName=''
       THROW 52181, 'Invalid role revocation parameters.', 1;
    SELECT @TenantId=TenantId FROM ten.TenantMemberships WHERE MembershipId=@MembershipId;
    IF @TenantId IS NULL THROW 52182, 'Target membership not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @LockResource=CONCAT(N'KLOP/TENANT/',CONVERT(NVARCHAR(20),@TenantId));
        EXEC @LockResult=sys.sp_getapplock
             @Resource=@LockResource,
             @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
        IF @LockResult<0 THROW 52183, 'Tenant operation is busy.', 1;
        SELECT @ActiveStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='ACTIVE' AND IsActive=1;
        SELECT @RoleId=r.RoleId FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
         WHERE s.Code='TENANT' AND r.Code=@RoleName AND r.IsActive=1;
        SELECT @OwnerRoleId=r.RoleId FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
         WHERE s.Code='TENANT' AND r.Code='OWNER' AND r.IsActive=1;
        SELECT @ActionId=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='REVOKE_ROLE' AND IsActive=1;
        SELECT @ResultId=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        IF @ActiveStatusId IS NULL OR @RoleId IS NULL OR @OwnerRoleId IS NULL OR @ActionId IS NULL OR @ResultId IS NULL
           THROW 52184, 'Role or required master data unavailable.', 1;
        IF NOT EXISTS (SELECT 1 FROM ten.TenantMemberships WITH (UPDLOCK,HOLDLOCK)
                       WHERE MembershipId=@MembershipId AND TenantId=@TenantId AND MembershipStatusId=@ActiveStatusId)
           THROW 52185, 'Target must be an active tenant member.', 1;
        IF NOT EXISTS (
            SELECT 1 FROM ten.TenantMemberships am
            JOIN iam.TenantRoleAssignments ar ON ar.MembershipId=am.MembershipId
            JOIN mst.Roles r ON r.RoleId=ar.RoleId AND r.IsActive=1
            JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId AND s.Code='TENANT'
            JOIN mst.RolePermissions rp ON rp.RoleId=r.RoleId
            JOIN mst.Permissions p ON p.PermissionId=rp.PermissionId AND p.IsActive=1
            WHERE am.TenantId=@TenantId AND am.UserId=@ActorUserId
              AND am.MembershipStatusId=@ActiveStatusId AND p.Code='tenant.roles.assign')
           THROW 52186, 'Actor lacks tenant role assignment permission.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.TenantRoleAssignments WITH (UPDLOCK,HOLDLOCK)
                       WHERE MembershipId=@MembershipId AND RoleId=@RoleId)
           THROW 52187, 'Role is not assigned.', 1;
        IF @RoleId=@OwnerRoleId
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM ten.TenantMemberships am
                JOIN iam.TenantRoleAssignments ar ON ar.MembershipId=am.MembershipId AND ar.RoleId=@OwnerRoleId
                WHERE am.TenantId=@TenantId AND am.UserId=@ActorUserId AND am.MembershipStatusId=@ActiveStatusId)
               THROW 52188, 'Only an active OWNER may revoke OWNER.', 1;
            SELECT @OwnerCount=COUNT_BIG(*) FROM ten.TenantMemberships m
              JOIN iam.TenantRoleAssignments ar ON ar.MembershipId=m.MembershipId AND ar.RoleId=@OwnerRoleId
              WHERE m.TenantId=@TenantId AND m.MembershipStatusId=@ActiveStatusId;
            IF @OwnerCount<=1 THROW 52189, 'Cannot revoke the last active OWNER.', 1;
        END;
        DELETE FROM iam.TenantRoleAssignments WHERE MembershipId=@MembershipId AND RoleId=@RoleId;
        IF @@ROWCOUNT<>1 THROW 52190, 'Concurrent role change detected.', 1;
        SELECT @Json=(SELECT @MembershipId AS MembershipId,@RoleName AS RevokedRoleCode
                       FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents
             (TenantId,ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
              ChangeSummaryJson,RequestId,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@ActionId,@ResultId,'TENANT_ROLE',
                CONVERT(NVARCHAR(150),@MembershipId),@Json,@RequestId,@CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
