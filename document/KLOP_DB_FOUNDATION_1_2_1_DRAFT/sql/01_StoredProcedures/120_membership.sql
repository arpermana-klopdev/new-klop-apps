-- Membership changes serialize with role changes on the SAME tenant-scoped application lock.
-- The trusted API must authenticate @ActorUserId and authorize subject to user session.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE ten.usp_InviteExistingUser
    @TenantId BIGINT,
    @ActorUserId BIGINT,
    @InviteeUserId BIGINT,
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL,
    @MembershipId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52140, 'Procedure must own the transaction.', 1;
    IF @TenantId IS NULL OR @ActorUserId IS NULL OR @InviteeUserId IS NULL OR @ActorUserId=@InviteeUserId
       THROW 52141, 'Invalid invitation parameters.', 1;

    DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(), @ActiveStatusId BIGINT, @InvitedStatusId BIGINT;
    DECLARE @ActionId BIGINT, @ResultId BIGINT, @BusinessTypeId BIGINT, @Json NVARCHAR(MAX);
    DECLARE @LockResult INT, @LockResource NVARCHAR(255);
    SET @MembershipId=NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        SET @LockResource=CONCAT(N'KLOP/TENANT/',CONVERT(NVARCHAR(20),@TenantId));
        EXEC @LockResult=sys.sp_getapplock
            @Resource=@LockResource,
            @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
        IF @LockResult < 0 THROW 52142, 'Tenant operation is busy.', 1;
        SELECT @ActiveStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='ACTIVE' AND IsActive=1;
        SELECT @InvitedStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='INVITED' AND IsActive=1;
        SELECT @ActionId=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
        SELECT @ResultId=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        SELECT @BusinessTypeId=BusinessEventTypeId FROM mst.BusinessEventTypes WHERE Code='MEMBERSHIP_CHANGED' AND IsActive=1;
        IF @ActiveStatusId IS NULL OR @InvitedStatusId IS NULL OR @ActionId IS NULL OR @ResultId IS NULL OR @BusinessTypeId IS NULL
           THROW 52143, 'Required master records missing.', 1;
        IF NOT EXISTS (
            SELECT 1 FROM ten.Tenants t WITH (UPDLOCK,HOLDLOCK)
            JOIN mst.TenantTypes ty ON ty.TenantTypeId=t.TenantTypeId
            JOIN mst.TenantStatuses ts ON ts.TenantStatusId=t.TenantStatusId
            WHERE t.TenantId=@TenantId AND ty.AllowMultipleMembers=1 AND ty.IsActive=1
              AND ts.Code IN ('ACTIVE','PENDING') AND ts.IsActive=1)
           THROW 52144, 'This tenant does not permit multiple members.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId=@InviteeUserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
           THROW 52145, 'Invitee must be active and email verified.', 1;
        IF NOT EXISTS (
            SELECT 1 FROM ten.TenantMemberships am
            JOIN iam.TenantRoleAssignments ar ON ar.MembershipId=am.MembershipId
            JOIN mst.Roles r ON r.RoleId=ar.RoleId AND r.IsActive=1
            JOIN mst.RoleScopes rs ON rs.RoleScopeId=r.RoleScopeId AND rs.Code='TENANT'
            JOIN mst.RolePermissions rp ON rp.RoleId=r.RoleId
            JOIN mst.Permissions p ON p.PermissionId=rp.PermissionId AND p.IsActive=1
            WHERE am.TenantId=@TenantId AND am.UserId=@ActorUserId
              AND am.MembershipStatusId=@ActiveStatusId AND p.Code='tenant.members.invite')
           THROW 52146, 'Actor lacks tenant invite permission.', 1;
        IF EXISTS (SELECT 1 FROM ten.TenantMemberships WITH (UPDLOCK,HOLDLOCK)
                   WHERE TenantId=@TenantId AND UserId=@InviteeUserId)
           THROW 52147, 'An invitation or membership already exists; reinstatement is not implemented.', 1;

        INSERT INTO ten.TenantMemberships (TenantId,UserId,MembershipStatusId,CreatedByUserId)
        VALUES (@TenantId,@InviteeUserId,@InvitedStatusId,@ActorUserId);
        SET @MembershipId=CONVERT(BIGINT,SCOPE_IDENTITY());
        SELECT @Json=(SELECT @MembershipId AS MembershipId,'INVITED' AS NewStatus
                       FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents (TenantId,ActorUserId,AuditActionTypeId,AuditResultTypeId,
                                     TargetType,TargetId,ChangeSummaryJson,RequestId,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@ActionId,@ResultId,'MEMBERSHIP',CONVERT(NVARCHAR(150),@MembershipId),
                @Json,@RequestId,@CorrelationId);
        INSERT INTO aud.BusinessEvents (TenantId,ActorUserId,BusinessEventTypeId,TargetType,TargetId,EventDataJson,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@BusinessTypeId,'MEMBERSHIP',CONVERT(NVARCHAR(150),@MembershipId),@Json,@CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE ten.usp_AcceptMembership
    @MembershipId BIGINT,
    @ActorUserId BIGINT,
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52150, 'Procedure must own the transaction.', 1;
    DECLARE @TenantId BIGINT, @Now DATETIME2(3)=SYSUTCDATETIME();
    DECLARE @LockResult INT, @LockResource NVARCHAR(255), @ActiveStatusId BIGINT, @InvitedStatusId BIGINT, @MemberRoleId BIGINT;
    DECLARE @ActionId BIGINT, @ResultId BIGINT, @BusinessTypeId BIGINT, @Json NVARCHAR(MAX);
    IF @MembershipId IS NULL OR @ActorUserId IS NULL THROW 52151, 'Invalid acceptance parameters.', 1;
    SELECT @TenantId=TenantId FROM ten.TenantMemberships WHERE MembershipId=@MembershipId;
    IF @TenantId IS NULL THROW 52152, 'Membership not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @LockResource=CONCAT(N'KLOP/TENANT/',CONVERT(NVARCHAR(20),@TenantId));
        EXEC @LockResult=sys.sp_getapplock
            @Resource=@LockResource,
            @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
        IF @LockResult < 0 THROW 52153, 'Tenant operation is busy.', 1;
        SELECT @ActiveStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='ACTIVE' AND IsActive=1;
        SELECT @InvitedStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='INVITED' AND IsActive=1;
        SELECT @MemberRoleId=r.RoleId FROM mst.Roles r JOIN mst.RoleScopes rs ON rs.RoleScopeId=r.RoleScopeId
         WHERE rs.Code='TENANT' AND r.Code='MEMBER' AND r.IsActive=1 AND r.IsAssignable=1;
        SELECT @ActionId=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='ACTIVATE' AND IsActive=1;
        SELECT @ResultId=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        SELECT @BusinessTypeId=BusinessEventTypeId FROM mst.BusinessEventTypes WHERE Code='MEMBERSHIP_CHANGED' AND IsActive=1;
        IF @ActiveStatusId IS NULL OR @InvitedStatusId IS NULL OR @MemberRoleId IS NULL
           OR @ActionId IS NULL OR @ResultId IS NULL OR @BusinessTypeId IS NULL
           THROW 52154, 'Required master records are unavailable.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId=@ActorUserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
           THROW 52155, 'Account is inactive or not verified.', 1;
        IF NOT EXISTS (SELECT 1 FROM ten.Tenants t JOIN mst.TenantStatuses ts ON ts.TenantStatusId=t.TenantStatusId
                       WHERE t.TenantId=@TenantId AND ts.Code IN ('ACTIVE','PENDING') AND ts.IsActive=1)
           THROW 52157, 'Tenant lifecycle does not allow membership acceptance.', 1;
        UPDATE ten.TenantMemberships
           SET MembershipStatusId=@ActiveStatusId, JoinedAtUtc=@Now,
               UpdatedAtUtc=@Now, UpdatedByUserId=@ActorUserId
         WHERE MembershipId=@MembershipId AND TenantId=@TenantId AND UserId=@ActorUserId
           AND MembershipStatusId=@InvitedStatusId;
        IF @@ROWCOUNT<>1 THROW 52156, 'Invitation not active or actor does not own invitation.', 1;
        INSERT INTO iam.TenantRoleAssignments (MembershipId,RoleId,AssignedByUserId)
        VALUES (@MembershipId,@MemberRoleId,@ActorUserId);
        SELECT @Json=(SELECT @MembershipId AS MembershipId,'ACTIVE' AS NewStatus,
                              'MEMBER' AS GrantedRole FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents (TenantId,ActorUserId,AuditActionTypeId,AuditResultTypeId,
                                     TargetType,TargetId,ChangeSummaryJson,RequestId,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@ActionId,@ResultId,'MEMBERSHIP',CONVERT(NVARCHAR(150),@MembershipId),
                @Json,@RequestId,@CorrelationId);
        INSERT INTO aud.BusinessEvents (TenantId,ActorUserId,BusinessEventTypeId,TargetType,TargetId,EventDataJson,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@BusinessTypeId,'MEMBERSHIP',CONVERT(NVARCHAR(150),@MembershipId),@Json,@CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE ten.usp_RemoveTenantMember
    @MembershipId BIGINT,
    @ActorUserId BIGINT,
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52160, 'Procedure must own the transaction.', 1;
    DECLARE @TenantId BIGINT, @Now DATETIME2(3)=SYSUTCDATETIME(), @TargetUserId BIGINT;
    DECLARE @LockResult INT, @LockResource NVARCHAR(255), @ActiveStatusId BIGINT, @RemovedStatusId BIGINT, @OwnerRoleId BIGINT;
    DECLARE @ActionId BIGINT, @ResultId BIGINT, @BusinessTypeId BIGINT, @Json NVARCHAR(MAX);
    DECLARE @IsOwner BIT=0, @OwnerCount BIGINT, @RemovedRoleCount INT;
    IF @MembershipId IS NULL OR @ActorUserId IS NULL THROW 52161, 'Invalid member removal parameters.', 1;
    SELECT @TenantId=TenantId FROM ten.TenantMemberships WHERE MembershipId=@MembershipId;
    IF @TenantId IS NULL THROW 52162, 'Membership not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @LockResource=CONCAT(N'KLOP/TENANT/',CONVERT(NVARCHAR(20),@TenantId));
        EXEC @LockResult=sys.sp_getapplock
            @Resource=@LockResource,
            @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
        IF @LockResult < 0 THROW 52163, 'Tenant operation is busy.', 1;
        SELECT @ActiveStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='ACTIVE' AND IsActive=1;
        SELECT @RemovedStatusId=MembershipStatusId FROM mst.MembershipStatuses WHERE Code='REMOVED' AND IsActive=1;
        SELECT @OwnerRoleId=r.RoleId FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
          WHERE s.Code='TENANT' AND r.Code='OWNER' AND r.IsActive=1;
        SELECT @ActionId=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='DEACTIVATE' AND IsActive=1;
        SELECT @ResultId=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        SELECT @BusinessTypeId=BusinessEventTypeId FROM mst.BusinessEventTypes WHERE Code='MEMBERSHIP_CHANGED' AND IsActive=1;
        IF @ActiveStatusId IS NULL OR @RemovedStatusId IS NULL OR @OwnerRoleId IS NULL
           OR @ActionId IS NULL OR @ResultId IS NULL OR @BusinessTypeId IS NULL
           THROW 52164, 'Required masters are unavailable.', 1;
        IF NOT EXISTS (
            SELECT 1 FROM ten.TenantMemberships am
            JOIN iam.TenantRoleAssignments ar ON ar.MembershipId=am.MembershipId
            JOIN mst.Roles r ON r.RoleId=ar.RoleId AND r.IsActive=1
            JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId AND s.Code='TENANT'
            JOIN mst.RolePermissions rp ON rp.RoleId=r.RoleId
            JOIN mst.Permissions p ON p.PermissionId=rp.PermissionId AND p.IsActive=1
            WHERE am.TenantId=@TenantId AND am.UserId=@ActorUserId
              AND am.MembershipStatusId=@ActiveStatusId AND p.Code='tenant.members.remove')
           THROW 52165, 'Actor lacks tenant remove permission.', 1;
        SELECT @TargetUserId=UserId FROM ten.TenantMemberships WITH (UPDLOCK,HOLDLOCK)
          WHERE MembershipId=@MembershipId AND TenantId=@TenantId AND MembershipStatusId=@ActiveStatusId;
        IF @TargetUserId IS NULL THROW 52166, 'Target is not an active member.', 1;
        IF EXISTS (SELECT 1 FROM iam.TenantRoleAssignments WHERE MembershipId=@MembershipId AND RoleId=@OwnerRoleId)
           SET @IsOwner=1;
        IF @IsOwner=1
        BEGIN
            SELECT @OwnerCount=COUNT_BIG(*)
              FROM ten.TenantMemberships m
              JOIN iam.TenantRoleAssignments a ON a.MembershipId=m.MembershipId AND a.RoleId=@OwnerRoleId
             WHERE m.TenantId=@TenantId AND m.MembershipStatusId=@ActiveStatusId;
            IF @OwnerCount<=1 THROW 52167, 'Cannot remove last active OWNER.', 1;
        END;
        DELETE FROM iam.TenantRoleAssignments WHERE MembershipId=@MembershipId;
        SET @RemovedRoleCount=@@ROWCOUNT;
        UPDATE ten.TenantMemberships SET MembershipStatusId=@RemovedStatusId,
            LeftAtUtc=@Now,UpdatedAtUtc=@Now,UpdatedByUserId=@ActorUserId
         WHERE MembershipId=@MembershipId AND MembershipStatusId=@ActiveStatusId;
        IF @@ROWCOUNT<>1 THROW 52168, 'Concurrent membership change detected.', 1;
        SELECT @Json=(SELECT @MembershipId AS MembershipId,'REMOVED' AS NewStatus,
                              @RemovedRoleCount AS RevokedRoleCount FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents (TenantId,ActorUserId,AuditActionTypeId,AuditResultTypeId,
                                     TargetType,TargetId,ChangeSummaryJson,RequestId,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@ActionId,@ResultId,'MEMBERSHIP',CONVERT(NVARCHAR(150),@MembershipId),
                @Json,@RequestId,@CorrelationId);
        INSERT INTO aud.BusinessEvents (TenantId,ActorUserId,BusinessEventTypeId,TargetType,TargetId,EventDataJson,CorrelationId)
        VALUES (@TenantId,@ActorUserId,@BusinessTypeId,'MEMBERSHIP',CONVERT(NVARCHAR(150),@MembershipId),@Json,@CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
