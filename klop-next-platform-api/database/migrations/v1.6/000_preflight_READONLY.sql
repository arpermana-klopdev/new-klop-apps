-- KLOP Platform v1.6 preflight. READ ONLY; do not use as an approval or deployment substitute.
SET NOCOUNT ON;

DECLARE @Findings TABLE
(
	CheckName NVARCHAR(200) NOT NULL,
	StatusCode VARCHAR(16) NOT NULL,
	Details NVARCHAR(400) NOT NULL
);

INSERT @Findings VALUES
(N'Database is the approved application database',
 CASE WHEN DB_NAME() <> N'master' AND DB_NAME() = N'KlopPlatformDB' THEN 'PASS' ELSE 'BLOCKER' END,
 N'Connect only to the explicitly approved Development target; Production and test-database creation are prohibited.'),
(N'Database is online and writable',
 CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE database_id=DB_ID() AND state_desc=N'ONLINE' AND is_read_only=0)
	  THEN 'PASS' ELSE 'BLOCKER' END,
 N'The migration requires an online, writable, explicitly approved Development database.'),
(N'Baseline schemas are present and share an owner',
 CASE WHEN (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))=5
		AND (SELECT COUNT(DISTINCT principal_id) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))=1
	  THEN 'PASS' ELSE 'BLOCKER' END,
 N'Existing baseline schemas must be present and share ownership for EXECUTE ownership chaining.'),
(N'New registration schemas do not already exist',
 CASE WHEN SCHEMA_ID(N'reg') IS NULL AND SCHEMA_ID(N'leg') IS NULL THEN 'PASS' ELSE 'BLOCKER' END,
 N'Existing reg/leg schemas require manual object-by-object reconciliation; this delta does not overwrite unknown objects.'),
(N'Existing atomic registration procedure exists',
 CASE WHEN OBJECT_ID(N'iam.usp_RegisterLocalUser',N'P') IS NOT NULL THEN 'PASS' ELSE 'BLOCKER' END,
 N'The migration extends the existing atomic registration Stored Procedure.'),
(N'Existing user, challenge, master and audit contracts exist',
 CASE WHEN OBJECT_ID(N'iam.Users',N'U') IS NOT NULL AND OBJECT_ID(N'iam.UserCredentials',N'U') IS NOT NULL
		AND OBJECT_ID(N'iam.VerificationChallenges',N'U') IS NOT NULL AND OBJECT_ID(N'mst.TenantTypes',N'U') IS NOT NULL
		AND OBJECT_ID(N'mst.OnboardingStatuses',N'U') IS NULL AND OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NOT NULL
		AND OBJECT_ID(N'aud.AuditEvents',N'U') IS NOT NULL
	  THEN 'PASS' ELSE 'BLOCKER' END,
 N'Existing IAM, master, configuration, and audit objects must match the inspected baseline.'),
(N'No target v1.6 registration tables or procedures exist',
 CASE WHEN OBJECT_ID(N'reg.RegistrationApplications') IS NULL AND OBJECT_ID(N'leg.LegalDocumentVersions') IS NULL
		AND OBJECT_ID(N'leg.usp_GetCurrentTerms',N'P') IS NULL
	  THEN 'PASS' ELSE 'BLOCKER' END,
 N'Target-object existence requires manual reconciliation; no existing object will be overwritten except the reviewed registration procedure.');

SELECT N'DEVELOPMENT_TARGET' AS Section,DB_NAME() AS DatabaseName,
	   CONVERT(NVARCHAR(128),SERVERPROPERTY('ProductVersion')) AS SqlServerVersion,
	   SYSDATETIMEOFFSET() AS CheckedAt;
SELECT CheckName,StatusCode,Details FROM @Findings
ORDER BY CASE StatusCode WHEN 'BLOCKER' THEN 0 ELSE 1 END,CheckName;
SELECT N'RUNTIME_ACCESS_REVIEW_REQUIRED' AS Section,
	   CASE WHEN DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL THEN N'BLOCKED: runtime role absent'
			WHEN (SELECT COUNT_BIG(*) FROM sys.database_role_members rm
				  JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
				  WHERE r.name=N'klop_app_runtime')=0 THEN N'BLOCKED: runtime role has no members'
			ELSE N'REVIEW REQUIRED: verify actual API identity and explicit EXECUTE grants' END AS Status;

IF EXISTS (SELECT 1 FROM @Findings WHERE StatusCode='BLOCKER')
	THROW 51600, 'v1.6 preflight failed. Do not apply the migration.', 1;
GO
