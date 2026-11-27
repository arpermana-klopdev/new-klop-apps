-- KLOP Platform v1.6 post-deployment verification. READ ONLY; does not grant permissions or inspect PII/secrets.
SET NOCOUNT ON;

DECLARE @Findings TABLE
(
	CheckName NVARCHAR(200) NOT NULL,
	StatusCode VARCHAR(16) NOT NULL,
	Details NVARCHAR(400) NOT NULL
);

WITH RequiredObjects(SchemaName,ObjectName,ObjectType) AS
(
	SELECT * FROM (VALUES
		(N'mst',N'OnboardingStatuses',N'TABLE'),
		(N'reg',N'RegistrationApplications',N'TABLE'),
		(N'reg',N'RegistrationApplicationHistory',N'TABLE'),
		(N'reg',N'PersonalOnboardingDetails',N'TABLE'),
		(N'reg',N'OrganizationOnboardingDetails',N'TABLE'),
		(N'reg',N'ApplicationSupportingDocuments',N'TABLE'),
		(N'leg',N'LegalDocuments',N'TABLE'),
		(N'leg',N'LegalDocumentVersions',N'TABLE'),
		(N'leg',N'LegalDocumentVersionScopes',N'TABLE'),
		(N'leg',N'UserLegalConsents',N'TABLE'),
		(N'iam',N'usp_RegisterLocalUser',N'PROCEDURE'),
		(N'reg',N'usp_GetMyApplication',N'PROCEDURE'),
		(N'reg',N'usp_GetApplicationForOwner',N'PROCEDURE'),
		(N'reg',N'usp_SavePersonalDraft',N'PROCEDURE'),
		(N'reg',N'usp_SaveOrganizationDraft',N'PROCEDURE'),
		(N'reg',N'usp_GetOrganizationRequirements',N'PROCEDURE'),
		(N'reg',N'usp_SubmitOnboarding',N'PROCEDURE'),
		(N'leg',N'usp_GetCurrentTerms',N'PROCEDURE'),
		(N'leg',N'usp_GetPublicTermsFile',N'PROCEDURE')
	) v(SchemaName,ObjectName,ObjectType)
)
INSERT @Findings(CheckName,StatusCode,Details)
SELECT N'Object '+r.SchemaName+N'.'+r.ObjectName,
	   CASE WHEN (r.ObjectType=N'TABLE' AND t.object_id IS NOT NULL)
				  OR (r.ObjectType=N'PROCEDURE' AND p.object_id IS NOT NULL) THEN 'PASS' ELSE 'BLOCKER' END,
	   N'Required v1.6 Stored Procedure or table must exist.'
FROM RequiredObjects r
LEFT JOIN sys.schemas s ON s.name=r.SchemaName
LEFT JOIN sys.tables t ON t.schema_id=s.schema_id AND t.name=r.ObjectName AND r.ObjectType=N'TABLE'
LEFT JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ObjectName AND r.ObjectType=N'PROCEDURE';

INSERT @Findings(CheckName,StatusCode,Details)
SELECT N'Configuration '+r.ConfigurationKey,
	   CASE WHEN c.ConfigurationId IS NOT NULL AND c.ValueType=r.ValueType AND c.StorageType=N'PLAIN'
				  AND c.IsActive=1 AND c.IsSystem=1 AND c.IsEditable=0 AND c.RequiresApproval=1
				  AND ((r.MustRemainFalse=1 AND TRY_CONVERT(BIT,c.ConfigurationValue)=0)
					   OR (r.MustRemainFalse=0 AND TRY_CONVERT(BIGINT,c.ConfigurationValue) BETWEEN 1 AND 52428800))
			THEN 'PASS' ELSE 'BLOCKER' END,
	   N'Required configuration metadata is present; values are not emitted.'
FROM (VALUES
	(N'registration.legal_consent_enforcement',N'BOOLEAN',1),
	(N'legal.maximum_upload_bytes',N'INTEGER',0),
	(N'onboarding.personal_submission_enabled',N'BOOLEAN',1),
	(N'onboarding.organization_submission_enabled',N'BOOLEAN',1)
) r(ConfigurationKey,ValueType,MustRemainFalse)
LEFT JOIN cfg.SystemConfigurations c ON c.ConfigurationKey=r.ConfigurationKey;

INSERT @Findings
SELECT N'Onboarding status master codes',
	   CASE WHEN (SELECT COUNT(*) FROM mst.OnboardingStatuses WHERE IsActive=1 AND Code IN
		   ('DRAFT','SUBMITTED','UNDER_REVIEW','NEEDS_REVISION','APPROVED','REJECTED','COMPLETED'))=7
			THEN 'PASS' ELSE 'BLOCKER' END,
	   N'All seven agreed status codes must be active.';

INSERT @Findings
SELECT N'Immutability triggers enabled',
	   CASE WHEN (SELECT COUNT(*) FROM sys.triggers WHERE is_disabled=0 AND name IN
		   (N'trg_LegalDocumentVersions_Immutable',N'trg_LegalDocumentVersionScopes_Immutable',
			N'trg_UserLegalConsents_AppendOnly'))=3 THEN 'PASS' ELSE 'BLOCKER' END,
	   N'Published document metadata/scopes and consent history must be protected.';

INSERT @Findings
SELECT N'No Terms PDF auto-published',
	   CASE WHEN NOT EXISTS (SELECT 1 FROM leg.LegalDocumentVersions WHERE PublicationStatus='PUBLISHED')
			THEN 'PASS' ELSE 'REVIEW' END,
	   N'Publication must be based on approved legal review, not migration seed data.';

SELECT N'DEVELOPMENT_TARGET' AS Section,DB_NAME() AS DatabaseName,
	   CONVERT(NVARCHAR(128),SERVERPROPERTY('ProductVersion')) AS SqlServerVersion,
	   SYSDATETIMEOFFSET() AS CheckedAt;
SELECT CheckName,StatusCode,Details FROM @Findings
ORDER BY CASE StatusCode WHEN 'BLOCKER' THEN 0 WHEN 'REVIEW' THEN 1 ELSE 2 END,CheckName;
SELECT N'RUNTIME_ACCESS_GATE' AS Section,
	   CASE WHEN DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL THEN N'BLOCKED: runtime role absent'
			WHEN (SELECT COUNT_BIG(*) FROM sys.database_role_members rm
				  JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
				  WHERE r.name=N'klop_app_runtime')=0 THEN N'BLOCKED: runtime role has no members'
			ELSE N'REVIEW REQUIRED: test with the actual API runtime identity and explicit EXECUTE grants' END AS Status;

IF EXISTS (SELECT 1 FROM @Findings WHERE StatusCode='BLOCKER')
	THROW 51620, 'v1.6 post-deployment verification failed.', 1;
GO
