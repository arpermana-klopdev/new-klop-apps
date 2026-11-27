-- Caller/API must attest @OwnerUserId to its authenticated user context; the DB does not
-- authenticate a web identity from a BIGINT argument. Restrict EXECUTE to trusted backend role.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE ten.usp_CreateTenantWithOwner
    @OwnerUserId BIGINT,
    @TenantCode VARCHAR(50),
    @TenantTypeCode VARCHAR(50),
    @DisplayName NVARCHAR(200),
    @OrganizationTypeId BIGINT = NULL,
    @RegisteredName NVARCHAR(250) = NULL,
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL,
    @TenantId BIGINT OUTPUT,
    @MembershipId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52130, 'Procedure must own the transaction.', 1;
    DECLARE @Code VARCHAR(50) = UPPER(LTRIM(RTRIM(@TenantCode)));
    DECLARE @Name NVARCHAR(200) = LTRIM(RTRIM(@DisplayName));
    DECLARE @Type VARCHAR(50) = UPPER(LTRIM(RTRIM(@TenantTypeCode)));
    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @TenantTypeId BIGINT, @StatusId BIGINT, @MemberStatusId BIGINT, @OwnerRoleId BIGINT;
    DECLARE @VerifyStatusId BIGINT, @ActionId BIGINT, @ResultId BIGINT, @BusinessTypeId BIGINT;
    DECLARE @Json NVARCHAR(MAX);
    SET @TenantId = NULL;
    SET @MembershipId = NULL;

    IF @OwnerUserId IS NULL OR @Code IS NULL OR @Code = '' OR @Name IS NULL OR @Name = N''
       OR @Type IS NULL OR @Type NOT IN ('PERSONAL','ORGANIZATION')
       THROW 52131, 'Invalid tenant parameters.', 1;
    IF (@Type='ORGANIZATION' AND (@OrganizationTypeId IS NULL OR NULLIF(LTRIM(RTRIM(@RegisteredName)),N'') IS NULL))
       OR (@Type='PERSONAL' AND (@OrganizationTypeId IS NOT NULL OR @RegisteredName IS NOT NULL))
       THROW 52132, 'Organization fields are inconsistent with tenant type.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WITH (UPDLOCK, HOLDLOCK)
                        WHERE UserId=@OwnerUserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
           THROW 52133, 'Owner must be active and email verified.', 1;
        SELECT @TenantTypeId = TenantTypeId FROM mst.TenantTypes WHERE Code=@Type AND IsActive=1;
        SELECT @StatusId = TenantStatusId FROM mst.TenantStatuses
         WHERE Code=CASE WHEN @Type='PERSONAL' THEN 'ACTIVE' ELSE 'PENDING' END AND IsActive=1;
        SELECT @MemberStatusId = MembershipStatusId FROM mst.MembershipStatuses WHERE Code='ACTIVE' AND IsActive=1;
        SELECT @OwnerRoleId = r.RoleId FROM mst.Roles r JOIN mst.RoleScopes rs ON rs.RoleScopeId=r.RoleScopeId
         WHERE rs.Code='TENANT' AND r.Code='OWNER' AND r.IsActive=1 AND r.IsAssignable=1;
        SELECT @VerifyStatusId = VerificationStatusId FROM mst.VerificationStatuses WHERE Code='UNVERIFIED' AND IsActive=1;
        SELECT @ActionId = AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
        SELECT @ResultId = AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        SELECT @BusinessTypeId = BusinessEventTypeId FROM mst.BusinessEventTypes WHERE Code='TENANT_CREATED' AND IsActive=1;
        IF @TenantTypeId IS NULL OR @StatusId IS NULL OR @MemberStatusId IS NULL OR @OwnerRoleId IS NULL
           OR @ActionId IS NULL OR @ResultId IS NULL OR @BusinessTypeId IS NULL
           OR (@Type='ORGANIZATION' AND @VerifyStatusId IS NULL)
           THROW 52134, 'Required master records are unavailable.', 1;
        IF @Type='ORGANIZATION' AND NOT EXISTS
            (SELECT 1 FROM mst.OrganizationTypes WHERE OrganizationTypeId=@OrganizationTypeId AND IsActive=1)
           THROW 52135, 'Organization type is invalid.', 1;
        IF EXISTS (SELECT 1 FROM ten.Tenants WITH (UPDLOCK, HOLDLOCK) WHERE TenantCode=@Code)
           THROW 52136, 'Tenant code is already used.', 1;
        -- PERSONAL user must own only one personal tenant; ORGANIZATION memberships remain many-to-many.
        IF @Type='PERSONAL' AND EXISTS (
             SELECT 1 FROM ten.Tenants t WITH (UPDLOCK, HOLDLOCK)
             JOIN ten.TenantMemberships m ON m.TenantId=t.TenantId
             JOIN mst.TenantTypes ty ON ty.TenantTypeId=t.TenantTypeId
             WHERE m.UserId=@OwnerUserId AND ty.Code='PERSONAL')
           THROW 52137, 'This user already has a personal tenant.', 1;

        INSERT INTO ten.Tenants (TenantCode, TenantTypeId, TenantStatusId, DisplayName, CreatedByUserId)
        VALUES (@Code,@TenantTypeId,@StatusId,@Name,@OwnerUserId);
        SET @TenantId = CONVERT(BIGINT,SCOPE_IDENTITY());
        IF @Type='ORGANIZATION'
            INSERT INTO ten.Organizations (TenantId,OrganizationTypeId,RegisteredName,VerificationStatusId)
            VALUES (@TenantId,@OrganizationTypeId,LTRIM(RTRIM(@RegisteredName)),@VerifyStatusId);
        INSERT INTO ten.TenantMemberships
            (TenantId,UserId,MembershipStatusId,JoinedAtUtc,CreatedByUserId)
        VALUES (@TenantId,@OwnerUserId,@MemberStatusId,@Now,@OwnerUserId);
        SET @MembershipId = CONVERT(BIGINT,SCOPE_IDENTITY());
        INSERT INTO iam.TenantRoleAssignments (MembershipId,RoleId,AssignedByUserId)
        VALUES (@MembershipId,@OwnerRoleId,@OwnerUserId);

        SELECT @Json=(SELECT @TenantId AS TenantId, @Type AS TenantType,
                              @MembershipId AS OwnerMembershipId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents
            (TenantId,ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
             ChangeSummaryJson,RequestId,CorrelationId)
        VALUES (@TenantId,@OwnerUserId,@ActionId,@ResultId,'TENANT',CONVERT(NVARCHAR(150),@TenantId),
                @Json,@RequestId,@CorrelationId);
        INSERT INTO aud.BusinessEvents
            (TenantId,ActorUserId,BusinessEventTypeId,TargetType,TargetId,EventDataJson,CorrelationId)
        VALUES (@TenantId,@OwnerUserId,@BusinessTypeId,'TENANT',CONVERT(NVARCHAR(150),@TenantId),
                @Json,@CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
