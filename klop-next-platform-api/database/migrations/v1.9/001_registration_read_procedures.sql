-- KLOP Platform v1.9 read-only registration administration procedures.
-- DBA review and explicit Development approval required. Never run automatically or in Production.
-- Creates no permissions, role assignments, grants, or registration data.
SET NOCOUNT ON;

IF DB_NAME() <> N'KlopPlatformDB'
    THROW 52900, 'v1.9 registration procedures require KlopPlatformDB.', 1;
IF OBJECT_ID(N'iam.usp_ValidatePlatformPermission', N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidateSessionAccess', N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_GetPlatformPermissions', N'P') IS NULL
   OR OBJECT_ID(N'iam.PlatformRoleAssignments', N'U') IS NULL
   OR OBJECT_ID(N'mst.RoleScopes', N'U') IS NULL
   OR OBJECT_ID(N'mst.Roles', N'U') IS NULL
   OR OBJECT_ID(N'mst.RolePermissions', N'U') IS NULL
   OR OBJECT_ID(N'mst.Permissions', N'U') IS NULL
   OR OBJECT_ID(N'iam.Users', N'U') IS NULL
   OR OBJECT_ID(N'iam.VerificationChallenges', N'U') IS NULL
   OR OBJECT_ID(N'mst.TenantTypes', N'U') IS NULL
   OR OBJECT_ID(N'mst.OnboardingStatuses', N'U') IS NULL
   OR OBJECT_ID(N'mst.VerificationPurposes', N'U') IS NULL
   OR OBJECT_ID(N'mst.OrganizationTypes', N'U') IS NULL
   OR OBJECT_ID(N'mst.TenantStatuses', N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditActionTypes', N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditResultTypes', N'U') IS NULL
   OR OBJECT_ID(N'reg.RegistrationApplications', N'U') IS NULL
   OR OBJECT_ID(N'reg.RegistrationApplicationHistory', N'U') IS NULL
   OR OBJECT_ID(N'reg.PersonalOnboardingDetails', N'U') IS NULL
   OR OBJECT_ID(N'reg.OrganizationOnboardingDetails', N'U') IS NULL
   OR OBJECT_ID(N'leg.UserLegalConsents', N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents', N'U') IS NULL
   OR OBJECT_ID(N'ten.Tenants', N'U') IS NULL
    THROW 52901, 'v1.9 registration procedure prerequisites are incomplete; stop for DBA reconciliation.', 1;
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
        'platform.registrations.read'
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
        JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
            AND roleScope.Code='PLATFORM' AND roleScope.IsActive=1
        JOIN mst.RolePermissions rolePermission ON rolePermission.RoleId=role.RoleId
        JOIN mst.Permissions permission ON permission.PermissionId=rolePermission.PermissionId
            AND permission.RoleScopeId=roleScope.RoleScopeId
            AND permission.Code=@PermissionCode AND permission.IsActive=1
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
    JOIN mst.RolePermissions rolePermission ON rolePermission.RoleId=role.RoleId
    JOIN mst.Permissions permission ON permission.PermissionId=rolePermission.PermissionId
        AND permission.RoleScopeId=roleScope.RoleScopeId AND permission.IsActive=1
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
        'platform.registrations.read'
      )
    ORDER BY permission.Code;
END;
GO

CREATE OR ALTER PROCEDURE reg.usp_GetPlatformRegistrationSummary
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @RegistrationTypeCode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET @RegistrationTypeCode=UPPER(LTRIM(RTRIM(@RegistrationTypeCode)));
    IF @RegistrationTypeCode NOT IN ('PERSONAL','ORGANIZATION')
        THROW 52910, 'A supported registration type is required.', 1;

    EXEC iam.usp_ValidatePlatformPermission
        @ActorUserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @PermissionCode='platform.registrations.read';

    SELECT @RegistrationTypeCode AS RegistrationType,
           COUNT_BIG(*) AS TotalRegistrations,
           COUNT_BIG(CASE WHEN u.EmailVerifiedAtUtc IS NULL THEN 1 END) AS PendingEmailVerification,
           COUNT_BIG(CASE WHEN u.EmailVerifiedAtUtc IS NOT NULL THEN 1 END) AS EmailVerified,
           COUNT_BIG(CASE WHEN status.Code IN ('SUBMITTED','UNDER_REVIEW') THEN 1 END) AS PendingReview
    FROM reg.RegistrationApplications application
    JOIN iam.Users u ON u.UserId=application.UserId
    JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=application.TenantTypeId
    JOIN mst.OnboardingStatuses status ON status.OnboardingStatusId=application.OnboardingStatusId
    WHERE tenantType.Code=@RegistrationTypeCode;
END;
GO

CREATE OR ALTER PROCEDURE reg.usp_ListPlatformRegistrations
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @RegistrationTypeCode VARCHAR(50),
    @Search NVARCHAR(200)=NULL,
    @EmailVerificationStatus VARCHAR(20)=NULL,
    @ApplicationStatus VARCHAR(30)=NULL,
    @PageNumber INT=1,
    @PageSize INT=20
AS
BEGIN
    SET NOCOUNT ON;
    SET @RegistrationTypeCode=UPPER(LTRIM(RTRIM(@RegistrationTypeCode)));
    SET @EmailVerificationStatus=NULLIF(UPPER(LTRIM(RTRIM(@EmailVerificationStatus))),'');
    SET @ApplicationStatus=NULLIF(UPPER(LTRIM(RTRIM(@ApplicationStatus))),'');
    SET @Search=NULLIF(LTRIM(RTRIM(@Search)),N'');

    IF @RegistrationTypeCode NOT IN ('PERSONAL','ORGANIZATION')
        THROW 52910, 'A supported registration type is required.', 1;
    IF @EmailVerificationStatus IS NOT NULL
       AND @EmailVerificationStatus NOT IN ('PENDING','VERIFIED')
        THROW 52911, 'The email verification filter is invalid.', 1;
    IF @ApplicationStatus IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM mst.OnboardingStatuses WHERE Code=@ApplicationStatus)
        THROW 52912, 'The application status filter is invalid.', 1;
    IF @PageNumber IS NULL OR @PageNumber<1 OR @PageNumber>1000000
       OR @PageSize IS NULL OR @PageSize<1 OR @PageSize>100
        THROW 52913, 'The registration page request is invalid.', 1;
    IF @Search IS NOT NULL AND LEN(@Search)>200
        THROW 52914, 'The registration search term is too long.', 1;

    EXEC iam.usp_ValidatePlatformPermission
        @ActorUserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @PermissionCode='platform.registrations.read';

    ;WITH Filtered AS
    (
        SELECT application.ApplicationId,
               u.DisplayName,
               u.Email,
               u.EmailVerifiedAtUtc,
               status.Code AS ApplicationStatus,
               tenantType.Code AS RegistrationType,
               application.CreatedAtUtc AS RegisteredAtUtc
        FROM reg.RegistrationApplications application
        JOIN iam.Users u ON u.UserId=application.UserId
        JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=application.TenantTypeId
        JOIN mst.OnboardingStatuses status ON status.OnboardingStatusId=application.OnboardingStatusId
        WHERE tenantType.Code=@RegistrationTypeCode
          AND (@EmailVerificationStatus IS NULL
               OR (@EmailVerificationStatus='PENDING' AND u.EmailVerifiedAtUtc IS NULL)
               OR (@EmailVerificationStatus='VERIFIED' AND u.EmailVerifiedAtUtc IS NOT NULL))
          AND (@ApplicationStatus IS NULL OR status.Code=@ApplicationStatus)
          AND (@Search IS NULL
               OR CHARINDEX(@Search,u.DisplayName)>0
               OR CHARINDEX(@Search,u.Email)>0
               OR CHARINDEX(@Search,CONVERT(NVARCHAR(20),application.ApplicationId))>0)
    ),
    PageRows AS
    (
        SELECT filtered.*,
               ROW_NUMBER() OVER (ORDER BY filtered.RegisteredAtUtc DESC,filtered.ApplicationId DESC) AS RowNumber
        FROM Filtered filtered
    ),
    Total AS
    (
        SELECT COUNT_BIG(*) AS TotalCount FROM Filtered
    )
    SELECT total.TotalCount,
           CONVERT(INT,CASE WHEN total.TotalCount=0 THEN 0
                            ELSE (total.TotalCount+@PageSize-1)/@PageSize END) AS TotalPages,
           (SELECT statusChoice.Code
            FROM mst.OnboardingStatuses statusChoice
            ORDER BY statusChoice.SortOrder,statusChoice.Code
            FOR JSON PATH) AS ApplicationStatusesJson,
           @PageNumber AS PageNumber,
           @PageSize AS PageSize,
           page.ApplicationId AS RegistrationApplicationId,
           page.DisplayName,
           page.Email,
           page.EmailVerifiedAtUtc,
           page.ApplicationStatus,
           page.RegistrationType,
           page.RegisteredAtUtc
    FROM Total total
    LEFT JOIN PageRows page
        ON page.RowNumber BETWEEN CONVERT(BIGINT,@PageNumber-1)*@PageSize+1
                               AND CONVERT(BIGINT,@PageNumber)*@PageSize
    ORDER BY page.RowNumber;
END;
GO

CREATE OR ALTER PROCEDURE reg.usp_GetPlatformRegistration
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @RegistrationApplicationId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF @RegistrationApplicationId IS NULL OR @RegistrationApplicationId<1
        THROW 52915, 'The registration application identifier is invalid.', 1;

    EXEC iam.usp_ValidatePlatformPermission
        @ActorUserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @PermissionCode='platform.registrations.read';

    SELECT application.ApplicationId AS RegistrationApplicationId,
           u.DisplayName,
           u.Email,
           u.IsActive,
           u.CreatedAtUtc AS UserRegisteredAtUtc,
           u.EmailVerifiedAtUtc,
           tenantType.Code AS RegistrationType,
           status.Code AS ApplicationStatus,
           application.CreatedAtUtc AS ApplicationCreatedAtUtc,
           application.UpdatedAtUtc AS ApplicationUpdatedAtUtc,
           application.TenantId,
           personal.PhoneNumber AS PersonalPhoneNumber,
           personal.CountryCode AS PersonalCountryCode,
           personal.Region AS PersonalRegion,
           personal.City AS PersonalCity,
           personal.PostalCode AS PersonalPostalCode,
           personal.AddressLine AS PersonalAddressLine,
           organizationType.Name AS OrganizationType,
           organization.CountryCode AS OrganizationCountryCode,
           organization.RegisteredName AS OrganizationRegisteredName,
           organization.ContactEmail AS OrganizationContactEmail,
           organization.ContactPhone AS OrganizationContactPhone,
           organization.Region AS OrganizationRegion,
           organization.City AS OrganizationCity,
           organization.PostalCode AS OrganizationPostalCode,
           organization.AddressLine AS OrganizationAddressLine,
           challenge.CreatedAtUtc AS LatestChallengeIssuedAtUtc,
           challenge.ExpiresAtUtc AS LatestChallengeExpiresAtUtc,
           tenant.TenantCode,
           linkedTenantType.Code AS TenantType,
           tenant.DisplayName AS TenantDisplayName,
           tenantStatus.Code AS TenantStatus
    FROM reg.RegistrationApplications application
    JOIN iam.Users u ON u.UserId=application.UserId
    JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=application.TenantTypeId
    JOIN mst.OnboardingStatuses status ON status.OnboardingStatusId=application.OnboardingStatusId
    LEFT JOIN reg.PersonalOnboardingDetails personal ON personal.ApplicationId=application.ApplicationId
    LEFT JOIN reg.OrganizationOnboardingDetails organization ON organization.ApplicationId=application.ApplicationId
    LEFT JOIN mst.OrganizationTypes organizationType
        ON organizationType.OrganizationTypeId=organization.OrganizationTypeId
    OUTER APPLY
    (
        SELECT TOP (1) verificationChallenge.CreatedAtUtc,verificationChallenge.ExpiresAtUtc
        FROM iam.VerificationChallenges verificationChallenge
        JOIN mst.VerificationPurposes purpose
            ON purpose.VerificationPurposeId=verificationChallenge.VerificationPurposeId
        WHERE verificationChallenge.UserId=u.UserId AND purpose.Code='EMAIL_CONFIRMATION'
        ORDER BY verificationChallenge.CreatedAtUtc DESC,verificationChallenge.ChallengeId DESC
    ) challenge
    LEFT JOIN ten.Tenants tenant ON tenant.TenantId=application.TenantId
    LEFT JOIN mst.TenantTypes linkedTenantType ON linkedTenantType.TenantTypeId=tenant.TenantTypeId
    LEFT JOIN mst.TenantStatuses tenantStatus ON tenantStatus.TenantStatusId=tenant.TenantStatusId
    WHERE application.ApplicationId=@RegistrationApplicationId;
END;
GO

CREATE OR ALTER PROCEDURE reg.usp_GetPlatformRegistrationTimeline
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @RegistrationApplicationId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF @RegistrationApplicationId IS NULL OR @RegistrationApplicationId<1
        THROW 52915, 'The registration application identifier is invalid.', 1;

    EXEC iam.usp_ValidatePlatformPermission
        @ActorUserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @PermissionCode='platform.registrations.read';

    DECLARE @UserId BIGINT;
    SELECT @UserId=application.UserId
    FROM reg.RegistrationApplications application
    WHERE application.ApplicationId=@RegistrationApplicationId;
    IF @UserId IS NULL
        THROW 52916, 'The registration application is unavailable.', 1;

    ;WITH Timeline AS
    (
        SELECT history.OccurredAtUtc,
               history.EventCode,
               fromStatus.Code AS FromStatus,
               toStatus.Code AS ToStatus,
               actor.DisplayName AS ActorDisplayName,
               history.HistoryId AS EventId
        FROM reg.RegistrationApplicationHistory history
        JOIN mst.OnboardingStatuses toStatus ON toStatus.OnboardingStatusId=history.ToStatusId
        LEFT JOIN mst.OnboardingStatuses fromStatus ON fromStatus.OnboardingStatusId=history.FromStatusId
        LEFT JOIN iam.Users actor ON actor.UserId=history.ActorUserId
        WHERE history.ApplicationId=@RegistrationApplicationId

        UNION ALL

        SELECT auditEvent.OccurredAtUtc,
               COALESCE(JSON_VALUE(auditEvent.ChangeSummaryJson,'$.EventCode'),
                        JSON_VALUE(auditEvent.ChangeSummaryJson,'$.VerificationState'),
                        actionType.Code) AS EventCode,
               CONVERT(VARCHAR(30),NULL) AS FromStatus,
               CONVERT(VARCHAR(30),NULL) AS ToStatus,
               actor.DisplayName AS ActorDisplayName,
               auditEvent.AuditEventId AS EventId
        FROM aud.AuditEvents auditEvent
        JOIN mst.AuditActionTypes actionType
            ON actionType.AuditActionTypeId=auditEvent.AuditActionTypeId
        LEFT JOIN mst.AuditResultTypes resultType
            ON resultType.AuditResultTypeId=auditEvent.AuditResultTypeId
        LEFT JOIN iam.Users actor ON actor.UserId=auditEvent.ActorUserId
        WHERE resultType.Code='SUCCESS'
          AND
          (
              (auditEvent.ActorService=N'KLOP.PLATFORM.REGISTRATION'
               AND ((auditEvent.TargetType='REGISTRATION_POLICY'
                     AND auditEvent.TargetId=CONVERT(NVARCHAR(150),@RegistrationApplicationId))
                    OR (auditEvent.TargetType='USER'
                        AND auditEvent.TargetId=CONVERT(NVARCHAR(150),@UserId))))
              OR
              (auditEvent.ActorService=N'KLOP.PLATFORM.LEGAL'
               AND auditEvent.TargetType='LEGAL_CONSENT'
               AND EXISTS
               (
                   SELECT 1
                   FROM leg.UserLegalConsents consent
                   WHERE consent.ApplicationId=@RegistrationApplicationId
                     AND auditEvent.TargetId=CONVERT(NVARCHAR(150),consent.ConsentId)
               ))
          )
    )
    SELECT OccurredAtUtc,EventCode,FromStatus,ToStatus,ActorDisplayName
    FROM Timeline
    ORDER BY OccurredAtUtc,EventCode,EventId;
END;
GO
