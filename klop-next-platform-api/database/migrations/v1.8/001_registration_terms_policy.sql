-- KLOP Platform v1.8. DBA review and explicit migration approval required.
-- Adds an explicit, Development-only Terms bypass input to the existing atomic
-- registration procedure. This migration does not change configuration or data.
SET NOCOUNT ON;

IF DB_NAME() <> N'KlopPlatformDB'
    THROW 52800, 'v1.8 registration policy migration requires KlopPlatformDB.', 1;
IF OBJECT_ID(N'iam.usp_RegisterLocalUser', N'P') IS NULL
   OR OBJECT_ID(N'iam.Users', N'U') IS NULL
   OR OBJECT_ID(N'iam.UserCredentials', N'U') IS NULL
   OR OBJECT_ID(N'iam.VerificationChallenges', N'U') IS NULL
   OR OBJECT_ID(N'mst.TenantTypes', N'U') IS NULL
   OR OBJECT_ID(N'mst.OnboardingStatuses', N'U') IS NULL
   OR OBJECT_ID(N'cfg.SystemConfigurations', N'U') IS NULL
   OR OBJECT_ID(N'reg.RegistrationApplications', N'U') IS NULL
   OR OBJECT_ID(N'reg.RegistrationApplicationHistory', N'U') IS NULL
   OR OBJECT_ID(N'leg.LegalDocuments', N'U') IS NULL
   OR OBJECT_ID(N'leg.LegalDocumentVersions', N'U') IS NULL
   OR OBJECT_ID(N'leg.LegalDocumentVersionScopes', N'U') IS NULL
   OR OBJECT_ID(N'leg.UserLegalConsents', N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents', N'U') IS NULL
    THROW 52801, 'v1.8 registration policy prerequisites are incomplete; stop for DBA reconciliation.', 1;
IF NOT EXISTS
(
    SELECT 1
    FROM cfg.SystemConfigurations
    WHERE ConfigurationKey=N'registration.legal_consent_enforcement'
      AND IsActive=1 AND ValueType='BOOLEAN' AND StorageType='PLAIN'
)
    THROW 52802, 'The existing legal consent configuration contract is unavailable.', 1;
GO

CREATE OR ALTER PROCEDURE iam.usp_RegisterLocalUser
    @Email NVARCHAR(320),
    @DisplayName NVARCHAR(150),
    @PasswordHash NVARCHAR(1024),
    @VerificationTokenHash BINARY(32),
    @VerificationExpiresAtUtc DATETIME2(3),
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL,
    @UserId BIGINT OUTPUT,
    @ChallengeId BIGINT OUTPUT,
    @RegistrationTypeCode VARCHAR(50) = NULL,
    @TermsDocumentVersionId UNIQUEIDENTIFIER = NULL,
    @TermsAccepted BIT = NULL,
    @RegistrationApplicationId BIGINT = NULL OUTPUT,
    @DevelopmentTermsBypassEnabled BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52110, 'Procedure must own the transaction.', 1;

    DECLARE @CleanEmail NVARCHAR(320)=LTRIM(RTRIM(@Email));
    DECLARE @NormalizedEmail NVARCHAR(320)=UPPER(@CleanEmail);
    DECLARE @CleanName NVARCHAR(150)=LTRIM(RTRIM(@DisplayName));
    DECLARE @CleanRegistrationType VARCHAR(50)=UPPER(LTRIM(RTRIM(@RegistrationTypeCode)));
    DECLARE @Now DATETIME2(3)=SYSUTCDATETIME();
    DECLARE @PurposeId BIGINT,@ActionId BIGINT,@ResultId BIGINT,@StatusId BIGINT,@TenantTypeId BIGINT;
    DECLARE @ConsentEnforcement BIT,@RegistrationEnabled BIT,@CurrentDocumentVersionId UNIQUEIDENTIFIER;
    DECLARE @DocumentHash BINARY(32),@ConsentId BIGINT,@Json NVARCHAR(MAX);
    SET @UserId=NULL;
    SET @ChallengeId=NULL;
    SET @RegistrationApplicationId=NULL;

    IF @CleanEmail IS NULL OR @CleanEmail=N'' OR @CleanEmail NOT LIKE N'%_@_%._%'
       OR @CleanName IS NULL OR @CleanName=N'' OR @PasswordHash IS NULL OR LEN(@PasswordHash)<50
       OR @VerificationTokenHash IS NULL OR @VerificationExpiresAtUtc IS NULL OR @VerificationExpiresAtUtc<=@Now
        THROW 52111, 'Invalid registration parameters.', 1;

    IF @CleanRegistrationType IS NULL OR @CleanRegistrationType NOT IN ('PERSONAL','ORGANIZATION')
        THROW 52114, 'A supported registration type is required.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @ConsentEnforcement=TRY_CONVERT(BIT,ConfigurationValue)
        FROM cfg.SystemConfigurations WITH (UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey='registration.legal_consent_enforcement' AND IsActive=1
          AND ValueType='BOOLEAN' AND StorageType='PLAIN';
        IF @ConsentEnforcement IS NULL
            THROW 52117, 'Legal registration policy is unavailable.', 1;

        IF @DevelopmentTermsBypassEnabled=1
           AND
           (
               @ConsentEnforcement=1
               OR CONVERT(NVARCHAR(128),SERVERPROPERTY('ServerName'))<>N'DEV-PC\SQLEXPRESS'
               OR DB_NAME()<>N'KlopPlatformDB'
           )
            THROW 52119, 'The Development Terms bypass is not permitted for this database policy or environment.', 1;

        IF @DevelopmentTermsBypassEnabled=1
        BEGIN
            IF @TermsDocumentVersionId IS NOT NULL OR @TermsAccepted IS NOT NULL
                THROW 52114, 'Terms fields must be omitted while the Development Terms bypass is active.', 1;
        END
        ELSE IF @TermsDocumentVersionId IS NULL
             OR @TermsDocumentVersionId='00000000-0000-0000-0000-000000000000'
             OR ISNULL(@TermsAccepted,0)<>1
            THROW 52115, 'Current Terms consent and registration type are required.', 1;

        SELECT @TenantTypeId=TenantTypeId
        FROM mst.TenantTypes WITH (HOLDLOCK)
        WHERE Code=@CleanRegistrationType AND IsActive=1;
        IF @TenantTypeId IS NULL
            THROW 52114, 'Registration type is unavailable.', 1;

        SELECT @RegistrationEnabled=TRY_CONVERT(BIT,ConfigurationValue)
        FROM cfg.SystemConfigurations
        WHERE ConfigurationKey=CONCAT('registration.',LOWER(@CleanRegistrationType),'.enabled')
          AND IsActive=1 AND ValueType='BOOLEAN' AND StorageType='PLAIN';
        IF @RegistrationEnabled IS NULL
            THROW 52117, 'Registration policy is unavailable.', 1;
        IF @RegistrationEnabled=0
            THROW 52118, 'Registration type is disabled.', 1;

        IF @DevelopmentTermsBypassEnabled=0
        BEGIN
            SELECT TOP (1) @CurrentDocumentVersionId=v.DocumentVersionId
            FROM leg.LegalDocumentVersions v WITH (UPDLOCK,HOLDLOCK)
            JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
            JOIN leg.LegalDocumentVersionScopes s ON s.DocumentVersionId=v.DocumentVersionId
            WHERE d.DocumentTypeCode='TERMS_AND_CONDITIONS'
              AND s.TenantTypeId=@TenantTypeId
              AND v.PublicationStatus='PUBLISHED'
              AND v.EffectiveAtUtc<=@Now
            ORDER BY v.EffectiveAtUtc DESC,v.PublishedAtUtc DESC,v.CreatedAtUtc DESC;

            IF @CurrentDocumentVersionId IS NULL OR @CurrentDocumentVersionId<>@TermsDocumentVersionId
                THROW 52116, 'Terms version is not current and applicable.', 1;

            SELECT @DocumentHash=v.ContentHash
            FROM leg.LegalDocumentVersions v WITH (HOLDLOCK)
            WHERE v.DocumentVersionId=@CurrentDocumentVersionId
              AND v.PublicationStatus='PUBLISHED' AND v.EffectiveAtUtc<=@Now;
            IF @DocumentHash IS NULL
                THROW 52116, 'Terms version is not currently effective.', 1;
        END;

        SELECT @StatusId=OnboardingStatusId
        FROM mst.OnboardingStatuses WHERE Code='DRAFT' AND IsActive=1;
        SELECT @PurposeId=VerificationPurposeId
        FROM mst.VerificationPurposes WHERE Code='EMAIL_CONFIRMATION' AND IsActive=1;
        SELECT @ActionId=AuditActionTypeId
        FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
        SELECT @ResultId=AuditResultTypeId
        FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        IF @StatusId IS NULL OR @PurposeId IS NULL OR @ActionId IS NULL OR @ResultId IS NULL
            THROW 52112, 'Required registration masters are unavailable.', 1;

        IF EXISTS (SELECT 1 FROM iam.Users WITH (UPDLOCK,HOLDLOCK) WHERE NormalizedEmail=@NormalizedEmail)
            THROW 52113, 'Email is already registered.', 1;

        INSERT iam.Users (Email,NormalizedEmail,DisplayName,IsActive)
        VALUES (@CleanEmail,@NormalizedEmail,@CleanName,1);
        SET @UserId=CONVERT(BIGINT,SCOPE_IDENTITY());

        INSERT iam.UserCredentials (UserId,PasswordHash)
        VALUES (@UserId,@PasswordHash);

        INSERT iam.VerificationChallenges (UserId,VerificationPurposeId,TokenHash,ExpiresAtUtc)
        VALUES (@UserId,@PurposeId,@VerificationTokenHash,@VerificationExpiresAtUtc);
        SET @ChallengeId=CONVERT(BIGINT,SCOPE_IDENTITY());

        INSERT reg.RegistrationApplications
            (UserId,TenantTypeId,OnboardingStatusId,IsCurrent,RequestId,CorrelationId)
        VALUES (@UserId,@TenantTypeId,@StatusId,1,@RequestId,@CorrelationId);
        SET @RegistrationApplicationId=CONVERT(BIGINT,SCOPE_IDENTITY());

        INSERT reg.RegistrationApplicationHistory
            (ApplicationId,FromStatusId,ToStatusId,ActorUserId,EventCode,RequestId,CorrelationId)
        VALUES (@RegistrationApplicationId,NULL,@StatusId,@UserId,'REGISTRATION_ACCEPTED',@RequestId,@CorrelationId);

        IF @DevelopmentTermsBypassEnabled=0
        BEGIN
            INSERT leg.UserLegalConsents
                (UserId,ApplicationId,TenantTypeId,DocumentVersionId,DocumentContentHash,
                 ConsentPurposeCode,AcceptedAtUtc,SourceCode,RequestId,CorrelationId)
            VALUES (@UserId,@RegistrationApplicationId,@TenantTypeId,@CurrentDocumentVersionId,@DocumentHash,
                    'TERMS_AND_CONDITIONS',@Now,'PUBLIC_REGISTRATION',@RequestId,@CorrelationId);
            SET @ConsentId=CONVERT(BIGINT,SCOPE_IDENTITY());

            INSERT aud.AuditEvents
                (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                 ChangeSummaryJson,RequestId,CorrelationId)
            VALUES (N'KLOP.PLATFORM.LEGAL',@ActionId,@ResultId,'LEGAL_CONSENT',
                    CONVERT(NVARCHAR(150),@ConsentId),
                    N'{"purpose":"TERMS_AND_CONDITIONS","source":"PUBLIC_REGISTRATION"}',
                    @RequestId,@CorrelationId);
        END
        ELSE
        BEGIN
            SELECT @Json=
            (
                SELECT 'TERMS_ENFORCEMENT_BYPASSED' AS EventCode,
                       @CleanRegistrationType AS RegistrationType,
                       CONVERT(BIT,0) AS ConsentRecorded
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER
            );
            INSERT aud.AuditEvents
                (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                 ChangeSummaryJson,RequestId,CorrelationId)
            VALUES (N'KLOP.PLATFORM.REGISTRATION',@ActionId,@ResultId,'REGISTRATION_POLICY',
                    CONVERT(NVARCHAR(150),@RegistrationApplicationId),@Json,@RequestId,@CorrelationId);
        END;

        SELECT @Json=(SELECT @UserId AS UserId,'EMAIL_PENDING' AS VerificationState
                      FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT aud.AuditEvents
            (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
             ChangeSummaryJson,RequestId,CorrelationId)
        VALUES (N'KLOP.PLATFORM.REGISTRATION',@ActionId,@ResultId,'USER',
                CONVERT(NVARCHAR(150),@UserId),@Json,@RequestId,@CorrelationId);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.parameters
    WHERE object_id=OBJECT_ID(N'iam.usp_RegisterLocalUser')
      AND name=N'@DevelopmentTermsBypassEnabled'
      AND system_type_id=TYPE_ID(N'bit')
)
    THROW 52803, 'v1.8 registration policy procedure signature validation failed.', 1;
SELECT N'REVIEW ONLY: procedure definition is prepared; no configuration or registration data changed.' AS Status;
GO
