-- KLOP Platform v1.7 additive legal-document administration delta.
-- DBA review and manual approval are required. This script has not been executed.
-- It creates no users or roles and does not assign any PlatformRoleAssignments.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'KlopPlatformDB'
	THROW 52799, 'This approval script is restricted to KlopPlatformDB Development.', 1;
IF OBJECT_ID(N'iam.PlatformRoleAssignments',N'U') IS NULL OR
   OBJECT_ID(N'mst.RoleScopes',N'U') IS NULL OR
   OBJECT_ID(N'mst.RolePermissions',N'U') IS NULL OR
   OBJECT_ID(N'leg.LegalDocumentVersions',N'U') IS NULL OR
   OBJECT_ID(N'leg.LegalDocumentVersionScopes',N'U') IS NULL OR
   OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
	THROW 52798, 'A verified v1.6 IAM, legal, or audit object is missing.', 1;
IF NOT EXISTS (SELECT 1 FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1)
	THROW 52797, 'The existing PLATFORM role scope is unavailable.', 1;
IF NOT EXISTS (SELECT 1 FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
	WHERE r.Code='SUPER_ADMIN' AND s.Code='PLATFORM' AND r.IsActive=1)
	THROW 52796, 'The existing PLATFORM SUPER_ADMIN role is unavailable.', 1;
IF NOT EXISTS (SELECT 1 FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
	WHERE r.Code='PLATFORM_SUPPORT' AND s.Code='PLATFORM' AND r.IsActive=1)
	THROW 52795, 'The existing PLATFORM_SUPPORT role is unavailable.', 1;

BEGIN TRANSACTION;

IF COL_LENGTH(N'leg.LegalDocumentVersions',N'SubmittedAtUtc') IS NULL
	ALTER TABLE leg.LegalDocumentVersions ADD SubmittedAtUtc DATETIME2(3) NULL;
IF COL_LENGTH(N'leg.LegalDocumentVersions',N'SubmittedByUserId') IS NULL
	ALTER TABLE leg.LegalDocumentVersions ADD SubmittedByUserId BIGINT NULL;
IF NOT EXISTS
(
	SELECT 1 FROM sys.foreign_keys
	WHERE parent_object_id=OBJECT_ID(N'leg.LegalDocumentVersions')
	  AND name=N'FK_leg_LegalDocumentVersions_SubmittedByUserId'
)
	ALTER TABLE leg.LegalDocumentVersions
		ADD CONSTRAINT FK_leg_LegalDocumentVersions_SubmittedByUserId
		FOREIGN KEY (SubmittedByUserId) REFERENCES iam.Users(UserId);

IF OBJECT_ID(N'leg.LegalDocumentApprovalDecisions',N'U') IS NULL
BEGIN
	CREATE TABLE leg.LegalDocumentApprovalDecisions
	(
		ApprovalDecisionId BIGINT IDENTITY(1,1) NOT NULL
			CONSTRAINT PK_leg_LegalDocumentApprovalDecisions PRIMARY KEY,
		DocumentVersionId UNIQUEIDENTIFIER NOT NULL,
		ReviewerUserId BIGINT NOT NULL,
		DecisionCode VARCHAR(20) NOT NULL,
		DecisionNote NVARCHAR(1000) NULL,
		DecidedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_leg_LegalDocumentApprovalDecisions_DecidedAtUtc
			DEFAULT SYSUTCDATETIME(),
		RequestId VARCHAR(100) NULL,
		CorrelationId UNIQUEIDENTIFIER NULL,
		CONSTRAINT FK_leg_LegalDocumentApprovalDecisions_VersionId
			FOREIGN KEY (DocumentVersionId) REFERENCES leg.LegalDocumentVersions(DocumentVersionId),
		CONSTRAINT FK_leg_LegalDocumentApprovalDecisions_ReviewerUserId
			FOREIGN KEY (ReviewerUserId) REFERENCES iam.Users(UserId),
		CONSTRAINT CK_leg_LegalDocumentApprovalDecisions_Decision
			CHECK (DecisionCode IN ('APPROVED','REJECTED'))
	);
	CREATE INDEX IX_leg_LegalDocumentApprovalDecisions_Version
		ON leg.LegalDocumentApprovalDecisions(DocumentVersionId,DecidedAtUtc DESC,ApprovalDecisionId DESC);
END;

IF EXISTS
(
	SELECT 1 FROM mst.Permissions p
	JOIN mst.RoleScopes s ON s.RoleScopeId=p.RoleScopeId
	WHERE p.Code IN
	(
		'platform.legal_documents.read',
		'platform.legal_documents.draft.create',
		'platform.legal_documents.draft.edit',
		'platform.legal_documents.draft.preview',
		'platform.legal_documents.submit',
		'platform.legal_documents.approve',
		'platform.legal_documents.publish',
		'platform.legal_documents.archive'
	) AND s.Code<>'PLATFORM'
)
	THROW 52794, 'A legal-document permission code already exists outside PLATFORM scope.', 1;

DECLARE @PlatformScopeId BIGINT=
	(SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1);
DECLARE @SuperAdminRoleId BIGINT=
	(SELECT r.RoleId FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
	 WHERE r.Code='SUPER_ADMIN' AND s.Code='PLATFORM' AND r.IsActive=1);
DECLARE @PlatformSupportRoleId BIGINT=
	(SELECT r.RoleId FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId
	 WHERE r.Code='PLATFORM_SUPPORT' AND s.Code='PLATFORM' AND r.IsActive=1);

DECLARE @LegalPermissions TABLE
(
	Code VARCHAR(150) NOT NULL PRIMARY KEY,
	Name NVARCHAR(300) NOT NULL,
	Description NVARCHAR(1000) NOT NULL,
	SortOrder INT NOT NULL
);
INSERT @LegalPermissions(Code,Name,Description,SortOrder) VALUES
	('platform.legal_documents.read',N'Read legal documents',N'Read Platform legal document metadata and version history.',710),
	('platform.legal_documents.draft.create',N'Create legal document drafts',N'Upload a legal document as a draft version.',711),
	('platform.legal_documents.draft.edit',N'Edit legal document drafts',N'Edit metadata and scopes on a draft version.',712),
	('platform.legal_documents.draft.preview',N'Preview legal document drafts',N'Preview private draft and pending-approval PDF files.',713),
	('platform.legal_documents.submit',N'Submit legal documents',N'Submit a validated draft for approval.',714),
	('platform.legal_documents.approve',N'Approve legal documents',N'Approve or reject a submitted legal document.',715),
	('platform.legal_documents.publish',N'Publish legal documents',N'Publish an approved legal document version.',716),
	('platform.legal_documents.archive',N'Archive legal documents',N'Archive a superseded published legal document version.',717);

INSERT mst.Permissions
	(RoleScopeId,Code,Name,Description,SortOrder,IsActive,IsSystem,CreatedAtUtc)
SELECT @PlatformScopeId,p.Code,p.Name,p.Description,p.SortOrder,1,1,SYSUTCDATETIME()
FROM @LegalPermissions p
WHERE NOT EXISTS
(
	SELECT 1 FROM mst.Permissions existing
	WHERE existing.RoleScopeId=@PlatformScopeId AND existing.Code=p.Code
);

INSERT mst.RolePermissions(RoleId,PermissionId,CreatedAtUtc)
SELECT @SuperAdminRoleId,p.PermissionId,SYSUTCDATETIME()
FROM mst.Permissions p
WHERE p.RoleScopeId=@PlatformScopeId
  AND p.Code IN (SELECT Code FROM @LegalPermissions)
  AND NOT EXISTS
	(SELECT 1 FROM mst.RolePermissions rp WHERE rp.RoleId=@SuperAdminRoleId AND rp.PermissionId=p.PermissionId);

-- Support receives draft-only capabilities; submit, approve, publish, and archive are intentionally excluded.
INSERT mst.RolePermissions(RoleId,PermissionId,CreatedAtUtc)
SELECT @PlatformSupportRoleId,p.PermissionId,SYSUTCDATETIME()
FROM mst.Permissions p
WHERE p.RoleScopeId=@PlatformScopeId
  AND p.Code IN
	('platform.legal_documents.read','platform.legal_documents.draft.create',
	 'platform.legal_documents.draft.edit','platform.legal_documents.draft.preview')
  AND NOT EXISTS
	(SELECT 1 FROM mst.RolePermissions rp WHERE rp.RoleId=@PlatformSupportRoleId AND rp.PermissionId=p.PermissionId);

DECLARE @AuditActions TABLE
(
	Code VARCHAR(50) NOT NULL PRIMARY KEY,
	Name NVARCHAR(300) NOT NULL,
	Description NVARCHAR(1000) NOT NULL,
	SortOrder INT NOT NULL
);
INSERT @AuditActions(Code,Name,Description,SortOrder) VALUES
	('LEGAL_DOCUMENT_CREATED',N'Legal document draft created',N'A legal document draft version was created.',710),
	('LEGAL_DOCUMENT_UPDATED',N'Legal document draft updated',N'Legal document draft metadata or scope was updated.',711),
	('LEGAL_DOCUMENT_SUBMITTED',N'Legal document submitted',N'A legal document draft was submitted for approval.',712),
	('LEGAL_DOCUMENT_APPROVED',N'Legal document approved',N'A legal document version was approved.',713),
	('LEGAL_DOCUMENT_REJECTED',N'Legal document rejected',N'A legal document version was rejected.',714),
	('LEGAL_DOCUMENT_PUBLISHED',N'Legal document published',N'An approved legal document version was published.',715),
	('LEGAL_DOCUMENT_ARCHIVED',N'Legal document archived',N'A superseded legal document version was archived.',716);

INSERT mst.AuditActionTypes(Code,Name,Description,SortOrder,IsActive,IsSystem,CreatedAtUtc)
SELECT a.Code,a.Name,a.Description,a.SortOrder,1,1,SYSUTCDATETIME()
FROM @AuditActions a
WHERE NOT EXISTS (SELECT 1 FROM mst.AuditActionTypes existing WHERE existing.Code=a.Code);

IF EXISTS (SELECT 1 FROM sys.check_constraints
	WHERE parent_object_id=OBJECT_ID(N'leg.LegalDocumentVersions')
	  AND name=N'CK_leg_LegalDocumentVersions_State')
	ALTER TABLE leg.LegalDocumentVersions DROP CONSTRAINT CK_leg_LegalDocumentVersions_State;
IF EXISTS (SELECT 1 FROM sys.check_constraints
	WHERE parent_object_id=OBJECT_ID(N'leg.LegalDocumentVersions')
	  AND name=N'CK_leg_LegalDocumentVersions_PublicationDates')
	ALTER TABLE leg.LegalDocumentVersions DROP CONSTRAINT CK_leg_LegalDocumentVersions_PublicationDates;

ALTER TABLE leg.LegalDocumentVersions WITH CHECK
	ADD CONSTRAINT CK_leg_LegalDocumentVersions_State
	CHECK
	(
		(PublicationStatus='DRAFT' AND ApprovedAtUtc IS NULL AND PublishedAtUtc IS NULL AND ArchivedAtUtc IS NULL)
		OR
		(PublicationStatus='PENDING_APPROVAL' AND SubmittedAtUtc IS NOT NULL AND
		 ApprovedAtUtc IS NULL AND PublishedAtUtc IS NULL AND ArchivedAtUtc IS NULL)
		OR
		(PublicationStatus='APPROVED' AND ApprovedAtUtc IS NOT NULL AND PublishedAtUtc IS NULL AND ArchivedAtUtc IS NULL)
		OR
		(PublicationStatus='PUBLISHED' AND ApprovedAtUtc IS NOT NULL AND PublishedAtUtc IS NOT NULL AND ArchivedAtUtc IS NULL)
		OR
		(PublicationStatus='ARCHIVED' AND ApprovedAtUtc IS NOT NULL AND PublishedAtUtc IS NOT NULL AND ArchivedAtUtc IS NOT NULL)
	);
ALTER TABLE leg.LegalDocumentVersions CHECK CONSTRAINT CK_leg_LegalDocumentVersions_State;
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
		'platform.legal_documents.archive'
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
		'platform.legal_documents.archive'
	  )
	ORDER BY permission.Code;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_ListLegalDocuments
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.read';

	SELECT d.LegalDocumentId,v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		v.EffectiveAtUtc,v.PublicationStatus,v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes,
		v.CreatedAtUtc,v.SubmittedAtUtc,v.ApprovedAtUtc,v.PublishedAtUtc,v.ArchivedAtUtc,
		latest.DecisionCode AS LatestApprovalDecisionCode,latest.DecidedAtUtc AS LatestApprovalDecisionAtUtc,
		latest.DecisionNote AS LatestApprovalDecisionNote,v.RowVersion,tenantType.Code AS RegistrationScopeCode
	FROM leg.LegalDocuments d
	JOIN leg.LegalDocumentVersions v ON v.LegalDocumentId=d.LegalDocumentId
	LEFT JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=scope.TenantTypeId
	OUTER APPLY
	(
		SELECT TOP (1) decision.DecisionCode,decision.DecidedAtUtc,decision.DecisionNote
		FROM leg.LegalDocumentApprovalDecisions decision
		WHERE decision.DocumentVersionId=v.DocumentVersionId
		ORDER BY decision.DecidedAtUtc DESC,decision.ApprovalDecisionId DESC
	) latest
	WHERE d.DocumentTypeCode='TERMS_AND_CONDITIONS'
	ORDER BY d.CreatedAtUtc DESC,v.CreatedAtUtc DESC,tenantType.Code;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_GetLegalDocument
	@LegalDocumentId UNIQUEIDENTIFIER,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.read';

	SELECT d.LegalDocumentId,v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		v.EffectiveAtUtc,v.PublicationStatus,v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes,
		v.CreatedAtUtc,v.SubmittedAtUtc,v.ApprovedAtUtc,v.PublishedAtUtc,v.ArchivedAtUtc,
		latest.DecisionCode AS LatestApprovalDecisionCode,latest.DecidedAtUtc AS LatestApprovalDecisionAtUtc,
		latest.DecisionNote AS LatestApprovalDecisionNote,v.RowVersion,tenantType.Code AS RegistrationScopeCode
	FROM leg.LegalDocuments d
	JOIN leg.LegalDocumentVersions v ON v.LegalDocumentId=d.LegalDocumentId
	LEFT JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=scope.TenantTypeId
	OUTER APPLY
	(
		SELECT TOP (1) decision.DecisionCode,decision.DecidedAtUtc,decision.DecisionNote
		FROM leg.LegalDocumentApprovalDecisions decision
		WHERE decision.DocumentVersionId=v.DocumentVersionId
		ORDER BY decision.DecidedAtUtc DESC,decision.ApprovalDecisionId DESC
	) latest
	WHERE d.LegalDocumentId=@LegalDocumentId AND d.DocumentTypeCode='TERMS_AND_CONDITIONS'
	ORDER BY v.CreatedAtUtc DESC,tenantType.Code;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_GetLegalDocumentVersion
	@DocumentVersionId UNIQUEIDENTIFIER,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.read';

	SELECT d.LegalDocumentId,v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		v.EffectiveAtUtc,v.PublicationStatus,v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes,
		v.CreatedAtUtc,v.SubmittedAtUtc,v.ApprovedAtUtc,v.PublishedAtUtc,v.ArchivedAtUtc,
		latest.DecisionCode AS LatestApprovalDecisionCode,latest.DecidedAtUtc AS LatestApprovalDecisionAtUtc,
		latest.DecisionNote AS LatestApprovalDecisionNote,v.RowVersion,tenantType.Code AS RegistrationScopeCode
	FROM leg.LegalDocuments d
	JOIN leg.LegalDocumentVersions v ON v.LegalDocumentId=d.LegalDocumentId
	LEFT JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=scope.TenantTypeId
	OUTER APPLY
	(
		SELECT TOP (1) decision.DecisionCode,decision.DecidedAtUtc,decision.DecisionNote
		FROM leg.LegalDocumentApprovalDecisions decision
		WHERE decision.DocumentVersionId=v.DocumentVersionId
		ORDER BY decision.DecidedAtUtc DESC,decision.ApprovalDecisionId DESC
	) latest
	WHERE v.DocumentVersionId=@DocumentVersionId AND d.DocumentTypeCode='TERMS_AND_CONDITIONS'
	ORDER BY tenantType.Code;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_GetLegalDocumentPreview
	@DocumentVersionId UNIQUEIDENTIFIER,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.draft.preview';

	SELECT d.LegalDocumentId,v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		v.EffectiveAtUtc,v.PublicationStatus,v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes,
		v.CreatedAtUtc,v.SubmittedAtUtc,v.ApprovedAtUtc,v.PublishedAtUtc,v.ArchivedAtUtc,
		latest.DecisionCode AS LatestApprovalDecisionCode,latest.DecidedAtUtc AS LatestApprovalDecisionAtUtc,
		latest.DecisionNote AS LatestApprovalDecisionNote,v.RowVersion,tenantType.Code AS RegistrationScopeCode
	FROM leg.LegalDocuments d
	JOIN leg.LegalDocumentVersions v ON v.LegalDocumentId=d.LegalDocumentId
	LEFT JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=scope.TenantTypeId
	OUTER APPLY
	(
		SELECT TOP (1) decision.DecisionCode,decision.DecidedAtUtc,decision.DecisionNote
		FROM leg.LegalDocumentApprovalDecisions decision
		WHERE decision.DocumentVersionId=v.DocumentVersionId
		ORDER BY decision.DecidedAtUtc DESC,decision.ApprovalDecisionId DESC
	) latest
	WHERE v.DocumentVersionId=@DocumentVersionId AND d.DocumentTypeCode='TERMS_AND_CONDITIONS'
	  AND v.PublicationStatus IN ('DRAFT','PENDING_APPROVAL','APPROVED')
	ORDER BY tenantType.Code;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_CreateLegalDocumentDraft
	@LegalDocumentId UNIQUEIDENTIFIER=NULL,
	@Title NVARCHAR(300),
	@VersionIdentifier NVARCHAR(50),
	@EffectiveAtUtc DATETIME2(3),
	@PersonalScope BIT,
	@OrganizationScope BIT,
	@StorageReference NVARCHAR(32),
	@ContentHash BINARY(32),
	@MimeType VARCHAR(100),
	@FileSizeBytes BIGINT,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER,
	@RequestId VARCHAR(100),
	@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.draft.create';
	IF NULLIF(LTRIM(RTRIM(@Title)),N'') IS NULL OR LEN(@Title)>300 OR
	   NULLIF(LTRIM(RTRIM(@VersionIdentifier)),N'') IS NULL OR LEN(@VersionIdentifier)>50 OR
	   (@PersonalScope=0 AND @OrganizationScope=0) OR @MimeType<>'application/pdf' OR
	   @FileSizeBytes<=0 OR LEN(@StorageReference)<>32 OR TRY_CONVERT(UNIQUEIDENTIFIER,@StorageReference) IS NULL
		THROW 52701, 'Legal document metadata is invalid.', 1;

	DECLARE @MaximumBytes BIGINT;
	SELECT @MaximumBytes=TRY_CONVERT(BIGINT,ConfigurationValue)
	FROM cfg.SystemConfigurations
	WHERE ConfigurationKey='legal.maximum_upload_bytes' AND IsActive=1
	  AND StorageType='PLAIN' AND ValueType='INTEGER';
	IF @MaximumBytes IS NULL OR @MaximumBytes<=0 OR @MaximumBytes>52428800 OR @FileSizeBytes>@MaximumBytes
		THROW 52705, 'Legal document upload policy is unavailable.', 1;
	IF (@PersonalScope=1 AND NOT EXISTS
		(SELECT 1 FROM mst.TenantTypes WHERE Code='PERSONAL' AND IsActive=1)) OR
	   (@OrganizationScope=1 AND NOT EXISTS
		(SELECT 1 FROM mst.TenantTypes WHERE Code='ORGANIZATION' AND IsActive=1))
		THROW 52701, 'A requested registration scope is unavailable.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @ResolvedDocumentId UNIQUEIDENTIFIER=@LegalDocumentId;
		IF @ResolvedDocumentId IS NULL
		BEGIN
			SET @ResolvedDocumentId=NEWID();
			INSERT leg.LegalDocuments(LegalDocumentId,DocumentTypeCode,CreatedByUserId)
				VALUES(@ResolvedDocumentId,'TERMS_AND_CONDITIONS',@ActorUserId);
		END
		ELSE IF NOT EXISTS
			(SELECT 1 FROM leg.LegalDocuments WITH (UPDLOCK,HOLDLOCK)
			 WHERE LegalDocumentId=@ResolvedDocumentId AND DocumentTypeCode='TERMS_AND_CONDITIONS')
			THROW 52702, 'The legal document is unavailable.', 1;

		DECLARE @DocumentVersionId UNIQUEIDENTIFIER=NEWID();
		INSERT leg.LegalDocumentVersions
			(DocumentVersionId,LegalDocumentId,VersionIdentifier,Title,EffectiveAtUtc,PublicationStatus,
			 StorageReference,ContentHash,MimeType,FileSizeBytes,CreatedByUserId)
		VALUES
			(@DocumentVersionId,@ResolvedDocumentId,@VersionIdentifier,@Title,@EffectiveAtUtc,'DRAFT',
			 @StorageReference,@ContentHash,@MimeType,@FileSizeBytes,@ActorUserId);

		INSERT leg.LegalDocumentVersionScopes(DocumentVersionId,TenantTypeId,CreatedByUserId)
		SELECT @DocumentVersionId,TenantTypeId,@ActorUserId
		FROM mst.TenantTypes
		WHERE IsActive=1 AND ((Code='PERSONAL' AND @PersonalScope=1)
			OR (Code='ORGANIZATION' AND @OrganizationScope=1));

		INSERT aud.AuditEvents
			(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
			 ChangeSummaryJson,RequestId,CorrelationId)
		SELECT @ActorUserId,actionType.AuditActionTypeId,resultType.AuditResultTypeId,
			'LEGAL_DOCUMENT_VERSION',CONVERT(NVARCHAR(150),@DocumentVersionId),
			N'{"action":"LEGAL_DOCUMENT_CREATED"}',@RequestId,@CorrelationId
		FROM mst.AuditActionTypes actionType
		CROSS JOIN mst.AuditResultTypes resultType
		WHERE actionType.Code='LEGAL_DOCUMENT_CREATED' AND actionType.IsActive=1
		  AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
		IF @@ROWCOUNT<>1 THROW 52706, 'Legal document audit configuration is unavailable.', 1;

		COMMIT TRANSACTION;
		SELECT d.LegalDocumentId,v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
			v.EffectiveAtUtc,v.PublicationStatus,v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes,
			v.CreatedAtUtc,v.SubmittedAtUtc,v.ApprovedAtUtc,v.PublishedAtUtc,v.ArchivedAtUtc,
			CAST(NULL AS VARCHAR(20)) AS LatestApprovalDecisionCode,
			CAST(NULL AS DATETIME2(3)) AS LatestApprovalDecisionAtUtc,
			CAST(NULL AS NVARCHAR(1000)) AS LatestApprovalDecisionNote,
			v.RowVersion,tenantType.Code AS RegistrationScopeCode
		FROM leg.LegalDocuments d
		JOIN leg.LegalDocumentVersions v ON v.LegalDocumentId=d.LegalDocumentId
		JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
		JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=scope.TenantTypeId
		WHERE v.DocumentVersionId=@DocumentVersionId
		ORDER BY tenantType.Code;
	END TRY
	BEGIN CATCH
		IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_UpdateLegalDocumentDraft
	@DocumentVersionId UNIQUEIDENTIFIER,
	@Title NVARCHAR(300),
	@VersionIdentifier NVARCHAR(50),
	@EffectiveAtUtc DATETIME2(3),
	@PersonalScope BIT,
	@OrganizationScope BIT,
	@ExpectedRowVersion BINARY(8),
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER,
	@RequestId VARCHAR(100),
	@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.draft.edit';
	IF NULLIF(LTRIM(RTRIM(@Title)),N'') IS NULL OR LEN(@Title)>300 OR
	   NULLIF(LTRIM(RTRIM(@VersionIdentifier)),N'') IS NULL OR LEN(@VersionIdentifier)>50 OR
	   (@PersonalScope=0 AND @OrganizationScope=0)
		THROW 52701, 'Legal document metadata is invalid.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @CurrentRowVersion BINARY(8),@CurrentState VARCHAR(20);
		SELECT @CurrentRowVersion=RowVersion,@CurrentState=PublicationStatus
		FROM leg.LegalDocumentVersions WITH (UPDLOCK,HOLDLOCK)
		WHERE DocumentVersionId=@DocumentVersionId;
		IF @CurrentRowVersion IS NULL THROW 52702, 'The legal document is unavailable.', 1;
		IF @CurrentState<>'DRAFT' THROW 52703, 'Only DRAFT legal documents can be edited.', 1;
		IF @CurrentRowVersion<>@ExpectedRowVersion
			THROW 52704, 'The legal document draft has changed.', 1;
		IF (@PersonalScope=1 AND NOT EXISTS
			(SELECT 1 FROM mst.TenantTypes WHERE Code='PERSONAL' AND IsActive=1)) OR
		   (@OrganizationScope=1 AND NOT EXISTS
			(SELECT 1 FROM mst.TenantTypes WHERE Code='ORGANIZATION' AND IsActive=1))
			THROW 52701, 'A requested registration scope is unavailable.', 1;

		UPDATE leg.LegalDocumentVersions
		SET Title=@Title,VersionIdentifier=@VersionIdentifier,EffectiveAtUtc=@EffectiveAtUtc
		WHERE DocumentVersionId=@DocumentVersionId AND PublicationStatus='DRAFT'
		  AND RowVersion=@ExpectedRowVersion;
		IF @@ROWCOUNT<>1 THROW 52704, 'The legal document draft has changed.', 1;

		DELETE FROM leg.LegalDocumentVersionScopes WHERE DocumentVersionId=@DocumentVersionId;
		INSERT leg.LegalDocumentVersionScopes(DocumentVersionId,TenantTypeId,CreatedByUserId)
		SELECT @DocumentVersionId,TenantTypeId,@ActorUserId
		FROM mst.TenantTypes
		WHERE IsActive=1 AND ((Code='PERSONAL' AND @PersonalScope=1)
			OR (Code='ORGANIZATION' AND @OrganizationScope=1));

		INSERT aud.AuditEvents
			(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
			 ChangeSummaryJson,RequestId,CorrelationId)
		SELECT @ActorUserId,actionType.AuditActionTypeId,resultType.AuditResultTypeId,
			'LEGAL_DOCUMENT_VERSION',CONVERT(NVARCHAR(150),@DocumentVersionId),
			N'{"action":"LEGAL_DOCUMENT_UPDATED"}',@RequestId,@CorrelationId
		FROM mst.AuditActionTypes actionType
		CROSS JOIN mst.AuditResultTypes resultType
		WHERE actionType.Code='LEGAL_DOCUMENT_UPDATED' AND actionType.IsActive=1
		  AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
		IF @@ROWCOUNT<>1 THROW 52706, 'Legal document audit configuration is unavailable.', 1;
		COMMIT TRANSACTION;

		EXEC leg.usp_GetLegalDocumentVersion @DocumentVersionId,@ActorUserId,@PublicSessionId;
	END TRY
	BEGIN CATCH
		IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_SubmitLegalDocument
	@DocumentVersionId UNIQUEIDENTIFIER,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER,
	@RequestId VARCHAR(100),
	@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.submit';

	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @CurrentState VARCHAR(20),@FileSizeBytes BIGINT,@StorageReference NVARCHAR(200),
			@ContentHash BINARY(32),@MimeType VARCHAR(100);
		SELECT @CurrentState=v.PublicationStatus,@FileSizeBytes=v.FileSizeBytes,
			@StorageReference=v.StorageReference,@ContentHash=v.ContentHash,@MimeType=v.MimeType
		FROM leg.LegalDocumentVersions v WITH (UPDLOCK,HOLDLOCK)
		JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
		WHERE v.DocumentVersionId=@DocumentVersionId AND d.DocumentTypeCode='TERMS_AND_CONDITIONS';
		IF @CurrentState IS NULL THROW 52702, 'The legal document is unavailable.', 1;
		IF @CurrentState<>'DRAFT' THROW 52703, 'Only DRAFT legal documents can be submitted.', 1;
		IF @FileSizeBytes<=0 OR @MimeType<>'application/pdf' OR DATALENGTH(@ContentHash)<>32 OR
		   LEN(@StorageReference)<>32 OR TRY_CONVERT(UNIQUEIDENTIFIER,@StorageReference) IS NULL OR
		   NOT EXISTS (SELECT 1 FROM leg.LegalDocumentVersionScopes WHERE DocumentVersionId=@DocumentVersionId)
			THROW 52701, 'The legal document is incomplete and cannot be submitted.', 1;

		DECLARE @MaximumBytes BIGINT;
		SELECT @MaximumBytes=TRY_CONVERT(BIGINT,ConfigurationValue)
		FROM cfg.SystemConfigurations
		WHERE ConfigurationKey='legal.maximum_upload_bytes' AND IsActive=1
		  AND StorageType='PLAIN' AND ValueType='INTEGER';
		IF @MaximumBytes IS NULL OR @MaximumBytes<=0 OR @MaximumBytes>52428800 OR @FileSizeBytes>@MaximumBytes
			THROW 52705, 'Legal document upload policy is unavailable.', 1;

		UPDATE leg.LegalDocumentVersions
		SET PublicationStatus='PENDING_APPROVAL',SubmittedAtUtc=SYSUTCDATETIME(),
			SubmittedByUserId=@ActorUserId
		WHERE DocumentVersionId=@DocumentVersionId AND PublicationStatus='DRAFT';

		INSERT aud.AuditEvents
			(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
			 ChangeSummaryJson,RequestId,CorrelationId)
		SELECT @ActorUserId,actionType.AuditActionTypeId,resultType.AuditResultTypeId,
			'LEGAL_DOCUMENT_VERSION',CONVERT(NVARCHAR(150),@DocumentVersionId),
			N'{"action":"LEGAL_DOCUMENT_SUBMITTED"}',@RequestId,@CorrelationId
		FROM mst.AuditActionTypes actionType
		CROSS JOIN mst.AuditResultTypes resultType
		WHERE actionType.Code='LEGAL_DOCUMENT_SUBMITTED' AND actionType.IsActive=1
		  AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
		IF @@ROWCOUNT<>1 THROW 52706, 'Legal document audit configuration is unavailable.', 1;
		COMMIT TRANSACTION;

		EXEC leg.usp_GetLegalDocumentVersion @DocumentVersionId,@ActorUserId,@PublicSessionId;
	END TRY
	BEGIN CATCH
		IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_DecideLegalDocumentApproval
	@DocumentVersionId UNIQUEIDENTIFIER,
	@DecisionCode VARCHAR(20),
	@DecisionNote NVARCHAR(1000)=NULL,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER,
	@RequestId VARCHAR(100),
	@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.approve';
	IF @DecisionCode NOT IN ('APPROVED','REJECTED') OR LEN(@DecisionNote)>1000
		THROW 52701, 'The legal document approval decision is invalid.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @CurrentState VARCHAR(20);
		SELECT @CurrentState=PublicationStatus
		FROM leg.LegalDocumentVersions WITH (UPDLOCK,HOLDLOCK)
		WHERE DocumentVersionId=@DocumentVersionId;
		IF @CurrentState IS NULL THROW 52702, 'The legal document is unavailable.', 1;
		IF @CurrentState<>'PENDING_APPROVAL'
			THROW 52703, 'Only submitted legal documents can be approved or rejected.', 1;

		INSERT leg.LegalDocumentApprovalDecisions
			(DocumentVersionId,ReviewerUserId,DecisionCode,DecisionNote,RequestId,CorrelationId)
		VALUES(@DocumentVersionId,@ActorUserId,@DecisionCode,NULLIF(LTRIM(RTRIM(@DecisionNote)),N''),
			@RequestId,@CorrelationId);

		IF @DecisionCode='APPROVED'
			UPDATE leg.LegalDocumentVersions
			SET PublicationStatus='APPROVED',ApprovedAtUtc=SYSUTCDATETIME(),ApprovedByUserId=@ActorUserId
			WHERE DocumentVersionId=@DocumentVersionId AND PublicationStatus='PENDING_APPROVAL';
		ELSE
			UPDATE leg.LegalDocumentVersions
			SET PublicationStatus='DRAFT',ApprovedAtUtc=NULL,ApprovedByUserId=NULL
			WHERE DocumentVersionId=@DocumentVersionId AND PublicationStatus='PENDING_APPROVAL';
		IF @@ROWCOUNT<>1 THROW 52703, 'The legal document approval state changed.', 1;

		DECLARE @AuditCode VARCHAR(50)=CASE WHEN @DecisionCode='APPROVED'
			THEN 'LEGAL_DOCUMENT_APPROVED' ELSE 'LEGAL_DOCUMENT_REJECTED' END;
		INSERT aud.AuditEvents
			(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
			 ChangeSummaryJson,RequestId,CorrelationId)
		SELECT @ActorUserId,actionType.AuditActionTypeId,resultType.AuditResultTypeId,
			'LEGAL_DOCUMENT_VERSION',CONVERT(NVARCHAR(150),@DocumentVersionId),
			CASE WHEN @DecisionCode='APPROVED'
				THEN N'{"action":"LEGAL_DOCUMENT_APPROVED"}'
				ELSE N'{"action":"LEGAL_DOCUMENT_REJECTED"}' END,
			@RequestId,@CorrelationId
		FROM mst.AuditActionTypes actionType
		CROSS JOIN mst.AuditResultTypes resultType
		WHERE actionType.Code=@AuditCode AND actionType.IsActive=1
		  AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
		IF @@ROWCOUNT<>1 THROW 52706, 'Legal document audit configuration is unavailable.', 1;
		COMMIT TRANSACTION;

		EXEC leg.usp_GetLegalDocumentVersion @DocumentVersionId,@ActorUserId,@PublicSessionId;
	END TRY
	BEGIN CATCH
		IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_PublishLegalDocument
	@DocumentVersionId UNIQUEIDENTIFIER,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER,
	@RequestId VARCHAR(100),
	@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.publish';

	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @CurrentState VARCHAR(20),@FileSizeBytes BIGINT,@StorageReference NVARCHAR(200),
			@ContentHash BINARY(32),@MimeType VARCHAR(100),@EffectiveAtUtc DATETIME2(3);
		SELECT @CurrentState=v.PublicationStatus,@FileSizeBytes=v.FileSizeBytes,
			@StorageReference=v.StorageReference,@ContentHash=v.ContentHash,@MimeType=v.MimeType,
			@EffectiveAtUtc=v.EffectiveAtUtc
		FROM leg.LegalDocumentVersions v WITH (UPDLOCK,HOLDLOCK)
		JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
		WHERE v.DocumentVersionId=@DocumentVersionId AND d.DocumentTypeCode='TERMS_AND_CONDITIONS';
		IF @CurrentState IS NULL THROW 52702, 'The legal document is unavailable.', 1;
		IF @CurrentState<>'APPROVED' THROW 52703, 'Only approved legal documents can be published.', 1;
		IF @FileSizeBytes<=0 OR @MimeType<>'application/pdf' OR DATALENGTH(@ContentHash)<>32 OR
		   LEN(@StorageReference)<>32 OR TRY_CONVERT(UNIQUEIDENTIFIER,@StorageReference) IS NULL OR
		   NOT EXISTS (SELECT 1 FROM leg.LegalDocumentVersionScopes WHERE DocumentVersionId=@DocumentVersionId)
			THROW 52701, 'The approved legal document is incomplete.', 1;

		DECLARE @MaximumBytes BIGINT;
		SELECT @MaximumBytes=TRY_CONVERT(BIGINT,ConfigurationValue)
		FROM cfg.SystemConfigurations
		WHERE ConfigurationKey='legal.maximum_upload_bytes' AND IsActive=1
		  AND StorageType='PLAIN' AND ValueType='INTEGER';
		IF @MaximumBytes IS NULL OR @MaximumBytes<=0 OR @MaximumBytes>52428800 OR @FileSizeBytes>@MaximumBytes
			THROW 52705, 'Legal document upload policy is unavailable.', 1;

		UPDATE leg.LegalDocumentVersions
		SET PublicationStatus='PUBLISHED',PublishedAtUtc=SYSUTCDATETIME(),PublishedByUserId=@ActorUserId
		WHERE DocumentVersionId=@DocumentVersionId AND PublicationStatus='APPROVED';
		IF @@ROWCOUNT<>1 THROW 52703, 'The legal document publication state changed.', 1;

		INSERT aud.AuditEvents
			(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
			 ChangeSummaryJson,RequestId,CorrelationId)
		SELECT @ActorUserId,actionType.AuditActionTypeId,resultType.AuditResultTypeId,
			'LEGAL_DOCUMENT_VERSION',CONVERT(NVARCHAR(150),@DocumentVersionId),
			N'{"action":"LEGAL_DOCUMENT_PUBLISHED"}',@RequestId,@CorrelationId
		FROM mst.AuditActionTypes actionType
		CROSS JOIN mst.AuditResultTypes resultType
		WHERE actionType.Code='LEGAL_DOCUMENT_PUBLISHED' AND actionType.IsActive=1
		  AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
		IF @@ROWCOUNT<>1 THROW 52706, 'Legal document audit configuration is unavailable.', 1;
		COMMIT TRANSACTION;

		EXEC leg.usp_GetLegalDocumentVersion @DocumentVersionId,@ActorUserId,@PublicSessionId;
	END TRY
	BEGIN CATCH
		IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE leg.usp_ArchiveLegalDocument
	@DocumentVersionId UNIQUEIDENTIFIER,
	@ActorUserId BIGINT,
	@PublicSessionId UNIQUEIDENTIFIER,
	@RequestId VARCHAR(100),
	@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.legal_documents.archive';

	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @CurrentState VARCHAR(20),@Now DATETIME2(3)=SYSUTCDATETIME();
		SELECT @CurrentState=PublicationStatus
		FROM leg.LegalDocumentVersions WITH (UPDLOCK,HOLDLOCK)
		WHERE DocumentVersionId=@DocumentVersionId;
		IF @CurrentState IS NULL THROW 52702, 'The legal document is unavailable.', 1;
		IF @CurrentState<>'PUBLISHED' THROW 52703, 'Only published legal documents can be archived.', 1;
		IF EXISTS
		(
			SELECT 1
			FROM leg.LegalDocumentVersionScopes targetScope
			CROSS APPLY
			(
				SELECT TOP (1) currentVersion.DocumentVersionId
				FROM leg.LegalDocumentVersionScopes currentScope
				JOIN leg.LegalDocumentVersions currentVersion
					ON currentVersion.DocumentVersionId=currentScope.DocumentVersionId
				WHERE currentScope.TenantTypeId=targetScope.TenantTypeId
				  AND currentVersion.PublicationStatus='PUBLISHED'
				  AND currentVersion.EffectiveAtUtc<=@Now
				ORDER BY currentVersion.EffectiveAtUtc DESC,currentVersion.PublishedAtUtc DESC,
					currentVersion.CreatedAtUtc DESC
			) currentTerms
			WHERE targetScope.DocumentVersionId=@DocumentVersionId
			  AND currentTerms.DocumentVersionId=@DocumentVersionId
		)
			THROW 52703, 'The current effective Terms version cannot be archived.', 1;

		UPDATE leg.LegalDocumentVersions
		SET PublicationStatus='ARCHIVED',ArchivedAtUtc=@Now,ArchivedByUserId=@ActorUserId
		WHERE DocumentVersionId=@DocumentVersionId AND PublicationStatus='PUBLISHED';
		IF @@ROWCOUNT<>1 THROW 52703, 'The legal document archival state changed.', 1;

		INSERT aud.AuditEvents
			(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
			 ChangeSummaryJson,RequestId,CorrelationId)
		SELECT @ActorUserId,actionType.AuditActionTypeId,resultType.AuditResultTypeId,
			'LEGAL_DOCUMENT_VERSION',CONVERT(NVARCHAR(150),@DocumentVersionId),
			N'{"action":"LEGAL_DOCUMENT_ARCHIVED"}',@RequestId,@CorrelationId
		FROM mst.AuditActionTypes actionType
		CROSS JOIN mst.AuditResultTypes resultType
		WHERE actionType.Code='LEGAL_DOCUMENT_ARCHIVED' AND actionType.IsActive=1
		  AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
		IF @@ROWCOUNT<>1 THROW 52706, 'Legal document audit configuration is unavailable.', 1;
		COMMIT TRANSACTION;

		EXEC leg.usp_GetLegalDocumentVersion @DocumentVersionId,@ActorUserId,@PublicSessionId;
	END TRY
	BEGIN CATCH
		IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

CREATE OR ALTER TRIGGER leg.trg_LegalDocumentVersions_Immutable
ON leg.LegalDocumentVersions
AFTER UPDATE,DELETE
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS
	(
		SELECT 1
		FROM deleted d
		LEFT JOIN inserted i ON i.DocumentVersionId=d.DocumentVersionId
		WHERE i.DocumentVersionId IS NULL
		   OR (d.PublicationStatus<>'DRAFT' AND
				(i.LegalDocumentId<>d.LegalDocumentId OR i.VersionIdentifier<>d.VersionIdentifier
				 OR i.Title<>d.Title OR i.EffectiveAtUtc<>d.EffectiveAtUtc
				 OR i.StorageReference<>d.StorageReference OR i.ContentHash<>d.ContentHash
				 OR i.MimeType<>d.MimeType OR i.FileSizeBytes<>d.FileSizeBytes))
		   OR (d.PublicationStatus='DRAFT' AND i.PublicationStatus NOT IN ('DRAFT','PENDING_APPROVAL'))
		   OR (d.PublicationStatus='PENDING_APPROVAL' AND
				i.PublicationStatus NOT IN ('PENDING_APPROVAL','APPROVED','DRAFT'))
		   OR (d.PublicationStatus='APPROVED' AND i.PublicationStatus NOT IN ('APPROVED','PUBLISHED'))
		   OR (d.PublicationStatus='PUBLISHED' AND i.PublicationStatus NOT IN ('PUBLISHED','ARCHIVED'))
		   OR (d.PublicationStatus='ARCHIVED' AND i.PublicationStatus<>'ARCHIVED')
	)
		THROW 51610, 'Legal document versions are immutable outside the approved lifecycle.', 1;
END;
GO

CREATE OR ALTER TRIGGER leg.trg_LegalDocumentVersionScopes_Immutable
ON leg.LegalDocumentVersionScopes
AFTER INSERT,UPDATE,DELETE
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS
	(
		SELECT 1
		FROM inserted i
		JOIN leg.LegalDocumentVersions v ON v.DocumentVersionId=i.DocumentVersionId
		WHERE v.PublicationStatus<>'DRAFT'
	) OR EXISTS
	(
		SELECT 1
		FROM deleted d
		JOIN leg.LegalDocumentVersions v ON v.DocumentVersionId=d.DocumentVersionId
		WHERE v.PublicationStatus<>'DRAFT'
	)
		THROW 51611, 'Legal document scopes cannot change after draft submission.', 1;
END;
GO

CREATE OR ALTER TRIGGER leg.trg_LegalDocumentApprovalDecisions_AppendOnly
ON leg.LegalDocumentApprovalDecisions
AFTER UPDATE,DELETE
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM deleted)
		THROW 51613, 'Legal document approval decisions are append-only.', 1;
END;
GO

COMMIT TRANSACTION;
GO
