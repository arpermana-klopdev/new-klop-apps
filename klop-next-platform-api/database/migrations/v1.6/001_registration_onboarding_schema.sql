-- KLOP Platform v1.6 DRAFT additive schema/configuration delta.
-- DBA review and explicit Development approval required. Never run automatically or in Production.
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRY
	BEGIN TRANSACTION;

	IF SCHEMA_ID(N'reg') IS NULL EXEC(N'CREATE SCHEMA reg AUTHORIZATION dbo;');
	IF SCHEMA_ID(N'leg') IS NULL EXEC(N'CREATE SCHEMA leg AUTHORIZATION dbo;');

	CREATE TABLE mst.OnboardingStatuses
	(
		OnboardingStatusId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_mst_OnboardingStatuses PRIMARY KEY,
		Code VARCHAR(30) NOT NULL CONSTRAINT UQ_mst_OnboardingStatuses_Code UNIQUE,
		Name NVARCHAR(100) NOT NULL,
		Description NVARCHAR(500) NULL,
		SortOrder INT NOT NULL,
		IsActive BIT NOT NULL,
		IsSystem BIT NOT NULL,
		CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_mst_OnboardingStatuses_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
		CreatedByUserId BIGINT NULL,
		UpdatedAtUtc DATETIME2(3) NULL,
		UpdatedByUserId BIGINT NULL,
		RowVersion ROWVERSION NOT NULL,
		CONSTRAINT FK_mst_OnboardingStatuses_CreatedByUserId FOREIGN KEY (CreatedByUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT FK_mst_OnboardingStatuses_UpdatedByUserId FOREIGN KEY (UpdatedByUserId) REFERENCES iam.Users(UserId)
	);

	INSERT mst.OnboardingStatuses (Code,Name,Description,SortOrder,IsActive,IsSystem)
	VALUES
		('DRAFT',N'Draft',N'Initial private onboarding draft.',10,1,1),
		('SUBMITTED',N'Submitted',N'Application submitted by its owner.',20,1,1),
		('UNDER_REVIEW',N'Under Review',N'Application is under authorized review.',30,1,1),
		('NEEDS_REVISION',N'Needs Revision',N'Owner action is required before resubmission.',40,1,1),
		('APPROVED',N'Approved',N'Application is approved but not necessarily activated.',50,1,1),
		('REJECTED',N'Rejected',N'Application was rejected by an authorized reviewer.',60,1,1),
		('COMPLETED',N'Completed',N'Approved onboarding completion was finalized.',70,1,1);

	CREATE TABLE reg.RegistrationApplications
	(
		ApplicationId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_reg_RegistrationApplications PRIMARY KEY,
		UserId BIGINT NOT NULL,
		TenantTypeId BIGINT NOT NULL,
		OnboardingStatusId BIGINT NOT NULL,
		TenantId BIGINT NULL,
		IsCurrent BIT NOT NULL CONSTRAINT DF_reg_RegistrationApplications_IsCurrent DEFAULT (1),
		CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_RegistrationApplications_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
		UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_RegistrationApplications_UpdatedAtUtc DEFAULT SYSUTCDATETIME(),
		CompletedAtUtc DATETIME2(3) NULL,
		RequestId VARCHAR(100) NULL,
		CorrelationId UNIQUEIDENTIFIER NULL,
		RowVersion ROWVERSION NOT NULL,
		CONSTRAINT FK_reg_RegistrationApplications_UserId FOREIGN KEY (UserId) REFERENCES iam.Users(UserId),
		CONSTRAINT FK_reg_RegistrationApplications_TenantTypeId FOREIGN KEY (TenantTypeId) REFERENCES mst.TenantTypes(TenantTypeId),
		CONSTRAINT FK_reg_RegistrationApplications_StatusId FOREIGN KEY (OnboardingStatusId) REFERENCES mst.OnboardingStatuses(OnboardingStatusId),
		CONSTRAINT FK_reg_RegistrationApplications_TenantId FOREIGN KEY (TenantId) REFERENCES ten.Tenants(TenantId),
		CONSTRAINT CK_reg_RegistrationApplications_Completion CHECK (CompletedAtUtc IS NULL OR TenantId IS NOT NULL)
	);
	CREATE UNIQUE INDEX UX_reg_RegistrationApplications_UserCurrent
		ON reg.RegistrationApplications(UserId) WHERE IsCurrent=1;
	CREATE INDEX IX_reg_RegistrationApplications_StatusCreated
		ON reg.RegistrationApplications(OnboardingStatusId,CreatedAtUtc DESC,ApplicationId)
		INCLUDE (TenantTypeId,UserId,TenantId,IsCurrent);
	CREATE INDEX IX_reg_RegistrationApplications_UserHistory
		ON reg.RegistrationApplications(UserId,CreatedAtUtc DESC,ApplicationId);

	CREATE TABLE reg.RegistrationApplicationHistory
	(
		HistoryId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_reg_RegistrationApplicationHistory PRIMARY KEY,
		ApplicationId BIGINT NOT NULL,
		FromStatusId BIGINT NULL,
		ToStatusId BIGINT NOT NULL,
		ActorUserId BIGINT NULL,
		EventCode VARCHAR(50) NOT NULL,
		RequestId VARCHAR(100) NULL,
		CorrelationId UNIQUEIDENTIFIER NULL,
		OccurredAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_RegistrationApplicationHistory_OccurredAtUtc DEFAULT SYSUTCDATETIME(),
		CONSTRAINT FK_reg_RegistrationApplicationHistory_ApplicationId FOREIGN KEY (ApplicationId) REFERENCES reg.RegistrationApplications(ApplicationId),
		CONSTRAINT FK_reg_RegistrationApplicationHistory_FromStatusId FOREIGN KEY (FromStatusId) REFERENCES mst.OnboardingStatuses(OnboardingStatusId),
		CONSTRAINT FK_reg_RegistrationApplicationHistory_ToStatusId FOREIGN KEY (ToStatusId) REFERENCES mst.OnboardingStatuses(OnboardingStatusId),
		CONSTRAINT FK_reg_RegistrationApplicationHistory_ActorUserId FOREIGN KEY (ActorUserId) REFERENCES iam.Users(UserId)
	);
	CREATE INDEX IX_reg_RegistrationApplicationHistory_ApplicationTime
		ON reg.RegistrationApplicationHistory(ApplicationId,OccurredAtUtc,HistoryId);

	CREATE TABLE reg.PersonalOnboardingDetails
	(
		ApplicationId BIGINT NOT NULL CONSTRAINT PK_reg_PersonalOnboardingDetails PRIMARY KEY,
		PhoneNumber NVARCHAR(30) NULL,
		CountryCode VARCHAR(2) NULL,
		Region NVARCHAR(120) NULL,
		City NVARCHAR(120) NULL,
		PostalCode NVARCHAR(30) NULL,
		AddressLine NVARCHAR(500) NULL,
		CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_PersonalOnboardingDetails_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
		UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_PersonalOnboardingDetails_UpdatedAtUtc DEFAULT SYSUTCDATETIME(),
		RowVersion ROWVERSION NOT NULL,
		CONSTRAINT FK_reg_PersonalOnboardingDetails_ApplicationId FOREIGN KEY (ApplicationId) REFERENCES reg.RegistrationApplications(ApplicationId),
		CONSTRAINT CK_reg_PersonalOnboardingDetails_CountryCode CHECK (CountryCode IS NULL OR LEN(CountryCode)=2)
	);

	CREATE TABLE reg.OrganizationOnboardingDetails
	(
		ApplicationId BIGINT NOT NULL CONSTRAINT PK_reg_OrganizationOnboardingDetails PRIMARY KEY,
		OrganizationTypeId BIGINT NULL,
		CountryCode VARCHAR(2) NULL,
		RegisteredName NVARCHAR(250) NULL,
		ContactEmail NVARCHAR(320) NULL,
		ContactPhone NVARCHAR(30) NULL,
		Region NVARCHAR(120) NULL,
		City NVARCHAR(120) NULL,
		PostalCode NVARCHAR(30) NULL,
		AddressLine NVARCHAR(500) NULL,
		VerificationStatusId BIGINT NOT NULL,
		CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_OrganizationOnboardingDetails_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
		UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_OrganizationOnboardingDetails_UpdatedAtUtc DEFAULT SYSUTCDATETIME(),
		RowVersion ROWVERSION NOT NULL,
		CONSTRAINT FK_reg_OrganizationOnboardingDetails_ApplicationId FOREIGN KEY (ApplicationId) REFERENCES reg.RegistrationApplications(ApplicationId),
		CONSTRAINT FK_reg_OrganizationOnboardingDetails_OrganizationTypeId FOREIGN KEY (OrganizationTypeId) REFERENCES mst.OrganizationTypes(OrganizationTypeId),
		CONSTRAINT FK_reg_OrganizationOnboardingDetails_VerificationStatusId FOREIGN KEY (VerificationStatusId) REFERENCES mst.VerificationStatuses(VerificationStatusId),
		CONSTRAINT CK_reg_OrganizationOnboardingDetails_CountryCode CHECK (CountryCode IS NULL OR LEN(CountryCode)=2)
	);

	CREATE TABLE reg.ApplicationSupportingDocuments
	(
		SupportingDocumentId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_reg_ApplicationSupportingDocuments PRIMARY KEY,
		ApplicationId BIGINT NOT NULL,
		IdentityDocumentTypeId BIGINT NOT NULL,
		VerificationStatusId BIGINT NOT NULL,
		StorageReference UNIQUEIDENTIFIER NOT NULL,
		ContentHash BINARY(32) NOT NULL,
		MimeType VARCHAR(100) NOT NULL,
		FileSizeBytes BIGINT NOT NULL,
		UploadedByUserId BIGINT NOT NULL,
		UploadedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_reg_ApplicationSupportingDocuments_UploadedAtUtc DEFAULT SYSUTCDATETIME(),
		RowVersion ROWVERSION NOT NULL,
		CONSTRAINT FK_reg_ApplicationSupportingDocuments_ApplicationId FOREIGN KEY (ApplicationId) REFERENCES reg.RegistrationApplications(ApplicationId),
		CONSTRAINT FK_reg_ApplicationSupportingDocuments_DocumentTypeId FOREIGN KEY (IdentityDocumentTypeId) REFERENCES mst.IdentityDocumentTypes(IdentityDocumentTypeId),
		CONSTRAINT FK_reg_ApplicationSupportingDocuments_VerificationStatusId FOREIGN KEY (VerificationStatusId) REFERENCES mst.VerificationStatuses(VerificationStatusId),
		CONSTRAINT FK_reg_ApplicationSupportingDocuments_UploadedByUserId FOREIGN KEY (UploadedByUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT UQ_reg_ApplicationSupportingDocuments_StorageReference UNIQUE (StorageReference),
		CONSTRAINT CK_reg_ApplicationSupportingDocuments_FileSize CHECK (FileSizeBytes>0)
	);
	CREATE INDEX IX_reg_ApplicationSupportingDocuments_Application
		ON reg.ApplicationSupportingDocuments(ApplicationId,IdentityDocumentTypeId,VerificationStatusId);

	CREATE TABLE leg.LegalDocuments
	(
		LegalDocumentId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_leg_LegalDocuments_Id DEFAULT NEWSEQUENTIALID(),
		DocumentTypeCode VARCHAR(50) NOT NULL,
		CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_leg_LegalDocuments_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
		CreatedByUserId BIGINT NULL,
		CONSTRAINT PK_leg_LegalDocuments PRIMARY KEY (LegalDocumentId),
		CONSTRAINT FK_leg_LegalDocuments_CreatedByUserId FOREIGN KEY (CreatedByUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT CK_leg_LegalDocuments_DocumentType CHECK (DocumentTypeCode='TERMS_AND_CONDITIONS')
	);

	CREATE TABLE leg.LegalDocumentVersions
	(
		DocumentVersionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_leg_LegalDocumentVersions_Id DEFAULT NEWSEQUENTIALID(),
		LegalDocumentId UNIQUEIDENTIFIER NOT NULL,
		VersionIdentifier NVARCHAR(50) NOT NULL,
		Title NVARCHAR(300) NOT NULL,
		EffectiveAtUtc DATETIME2(3) NOT NULL,
		PublicationStatus VARCHAR(20) NOT NULL,
		StorageReference NVARCHAR(100) NOT NULL,
		ContentHash BINARY(32) NOT NULL,
		MimeType VARCHAR(100) NOT NULL,
		FileSizeBytes BIGINT NOT NULL,
		CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_leg_LegalDocumentVersions_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
		CreatedByUserId BIGINT NULL,
		ApprovedAtUtc DATETIME2(3) NULL,
		ApprovedByUserId BIGINT NULL,
		PublishedAtUtc DATETIME2(3) NULL,
		PublishedByUserId BIGINT NULL,
		ArchivedAtUtc DATETIME2(3) NULL,
		ArchivedByUserId BIGINT NULL,
		RowVersion ROWVERSION NOT NULL,
		CONSTRAINT PK_leg_LegalDocumentVersions PRIMARY KEY (DocumentVersionId),
		CONSTRAINT FK_leg_LegalDocumentVersions_DocumentId FOREIGN KEY (LegalDocumentId) REFERENCES leg.LegalDocuments(LegalDocumentId),
		CONSTRAINT FK_leg_LegalDocumentVersions_CreatedByUserId FOREIGN KEY (CreatedByUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT FK_leg_LegalDocumentVersions_ApprovedByUserId FOREIGN KEY (ApprovedByUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT FK_leg_LegalDocumentVersions_PublishedByUserId FOREIGN KEY (PublishedByUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT FK_leg_LegalDocumentVersions_ArchivedByUserId FOREIGN KEY (ArchivedByUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT UQ_leg_LegalDocumentVersions_DocumentVersion UNIQUE (LegalDocumentId,VersionIdentifier),
		CONSTRAINT CK_leg_LegalDocumentVersions_State CHECK (PublicationStatus IN ('DRAFT','APPROVED','PUBLISHED','ARCHIVED')),
		CONSTRAINT CK_leg_LegalDocumentVersions_Pdf CHECK (MimeType='application/pdf' AND FileSizeBytes>0),
		CONSTRAINT CK_leg_LegalDocumentVersions_StorageReference CHECK
			(LEN(StorageReference)=32 AND TRY_CONVERT(UNIQUEIDENTIFIER,StorageReference) IS NOT NULL),
		CONSTRAINT CK_leg_LegalDocumentVersions_PublicationDates CHECK
		(
			(PublicationStatus='DRAFT' AND ApprovedAtUtc IS NULL AND PublishedAtUtc IS NULL AND ArchivedAtUtc IS NULL)
			OR (PublicationStatus='APPROVED' AND ApprovedAtUtc IS NOT NULL AND PublishedAtUtc IS NULL AND ArchivedAtUtc IS NULL)
			OR (PublicationStatus='PUBLISHED' AND ApprovedAtUtc IS NOT NULL AND PublishedAtUtc IS NOT NULL AND ArchivedAtUtc IS NULL)
			OR (PublicationStatus='ARCHIVED' AND ApprovedAtUtc IS NOT NULL AND PublishedAtUtc IS NOT NULL AND ArchivedAtUtc IS NOT NULL)
		)
	);
	CREATE INDEX IX_leg_LegalDocumentVersions_Current
		ON leg.LegalDocumentVersions(PublicationStatus,EffectiveAtUtc DESC,PublishedAtUtc DESC)
		INCLUDE (LegalDocumentId,DocumentVersionId,VersionIdentifier,Title,ContentHash,MimeType,FileSizeBytes);

	CREATE TABLE leg.LegalDocumentVersionScopes
	(
		DocumentVersionId UNIQUEIDENTIFIER NOT NULL,
		TenantTypeId BIGINT NOT NULL,
		CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_leg_LegalDocumentVersionScopes_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
		CreatedByUserId BIGINT NULL,
		CONSTRAINT PK_leg_LegalDocumentVersionScopes PRIMARY KEY (DocumentVersionId,TenantTypeId),
		CONSTRAINT FK_leg_LegalDocumentVersionScopes_VersionId FOREIGN KEY (DocumentVersionId) REFERENCES leg.LegalDocumentVersions(DocumentVersionId),
		CONSTRAINT FK_leg_LegalDocumentVersionScopes_TenantTypeId FOREIGN KEY (TenantTypeId) REFERENCES mst.TenantTypes(TenantTypeId),
		CONSTRAINT FK_leg_LegalDocumentVersionScopes_CreatedByUserId FOREIGN KEY (CreatedByUserId) REFERENCES iam.Users(UserId)
	);
	CREATE INDEX IX_leg_LegalDocumentVersionScopes_TenantType ON leg.LegalDocumentVersionScopes(TenantTypeId,DocumentVersionId);

	CREATE TABLE leg.UserLegalConsents
	(
		ConsentId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_leg_UserLegalConsents PRIMARY KEY,
		UserId BIGINT NOT NULL,
		ApplicationId BIGINT NOT NULL,
		TenantTypeId BIGINT NOT NULL,
		DocumentVersionId UNIQUEIDENTIFIER NOT NULL,
		DocumentContentHash BINARY(32) NOT NULL,
		ConsentPurposeCode VARCHAR(50) NOT NULL,
		AcceptedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_leg_UserLegalConsents_AcceptedAtUtc DEFAULT SYSUTCDATETIME(),
		SourceCode VARCHAR(50) NOT NULL,
		RequestId VARCHAR(100) NULL,
		CorrelationId UNIQUEIDENTIFIER NULL,
		CONSTRAINT FK_leg_UserLegalConsents_UserId FOREIGN KEY (UserId) REFERENCES iam.Users(UserId),
		CONSTRAINT FK_leg_UserLegalConsents_ApplicationId FOREIGN KEY (ApplicationId) REFERENCES reg.RegistrationApplications(ApplicationId),
		CONSTRAINT FK_leg_UserLegalConsents_TenantTypeId FOREIGN KEY (TenantTypeId) REFERENCES mst.TenantTypes(TenantTypeId),
		CONSTRAINT FK_leg_UserLegalConsents_DocumentVersionId FOREIGN KEY (DocumentVersionId) REFERENCES leg.LegalDocumentVersions(DocumentVersionId),
		CONSTRAINT UQ_leg_UserLegalConsents_ApplicationVersionPurpose UNIQUE (ApplicationId,DocumentVersionId,ConsentPurposeCode),
		CONSTRAINT CK_leg_UserLegalConsents_Purpose CHECK (ConsentPurposeCode='TERMS_AND_CONDITIONS'),
		CONSTRAINT CK_leg_UserLegalConsents_Source CHECK (SourceCode='PUBLIC_REGISTRATION')
	);
	CREATE INDEX IX_leg_UserLegalConsents_UserAccepted
		ON leg.UserLegalConsents(UserId,AcceptedAtUtc DESC,ConsentId);

	IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WHERE ConfigurationKey='registration.legal_consent_enforcement')
		INSERT cfg.SystemConfigurations
			(ConfigurationKey,ConfigurationValue,ValueType,Category,StorageType,Description,DefaultValue,
			 RequiresApproval,VersionNumber,IsActive,IsSystem,IsEditable,IsSensitive,RequiresRestart,CreatedAtUtc)
		VALUES ('registration.legal_consent_enforcement',N'false','BOOLEAN','Registration','PLAIN',
				N'Enforce current versioned Terms consent during public registration.',N'false',1,1,1,1,0,0,0,SYSUTCDATETIME());

	IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WHERE ConfigurationKey='legal.maximum_upload_bytes')
		INSERT cfg.SystemConfigurations
			(ConfigurationKey,ConfigurationValue,ValueType,Category,StorageType,Description,DefaultValue,
			 MinNumericValue,MaxNumericValue,RequiresApproval,VersionNumber,IsActive,IsSystem,IsEditable,IsSensitive,RequiresRestart,CreatedAtUtc)
		VALUES ('legal.maximum_upload_bytes',N'10485760','INTEGER','Legal','PLAIN',
				N'Maximum approved legal PDF size in bytes.',N'10485760',1,52428800,1,1,1,1,0,0,0,SYSUTCDATETIME());

	IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WHERE ConfigurationKey='onboarding.personal_submission_enabled')
		INSERT cfg.SystemConfigurations
			(ConfigurationKey,ConfigurationValue,ValueType,Category,StorageType,Description,DefaultValue,
			 RequiresApproval,VersionNumber,IsActive,IsSystem,IsEditable,IsSensitive,RequiresRestart,CreatedAtUtc)
		VALUES ('onboarding.personal_submission_enabled',N'false','BOOLEAN','Onboarding','PLAIN',
				N'Enable Personal onboarding submission only after approved validation policy is configured.',N'false',1,1,1,1,0,0,0,SYSUTCDATETIME());

	IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WHERE ConfigurationKey='onboarding.organization_submission_enabled')
		INSERT cfg.SystemConfigurations
			(ConfigurationKey,ConfigurationValue,ValueType,Category,StorageType,Description,DefaultValue,
			 RequiresApproval,VersionNumber,IsActive,IsSystem,IsEditable,IsSensitive,RequiresRestart,CreatedAtUtc)
		VALUES ('onboarding.organization_submission_enabled',N'false','BOOLEAN','Onboarding','PLAIN',
				N'Enable Organization submission only after approved identity and activation policies are configured.',N'false',1,1,1,1,0,0,0,SYSUTCDATETIME());

	IF EXISTS
	(
		SELECT 1 FROM cfg.SystemConfigurations
		WHERE ConfigurationKey IN ('registration.legal_consent_enforcement','legal.maximum_upload_bytes',
								   'onboarding.personal_submission_enabled','onboarding.organization_submission_enabled')
			AND (IsActive<>1 OR StorageType<>'PLAIN' OR IsSystem<>1 OR IsEditable<>0 OR RequiresApproval<>1
			   OR (ConfigurationKey IN ('registration.legal_consent_enforcement',
										 'onboarding.personal_submission_enabled',
										 'onboarding.organization_submission_enabled')
				   AND (ValueType<>'BOOLEAN' OR TRY_CONVERT(BIT,ConfigurationValue)<>0))
			   OR (ConfigurationKey='legal.maximum_upload_bytes'
				   AND (ValueType<>'INTEGER' OR TRY_CONVERT(BIGINT,ConfigurationValue) NOT BETWEEN 1 AND 52428800)))
	)
		THROW 51601, 'A v1.6 configuration key exists with incompatible security metadata.', 1;

	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;
GO
