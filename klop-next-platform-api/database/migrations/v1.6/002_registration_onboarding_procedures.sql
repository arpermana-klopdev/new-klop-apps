-- KLOP Platform v1.6 DRAFT Stored Procedures. DBA review and explicit Development approval required.
-- Extends the existing atomic registration contract and adds owner-scoped onboarding operations.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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
	@RegistrationApplicationId BIGINT = NULL OUTPUT
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

	BEGIN TRY
		BEGIN TRANSACTION;

		SELECT @ConsentEnforcement=TRY_CONVERT(BIT,ConfigurationValue)
		FROM cfg.SystemConfigurations WITH (UPDLOCK,HOLDLOCK)
		WHERE ConfigurationKey='registration.legal_consent_enforcement' AND IsActive=1
		  AND ValueType='BOOLEAN' AND StorageType='PLAIN';
		IF @ConsentEnforcement IS NULL
			THROW 52117, 'Legal registration policy is unavailable.', 1;

		IF @CleanRegistrationType IS NULL
		BEGIN
			IF @TermsDocumentVersionId IS NOT NULL OR @TermsAccepted IS NOT NULL
				THROW 52114, 'Registration consent parameters are inconsistent.', 1;
			IF @ConsentEnforcement=1
				THROW 52115, 'Current Terms consent and registration type are required.', 1;
		END
		ELSE
		BEGIN
			IF @CleanRegistrationType NOT IN ('PERSONAL','ORGANIZATION')
				  OR @TermsDocumentVersionId IS NULL OR ISNULL(@TermsAccepted,0)<>1
				THROW 52114, 'Registration type or Terms consent is invalid.', 1;

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

			SELECT @StatusId=OnboardingStatusId
			FROM mst.OnboardingStatuses WHERE Code='DRAFT' AND IsActive=1;
			IF @StatusId IS NULL
				THROW 52117, 'Onboarding status master is unavailable.', 1;
		END;

		SELECT @PurposeId=VerificationPurposeId FROM mst.VerificationPurposes WHERE Code='EMAIL_CONFIRMATION' AND IsActive=1;
		SELECT @ActionId=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
		SELECT @ResultId=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
		IF @PurposeId IS NULL OR @ActionId IS NULL OR @ResultId IS NULL
			THROW 52112, 'Required masters are unavailable.', 1;
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

		IF @CleanRegistrationType IS NOT NULL
		BEGIN
			INSERT reg.RegistrationApplications
				(UserId,TenantTypeId,OnboardingStatusId,IsCurrent,RequestId,CorrelationId)
			VALUES (@UserId,@TenantTypeId,@StatusId,1,@RequestId,@CorrelationId);
			SET @RegistrationApplicationId=CONVERT(BIGINT,SCOPE_IDENTITY());

			INSERT reg.RegistrationApplicationHistory
				(ApplicationId,FromStatusId,ToStatusId,ActorUserId,EventCode,RequestId,CorrelationId)
			VALUES (@RegistrationApplicationId,NULL,@StatusId,@UserId,'REGISTRATION_ACCEPTED',@RequestId,@CorrelationId);

			INSERT leg.UserLegalConsents
				(UserId,ApplicationId,TenantTypeId,DocumentVersionId,DocumentContentHash,
				 ConsentPurposeCode,AcceptedAtUtc,SourceCode,RequestId,CorrelationId)
			VALUES (@UserId,@RegistrationApplicationId,@TenantTypeId,@CurrentDocumentVersionId,@DocumentHash,
					'TERMS_AND_CONDITIONS',@Now,'PUBLIC_REGISTRATION',@RequestId,@CorrelationId);
			SET @ConsentId=CONVERT(BIGINT,SCOPE_IDENTITY());

			INSERT aud.AuditEvents
				(ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
				 ChangeSummaryJson,RequestId,CorrelationId)
			VALUES (N'KLOP.PLATFORM.LEGAL',@ActionId,@ResultId,'LEGAL_CONSENT',CONVERT(NVARCHAR(150),@ConsentId),
					N'{"purpose":"TERMS_AND_CONDITIONS","source":"PUBLIC_REGISTRATION"}',@RequestId,@CorrelationId);
		END;

		SELECT @Json=(SELECT @UserId AS UserId,'EMAIL_PENDING' AS VerificationState FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
		INSERT aud.AuditEvents
			(ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
			 ChangeSummaryJson,RequestId,CorrelationId)
		VALUES (N'KLOP.PLATFORM.REGISTRATION',@ActionId,@ResultId,'USER',CONVERT(NVARCHAR(150),@UserId),
				@Json,@RequestId,@CorrelationId);

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
CREATE OR ALTER PROCEDURE reg.usp_GetMyApplication
	@UserId BIGINT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT a.ApplicationId,ty.Code AS RegistrationType,s.Code AS OnboardingStatus,
		   a.CreatedAtUtc,a.UpdatedAtUtc,a.CompletedAtUtc,a.TenantId,a.RowVersion
	FROM reg.RegistrationApplications a
	JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
	JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
	WHERE a.UserId=@UserId AND a.IsCurrent=1;
END;
GO
CREATE OR ALTER PROCEDURE reg.usp_GetApplicationForOwner
	@UserId BIGINT,
	@ApplicationId BIGINT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT a.ApplicationId,ty.Code AS RegistrationType,s.Code AS OnboardingStatus,
		   a.CreatedAtUtc,a.UpdatedAtUtc,a.CompletedAtUtc,a.TenantId,a.RowVersion
	FROM reg.RegistrationApplications a
	JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
	JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
	WHERE a.UserId=@UserId AND a.ApplicationId=@ApplicationId;
END;
GO
CREATE OR ALTER PROCEDURE reg.usp_SavePersonalDraft
	@UserId BIGINT,
	@ExpectedRowVersion BINARY(8),
	@PhoneNumber NVARCHAR(30)=NULL,
	@CountryCode VARCHAR(2)=NULL,
	@Region NVARCHAR(120)=NULL,
	@City NVARCHAR(120)=NULL,
	@PostalCode NVARCHAR(30)=NULL,
	@AddressLine NVARCHAR(500)=NULL,
	@RequestId VARCHAR(100)=NULL,
	@CorrelationId UNIQUEIDENTIFIER=NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF @@TRANCOUNT<>0 THROW 52600, 'Procedure must own the transaction.', 1;
	IF @UserId IS NULL OR @ExpectedRowVersion IS NULL THROW 52604, 'Invalid draft parameters.', 1;

	DECLARE @ApplicationId BIGINT,@TenantTypeCode VARCHAR(50),@StatusCode VARCHAR(30),@CurrentVersion BINARY(8);
	DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(),@NoChange BIT=0;
	BEGIN TRY
		BEGIN TRANSACTION;
		IF NOT EXISTS (SELECT 1 FROM iam.Users WITH (UPDLOCK,HOLDLOCK)
					   WHERE UserId=@UserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
			THROW 52602, 'Verified account is required.', 1;
		SELECT @ApplicationId=a.ApplicationId,@TenantTypeCode=ty.Code,@StatusCode=s.Code,
			   @CurrentVersion=a.RowVersion
		FROM reg.RegistrationApplications a WITH (UPDLOCK,HOLDLOCK)
		JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
		JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
		WHERE a.UserId=@UserId AND a.IsCurrent=1;
		IF @ApplicationId IS NULL THROW 52601, 'Application unavailable.', 1;
		IF @TenantTypeCode<>'PERSONAL' THROW 52604, 'Registration type mismatch.', 1;
		IF @StatusCode NOT IN ('DRAFT','NEEDS_REVISION') THROW 52606, 'Draft cannot be changed in this state.', 1;

		IF @CurrentVersion<>@ExpectedRowVersion
		BEGIN
			IF EXISTS (SELECT 1 FROM reg.PersonalOnboardingDetails
					   WHERE ApplicationId=@ApplicationId
						 AND ((PhoneNumber=@PhoneNumber) OR (PhoneNumber IS NULL AND @PhoneNumber IS NULL))
						 AND ((CountryCode=@CountryCode) OR (CountryCode IS NULL AND @CountryCode IS NULL))
						 AND ((Region=@Region) OR (Region IS NULL AND @Region IS NULL))
						 AND ((City=@City) OR (City IS NULL AND @City IS NULL))
						 AND ((PostalCode=@PostalCode) OR (PostalCode IS NULL AND @PostalCode IS NULL))
						 AND ((AddressLine=@AddressLine) OR (AddressLine IS NULL AND @AddressLine IS NULL)))
				SET @NoChange=1;
			ELSE THROW 52603, 'Application changed since it was read.', 1;
		END
		ELSE IF EXISTS (SELECT 1 FROM reg.PersonalOnboardingDetails
						WHERE ApplicationId=@ApplicationId
						  AND ((PhoneNumber=@PhoneNumber) OR (PhoneNumber IS NULL AND @PhoneNumber IS NULL))
						  AND ((CountryCode=@CountryCode) OR (CountryCode IS NULL AND @CountryCode IS NULL))
						  AND ((Region=@Region) OR (Region IS NULL AND @Region IS NULL))
						  AND ((City=@City) OR (City IS NULL AND @City IS NULL))
						  AND ((PostalCode=@PostalCode) OR (PostalCode IS NULL AND @PostalCode IS NULL))
						  AND ((AddressLine=@AddressLine) OR (AddressLine IS NULL AND @AddressLine IS NULL)))
			SET @NoChange=1;

		IF @NoChange=0
		BEGIN
			IF EXISTS (SELECT 1 FROM reg.PersonalOnboardingDetails WHERE ApplicationId=@ApplicationId)
				UPDATE reg.PersonalOnboardingDetails
				   SET PhoneNumber=@PhoneNumber,CountryCode=@CountryCode,Region=@Region,City=@City,
					   PostalCode=@PostalCode,AddressLine=@AddressLine,UpdatedAtUtc=@Now
				 WHERE ApplicationId=@ApplicationId;
			ELSE
				INSERT reg.PersonalOnboardingDetails
					(ApplicationId,PhoneNumber,CountryCode,Region,City,PostalCode,AddressLine)
				VALUES (@ApplicationId,@PhoneNumber,@CountryCode,@Region,@City,@PostalCode,@AddressLine);
			UPDATE reg.RegistrationApplications SET UpdatedAtUtc=@Now WHERE ApplicationId=@ApplicationId;
		END;

		SELECT a.ApplicationId,ty.Code AS RegistrationType,s.Code AS OnboardingStatus,
			   a.CreatedAtUtc,a.UpdatedAtUtc,a.CompletedAtUtc,a.TenantId,a.RowVersion
		FROM reg.RegistrationApplications a
		JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
		JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
		WHERE a.ApplicationId=@ApplicationId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
CREATE OR ALTER PROCEDURE reg.usp_SaveOrganizationDraft
	@UserId BIGINT,
	@ExpectedRowVersion BINARY(8),
	@OrganizationTypeId BIGINT=NULL,
	@CountryCode VARCHAR(2)=NULL,
	@RegisteredName NVARCHAR(250)=NULL,
	@ContactEmail NVARCHAR(320)=NULL,
	@ContactPhone NVARCHAR(30)=NULL,
	@Region NVARCHAR(120)=NULL,
	@City NVARCHAR(120)=NULL,
	@PostalCode NVARCHAR(30)=NULL,
	@AddressLine NVARCHAR(500)=NULL,
	@RequestId VARCHAR(100)=NULL,
	@CorrelationId UNIQUEIDENTIFIER=NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF @@TRANCOUNT<>0 THROW 52600, 'Procedure must own the transaction.', 1;
	IF @UserId IS NULL OR @ExpectedRowVersion IS NULL THROW 52604, 'Invalid draft parameters.', 1;

	DECLARE @ApplicationId BIGINT,@TenantTypeCode VARCHAR(50),@StatusCode VARCHAR(30),@CurrentVersion BINARY(8);
	DECLARE @VerificationStatusId BIGINT,@TypeCountryCode CHAR(2),@Now DATETIME2(3)=SYSUTCDATETIME(),@NoChange BIT=0;
	BEGIN TRY
		BEGIN TRANSACTION;
		IF NOT EXISTS (SELECT 1 FROM iam.Users WITH (UPDLOCK,HOLDLOCK)
					   WHERE UserId=@UserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
			THROW 52602, 'Verified account is required.', 1;
		SELECT @ApplicationId=a.ApplicationId,@TenantTypeCode=ty.Code,@StatusCode=s.Code,
			   @CurrentVersion=a.RowVersion
		FROM reg.RegistrationApplications a WITH (UPDLOCK,HOLDLOCK)
		JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
		JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
		WHERE a.UserId=@UserId AND a.IsCurrent=1;
		IF @ApplicationId IS NULL THROW 52601, 'Application unavailable.', 1;
		IF @TenantTypeCode<>'ORGANIZATION' THROW 52604, 'Registration type mismatch.', 1;
		IF @StatusCode NOT IN ('DRAFT','NEEDS_REVISION') THROW 52606, 'Draft cannot be changed in this state.', 1;

		IF @OrganizationTypeId IS NOT NULL
		BEGIN
			SELECT @TypeCountryCode=CountryCode FROM mst.OrganizationTypes
			WHERE OrganizationTypeId=@OrganizationTypeId AND IsActive=1;
			IF @TypeCountryCode IS NULL THROW 52604, 'Organization type is unavailable.', 1;
			IF @CountryCode IS NOT NULL AND @CountryCode<>@TypeCountryCode
				THROW 52604, 'Country does not match the selected organization type.', 1;
		END;
		SELECT @VerificationStatusId=VerificationStatusId FROM mst.VerificationStatuses
		WHERE Code='UNVERIFIED' AND IsActive=1;
		IF @VerificationStatusId IS NULL THROW 52608, 'Verification status master is unavailable.', 1;

		IF @CurrentVersion<>@ExpectedRowVersion
		BEGIN
			IF EXISTS (SELECT 1 FROM reg.OrganizationOnboardingDetails
					   WHERE ApplicationId=@ApplicationId
						 AND ((OrganizationTypeId=@OrganizationTypeId) OR (OrganizationTypeId IS NULL AND @OrganizationTypeId IS NULL))
						 AND ((CountryCode=@CountryCode) OR (CountryCode IS NULL AND @CountryCode IS NULL))
						 AND ((RegisteredName=@RegisteredName) OR (RegisteredName IS NULL AND @RegisteredName IS NULL))
						 AND ((ContactEmail=@ContactEmail) OR (ContactEmail IS NULL AND @ContactEmail IS NULL))
						 AND ((ContactPhone=@ContactPhone) OR (ContactPhone IS NULL AND @ContactPhone IS NULL))
						 AND ((Region=@Region) OR (Region IS NULL AND @Region IS NULL))
						 AND ((City=@City) OR (City IS NULL AND @City IS NULL))
						 AND ((PostalCode=@PostalCode) OR (PostalCode IS NULL AND @PostalCode IS NULL))
						 AND ((AddressLine=@AddressLine) OR (AddressLine IS NULL AND @AddressLine IS NULL)))
				SET @NoChange=1;
			ELSE THROW 52603, 'Application changed since it was read.', 1;
		END
		ELSE IF EXISTS (SELECT 1 FROM reg.OrganizationOnboardingDetails
						WHERE ApplicationId=@ApplicationId
						  AND ((OrganizationTypeId=@OrganizationTypeId) OR (OrganizationTypeId IS NULL AND @OrganizationTypeId IS NULL))
						  AND ((CountryCode=@CountryCode) OR (CountryCode IS NULL AND @CountryCode IS NULL))
						  AND ((RegisteredName=@RegisteredName) OR (RegisteredName IS NULL AND @RegisteredName IS NULL))
						  AND ((ContactEmail=@ContactEmail) OR (ContactEmail IS NULL AND @ContactEmail IS NULL))
						  AND ((ContactPhone=@ContactPhone) OR (ContactPhone IS NULL AND @ContactPhone IS NULL))
						  AND ((Region=@Region) OR (Region IS NULL AND @Region IS NULL))
						  AND ((City=@City) OR (City IS NULL AND @City IS NULL))
						  AND ((PostalCode=@PostalCode) OR (PostalCode IS NULL AND @PostalCode IS NULL))
						  AND ((AddressLine=@AddressLine) OR (AddressLine IS NULL AND @AddressLine IS NULL)))
			SET @NoChange=1;

		IF @NoChange=0
		BEGIN
			IF EXISTS (SELECT 1 FROM reg.OrganizationOnboardingDetails WHERE ApplicationId=@ApplicationId)
				UPDATE reg.OrganizationOnboardingDetails
				   SET OrganizationTypeId=@OrganizationTypeId,CountryCode=@CountryCode,RegisteredName=@RegisteredName,
					   ContactEmail=@ContactEmail,ContactPhone=@ContactPhone,Region=@Region,City=@City,
					   PostalCode=@PostalCode,AddressLine=@AddressLine,UpdatedAtUtc=@Now
				 WHERE ApplicationId=@ApplicationId;
			ELSE
				INSERT reg.OrganizationOnboardingDetails
					(ApplicationId,OrganizationTypeId,CountryCode,RegisteredName,ContactEmail,ContactPhone,
					 Region,City,PostalCode,AddressLine,VerificationStatusId)
				VALUES (@ApplicationId,@OrganizationTypeId,@CountryCode,@RegisteredName,@ContactEmail,@ContactPhone,
						@Region,@City,@PostalCode,@AddressLine,@VerificationStatusId);
			UPDATE reg.RegistrationApplications SET UpdatedAtUtc=@Now WHERE ApplicationId=@ApplicationId;
		END;

		SELECT a.ApplicationId,ty.Code AS RegistrationType,s.Code AS OnboardingStatus,
			   a.CreatedAtUtc,a.UpdatedAtUtc,a.CompletedAtUtc,a.TenantId,a.RowVersion
		FROM reg.RegistrationApplications a
		JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
		JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
		WHERE a.ApplicationId=@ApplicationId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
CREATE OR ALTER PROCEDURE reg.usp_GetOrganizationRequirements
	@UserId BIGINT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ApplicationId BIGINT,@OrganizationTypeId BIGINT,@CountryCode VARCHAR(2),@Now DATETIME2(3)=SYSUTCDATETIME();
	IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId=@UserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
		THROW 52602, 'Verified account is required.', 1;
	SELECT @ApplicationId=a.ApplicationId,@OrganizationTypeId=o.OrganizationTypeId,
		   @CountryCode=COALESCE(o.CountryCode,ot.CountryCode)
	FROM reg.RegistrationApplications a
	JOIN mst.TenantTypes tt ON tt.TenantTypeId=a.TenantTypeId AND tt.Code='ORGANIZATION'
	LEFT JOIN reg.OrganizationOnboardingDetails o ON o.ApplicationId=a.ApplicationId
	LEFT JOIN mst.OrganizationTypes ot ON ot.OrganizationTypeId=o.OrganizationTypeId
	WHERE a.UserId=@UserId AND a.IsCurrent=1;
	IF @ApplicationId IS NULL THROW 52601, 'Application unavailable.', 1;

	SELECT g.RequirementGroupId,g.Code AS RequirementGroupCode,g.SelectionMode,g.MinimumRequired,
		   idt.IdentityDocumentTypeId,idt.Code AS IdentityDocumentTypeCode,idt.RequiresNumber,idt.AllowsFileUpload,
		   r.RequirementLevel,g.EffectiveFromUtc AS GroupEffectiveFromUtc,g.EffectiveToUtc AS GroupEffectiveToUtc,
		   r.EffectiveFromUtc AS RequirementEffectiveFromUtc,r.EffectiveToUtc AS RequirementEffectiveToUtc
	FROM mst.OrganizationIdentityRequirementGroups g
	JOIN mst.OrganizationIdentityRequirements r ON r.RequirementGroupId=g.RequirementGroupId AND r.IsActive=1
	JOIN mst.IdentityDocumentTypes idt ON idt.IdentityDocumentTypeId=r.IdentityDocumentTypeId AND idt.IsActive=1
	JOIN mst.OrganizationTypes ot ON ot.OrganizationTypeId=g.OrganizationTypeId AND ot.IsActive=1
	WHERE @OrganizationTypeId IS NOT NULL AND g.OrganizationTypeId=@OrganizationTypeId
	  AND (@CountryCode IS NULL OR idt.CountryCode=@CountryCode)
	  AND g.IsActive=1 AND g.EffectiveFromUtc<=@Now AND (g.EffectiveToUtc IS NULL OR g.EffectiveToUtc>@Now)
	  AND r.EffectiveFromUtc<=@Now AND (r.EffectiveToUtc IS NULL OR r.EffectiveToUtc>@Now)
	ORDER BY g.SortOrder,g.RequirementGroupId,idt.SortOrder,idt.IdentityDocumentTypeId;
END;
GO
CREATE OR ALTER PROCEDURE reg.usp_SubmitOnboarding
	@UserId BIGINT,
	@ExpectedRowVersion BINARY(8),
	@RequestId VARCHAR(100)=NULL,
	@CorrelationId UNIQUEIDENTIFIER=NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF @@TRANCOUNT<>0 THROW 52600, 'Procedure must own the transaction.', 1;
	IF @UserId IS NULL OR @ExpectedRowVersion IS NULL THROW 52604, 'Invalid submission parameters.', 1;

	DECLARE @ApplicationId BIGINT,@TenantTypeCode VARCHAR(50),@StatusId BIGINT,@StatusCode VARCHAR(30);
	DECLARE @CurrentVersion BINARY(8),@NextStatusId BIGINT,@Enabled BIT,@ActionId BIGINT,@ResultId BIGINT;
	DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(),@Json NVARCHAR(MAX);
	BEGIN TRY
		BEGIN TRANSACTION;
		IF NOT EXISTS (SELECT 1 FROM iam.Users WITH (UPDLOCK,HOLDLOCK)
					   WHERE UserId=@UserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
			THROW 52602, 'Verified account is required.', 1;
		SELECT @ApplicationId=a.ApplicationId,@TenantTypeCode=ty.Code,@StatusId=a.OnboardingStatusId,
			   @StatusCode=s.Code,@CurrentVersion=a.RowVersion
		FROM reg.RegistrationApplications a WITH (UPDLOCK,HOLDLOCK)
		JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
		JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
		WHERE a.UserId=@UserId AND a.IsCurrent=1;
		IF @ApplicationId IS NULL THROW 52601, 'Application unavailable.', 1;
		IF @StatusCode='SUBMITTED'
		BEGIN
			SELECT a.ApplicationId,ty.Code AS RegistrationType,s.Code AS OnboardingStatus,
				   a.CreatedAtUtc,a.UpdatedAtUtc,a.CompletedAtUtc,a.TenantId,a.RowVersion
			FROM reg.RegistrationApplications a
			JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
			JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
			WHERE a.ApplicationId=@ApplicationId;
			COMMIT TRANSACTION;
			RETURN;
		END;
		IF @StatusCode NOT IN ('DRAFT','NEEDS_REVISION') THROW 52606, 'Application cannot be submitted in this state.', 1;
		IF @CurrentVersion<>@ExpectedRowVersion THROW 52603, 'Application changed since it was read.', 1;

		SELECT @Enabled=TRY_CONVERT(BIT,ConfigurationValue)
		FROM cfg.SystemConfigurations WITH (HOLDLOCK)
		WHERE ConfigurationKey=CASE WHEN @TenantTypeCode='PERSONAL'
									 THEN 'onboarding.personal_submission_enabled'
									 ELSE 'onboarding.organization_submission_enabled' END
		  AND IsActive=1 AND ValueType='BOOLEAN' AND StorageType='PLAIN';
		IF @Enabled IS NULL THROW 52608, 'Onboarding policy is unavailable.', 1;
		IF @Enabled=0 THROW 52605, 'Onboarding submission is not enabled by approved policy.', 1;

		SELECT @NextStatusId=OnboardingStatusId FROM mst.OnboardingStatuses WHERE Code='SUBMITTED' AND IsActive=1;
		SELECT @ActionId=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='UPDATE' AND IsActive=1;
		SELECT @ResultId=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
		IF @NextStatusId IS NULL OR @ActionId IS NULL OR @ResultId IS NULL
			THROW 52608, 'Onboarding status or audit masters are unavailable.', 1;

		UPDATE reg.RegistrationApplications
		   SET OnboardingStatusId=@NextStatusId,UpdatedAtUtc=@Now
		 WHERE ApplicationId=@ApplicationId;
		INSERT reg.RegistrationApplicationHistory
			(ApplicationId,FromStatusId,ToStatusId,ActorUserId,EventCode,RequestId,CorrelationId)
		VALUES (@ApplicationId,@StatusId,@NextStatusId,@UserId,'ONBOARDING_SUBMITTED',@RequestId,@CorrelationId);
		SET @Json=N'{"from":"'+@StatusCode+N'","to":"SUBMITTED"}';
		INSERT aud.AuditEvents
			(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,ChangeSummaryJson,RequestId,CorrelationId)
		VALUES (@UserId,@ActionId,@ResultId,'REGISTRATION_APPLICATION',CONVERT(NVARCHAR(150),@ApplicationId),
				@Json,@RequestId,@CorrelationId);

		SELECT a.ApplicationId,ty.Code AS RegistrationType,s.Code AS OnboardingStatus,
			   a.CreatedAtUtc,a.UpdatedAtUtc,a.CompletedAtUtc,a.TenantId,a.RowVersion
		FROM reg.RegistrationApplications a
		JOIN mst.TenantTypes ty ON ty.TenantTypeId=a.TenantTypeId
		JOIN mst.OnboardingStatuses s ON s.OnboardingStatusId=a.OnboardingStatusId
		WHERE a.ApplicationId=@ApplicationId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
