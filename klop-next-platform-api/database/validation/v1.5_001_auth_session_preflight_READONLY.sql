-- Read-only preflight for database/migrations/v1.5/001_auth_session_procedures.sql.
-- Run with sqlcmd from the repository root against the explicitly approved Development target.
-- Does not reveal configuration values and does not change schema, data, or permissions.
SET NOCOUNT ON;

DECLARE @Findings TABLE
(
	CheckName NVARCHAR(200) NOT NULL,
	StatusCode VARCHAR(16) NOT NULL,
	Details NVARCHAR(400) NOT NULL
);

DECLARE @ProductVersion NVARCHAR(128) = CONVERT(NVARCHAR(128), SERVERPROPERTY('ProductVersion'));
DECLARE @ProductMajor INT = TRY_CONVERT(INT, PARSENAME(@ProductVersion, 4));
DECLARE @ProductBuild INT = TRY_CONVERT(INT, PARSENAME(@ProductVersion, 2));

INSERT @Findings VALUES
(N'Database is not master', CASE WHEN DB_ID() <> DB_ID(N'master') THEN 'PASS' ELSE 'BLOCKER' END, N'Current database must be the DBA-approved Development database.'),
(N'Database is online and writable', CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE database_id=DB_ID() AND state_desc=N'ONLINE' AND is_read_only=0) THEN 'PASS' ELSE 'BLOCKER' END, N'Database must be online and writable.'),
(N'SQL Server supports CREATE OR ALTER', CASE WHEN @ProductMajor > 13 OR (@ProductMajor = 13 AND @ProductBuild >= 4001) THEN 'PASS' ELSE 'BLOCKER' END, N'Requires SQL Server 2016 SP1 or later.'),
(N'Existing target procedure objects are absent', CASE WHEN NOT EXISTS
(
	SELECT 1 FROM (VALUES
		(N'iam',N'usp_GetLocalLoginCandidate'),(N'iam',N'usp_RecordLocalLoginFailure'),
		(N'iam',N'usp_IssueEmailVerificationChallenge'),(N'iam',N'usp_CreateAuthSession'),
		(N'iam',N'usp_ValidateSessionAccess'),(N'iam',N'usp_RotateRefreshToken'),
		(N'iam',N'usp_RevokeAuthSession'),(N'iam',N'usp_GetUserProfile'),
		(N'ten',N'usp_ListMyTenants')
	) target(SchemaName,ObjectName)
	JOIN sys.schemas s ON s.name=target.SchemaName
	JOIN sys.objects o ON o.schema_id=s.schema_id AND o.name=target.ObjectName
) THEN 'PASS' ELSE 'BLOCKER' END, N'Any existing object with a target name requires definition review; this migration will not overwrite it.'),
(N'Cross-schema ownership chaining is consistent', CASE WHEN
	(SELECT COUNT(DISTINCT principal_id) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))=1
	AND (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))=5
	THEN 'PASS' ELSE 'BLOCKER' END, N'Referenced application schemas must exist and have a common owner for least-privilege EXECUTE ownership chaining.');

WITH RequiredObjects(SchemaName,ObjectName,ObjectType) AS
(
	SELECT * FROM (VALUES
		(N'cfg',N'SystemConfigurations',N'TABLE'),(N'cfg',N'usp_Configuration_GetByKey',N'PROCEDURE'),
		(N'iam',N'Users',N'TABLE'),(N'iam',N'UserCredentials',N'TABLE'),(N'iam',N'VerificationChallenges',N'TABLE'),
		(N'iam',N'AuthSessions',N'TABLE'),(N'iam',N'RefreshTokens',N'TABLE'),(N'iam',N'TenantRoleAssignments',N'TABLE'),
		(N'mst',N'SecurityEventTypes',N'TABLE'),(N'mst',N'AuditActionTypes',N'TABLE'),(N'mst',N'AuditResultTypes',N'TABLE'),
		(N'mst',N'VerificationPurposes',N'TABLE'),(N'mst',N'MembershipStatuses',N'TABLE'),(N'mst',N'TenantStatuses',N'TABLE'),
		(N'mst',N'Roles',N'TABLE'),(N'mst',N'RoleScopes',N'TABLE'),(N'mst',N'RolePermissions',N'TABLE'),(N'mst',N'Permissions',N'TABLE'),
		(N'mst',N'TenantTypes',N'TABLE'),(N'ten',N'Tenants',N'TABLE'),(N'ten',N'TenantMemberships',N'TABLE'),
		(N'aud',N'SecurityEvents',N'TABLE'),(N'aud',N'AuditEvents',N'TABLE'),
		(N'iam',N'usp_RegisterLocalUser',N'PROCEDURE'),(N'iam',N'usp_ConfirmEmail',N'PROCEDURE'),
		(N'ten',N'usp_CreateTenantWithOwner',N'PROCEDURE'),(N'ten',N'usp_InviteExistingUser',N'PROCEDURE'),
		(N'ten',N'usp_AcceptMembership',N'PROCEDURE'),(N'ten',N'usp_RemoveTenantMember',N'PROCEDURE'),
		(N'iam',N'usp_AssignTenantRole',N'PROCEDURE'),(N'iam',N'usp_RevokeTenantRole',N'PROCEDURE'),
		(N'mst',N'usp_OrganizationType_GetAll',N'PROCEDURE'),(N'mst',N'usp_TenantType_GetAll',N'PROCEDURE')
	) v(SchemaName,ObjectName,ObjectType)
)
INSERT @Findings(CheckName,StatusCode,Details)
SELECT N'Object '+r.SchemaName+N'.'+r.ObjectName,
	   CASE WHEN (r.ObjectType=N'TABLE' AND t.object_id IS NOT NULL) OR (r.ObjectType=N'PROCEDURE' AND p.object_id IS NOT NULL) THEN 'PASS' ELSE 'BLOCKER' END,
	   CASE WHEN r.ObjectType=N'TABLE' THEN N'Required baseline table.' ELSE N'Required existing baseline Stored Procedure.' END
FROM RequiredObjects r
LEFT JOIN sys.schemas s ON s.name=r.SchemaName
LEFT JOIN sys.tables t ON t.schema_id=s.schema_id AND t.name=r.ObjectName AND r.ObjectType=N'TABLE'
LEFT JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ObjectName AND r.ObjectType=N'PROCEDURE';

WITH RequiredColumns(SchemaName,TableName,ColumnName) AS
(
	SELECT * FROM (VALUES
		(N'iam',N'Users',N'UserId'),(N'iam',N'Users',N'DisplayName'),(N'iam',N'Users',N'IsActive'),(N'iam',N'Users',N'EmailVerifiedAtUtc'),(N'iam',N'Users',N'NormalizedEmail'),(N'iam',N'Users',N'Email'),
		(N'iam',N'UserCredentials',N'UserId'),(N'iam',N'UserCredentials',N'PasswordHash'),(N'iam',N'UserCredentials',N'LockoutUntilUtc'),(N'iam',N'UserCredentials',N'FailedLoginCount'),(N'iam',N'UserCredentials',N'UpdatedAtUtc'),
		(N'iam',N'VerificationChallenges',N'UserId'),(N'iam',N'VerificationChallenges',N'VerificationPurposeId'),(N'iam',N'VerificationChallenges',N'TokenHash'),(N'iam',N'VerificationChallenges',N'ExpiresAtUtc'),(N'iam',N'VerificationChallenges',N'ConsumedAtUtc'),(N'iam',N'VerificationChallenges',N'InvalidatedAtUtc'),
		(N'iam',N'AuthSessions',N'AuthSessionId'),(N'iam',N'AuthSessions',N'PublicSessionId'),(N'iam',N'AuthSessions',N'UserId'),(N'iam',N'AuthSessions',N'TenantId'),(N'iam',N'AuthSessions',N'ExpiresAtUtc'),(N'iam',N'AuthSessions',N'RevokedAtUtc'),(N'iam',N'AuthSessions',N'RevocationReason'),
		(N'iam',N'RefreshTokens',N'RefreshTokenId'),(N'iam',N'RefreshTokens',N'AuthSessionId'),(N'iam',N'RefreshTokens',N'TokenHash'),(N'iam',N'RefreshTokens',N'TokenFamilyId'),(N'iam',N'RefreshTokens',N'ExpiresAtUtc'),(N'iam',N'RefreshTokens',N'UsedAtUtc'),(N'iam',N'RefreshTokens',N'RevokedAtUtc'),(N'iam',N'RefreshTokens',N'PreviousTokenId'),
		(N'cfg',N'SystemConfigurations',N'ConfigurationKey'),(N'cfg',N'SystemConfigurations',N'ConfigurationValue'),(N'cfg',N'SystemConfigurations',N'ValueType'),(N'cfg',N'SystemConfigurations',N'StorageType'),(N'cfg',N'SystemConfigurations',N'IsActive'),
		(N'mst',N'SecurityEventTypes',N'SecurityEventTypeId'),(N'mst',N'SecurityEventTypes',N'Code'),(N'mst',N'SecurityEventTypes',N'IsActive'),
		(N'mst',N'AuditActionTypes',N'AuditActionTypeId'),(N'mst',N'AuditActionTypes',N'Code'),(N'mst',N'AuditActionTypes',N'IsActive'),
		(N'mst',N'AuditResultTypes',N'AuditResultTypeId'),(N'mst',N'AuditResultTypes',N'Code'),(N'mst',N'AuditResultTypes',N'IsActive'),
		(N'mst',N'VerificationPurposes',N'VerificationPurposeId'),(N'mst',N'VerificationPurposes',N'Code'),(N'mst',N'VerificationPurposes',N'IsActive'),
		(N'mst',N'MembershipStatuses',N'MembershipStatusId'),(N'mst',N'MembershipStatuses',N'Code'),(N'mst',N'TenantStatuses',N'TenantStatusId'),(N'mst',N'TenantStatuses',N'Code'),(N'mst',N'TenantStatuses',N'IsActive'),(N'mst',N'MembershipStatuses',N'IsActive'),
		(N'mst',N'TenantTypes',N'TenantTypeId'),(N'mst',N'TenantTypes',N'Code'),
		(N'ten',N'Tenants',N'TenantId'),(N'ten',N'Tenants',N'TenantCode'),(N'ten',N'Tenants',N'DisplayName'),(N'ten',N'Tenants',N'TenantTypeId'),(N'ten',N'Tenants',N'TenantStatusId'),
		(N'ten',N'TenantMemberships',N'MembershipId'),(N'ten',N'TenantMemberships',N'TenantId'),(N'ten',N'TenantMemberships',N'UserId'),(N'ten',N'TenantMemberships',N'MembershipStatusId'),(N'iam',N'TenantRoleAssignments',N'MembershipId'),(N'iam',N'TenantRoleAssignments',N'RoleId'),
		(N'aud',N'SecurityEvents',N'ActorUserId'),(N'aud',N'SecurityEvents',N'SubjectUserId'),(N'aud',N'SecurityEvents',N'SecurityEventTypeId'),(N'aud',N'SecurityEvents',N'SeverityCode'),(N'aud',N'SecurityEvents',N'CorrelationId'),
		(N'aud',N'AuditEvents',N'ActorService'),(N'aud',N'AuditEvents',N'ActorUserId'),(N'aud',N'AuditEvents',N'AuditActionTypeId'),(N'aud',N'AuditEvents',N'AuditResultTypeId'),(N'aud',N'AuditEvents',N'TargetType'),(N'aud',N'AuditEvents',N'TargetId'),(N'aud',N'AuditEvents',N'RequestId'),(N'aud',N'AuditEvents',N'CorrelationId')
	) v(SchemaName,TableName,ColumnName)
)
INSERT @Findings(CheckName,StatusCode,Details)
SELECT N'Column '+r.SchemaName+N'.'+r.TableName+N'.'+r.ColumnName,
	   CASE WHEN c.column_id IS NULL THEN 'BLOCKER' ELSE 'PASS' END,
	   CASE WHEN c.column_id IS NULL THEN N'Referenced by source procedure; deployment would defer or fail.' ELSE N'Referenced source column exists.' END
FROM RequiredColumns r
LEFT JOIN sys.schemas s ON s.name=r.SchemaName
LEFT JOIN sys.tables t ON t.schema_id=s.schema_id AND t.name=r.TableName
LEFT JOIN sys.columns c ON c.object_id=t.object_id AND c.name=r.ColumnName;

WITH RequiredIndexes(SchemaName,TableName,IndexName,RequiresFilter) AS
(
	SELECT * FROM (VALUES
		(N'iam',N'Users',N'UX_Users_NormalizedEmail',0),
		(N'iam',N'VerificationChallenges',N'UX_VerificationChallenges_TokenHash',0),
		(N'iam',N'AuthSessions',N'UX_AuthSessions_PublicSessionId',0),
		(N'iam',N'RefreshTokens',N'UX_RefreshTokens_TokenHash',0),
		(N'iam',N'RefreshTokens',N'UX_RefreshTokens_PreviousToken',1)
	) v(SchemaName,TableName,IndexName,RequiresFilter)
)
INSERT @Findings(CheckName,StatusCode,Details)
SELECT N'Unique index '+r.SchemaName+N'.'+r.TableName+N'.'+r.IndexName,
	   CASE WHEN i.index_id IS NOT NULL AND i.is_unique=1 AND i.is_disabled=0
				  AND (r.RequiresFilter=0 OR (i.has_filter=1 AND REPLACE(REPLACE(REPLACE(i.filter_definition,N'[',N''),N']',N''),N' ',N'') LIKE N'%(PreviousTokenIdISNOTNULL)%'))
			THEN 'PASS' ELSE 'BLOCKER' END,
	   N'Required uniqueness protects user/challenge/session/token identity and one-successor rotation.'
FROM RequiredIndexes r
LEFT JOIN sys.schemas s ON s.name=r.SchemaName
LEFT JOIN sys.tables t ON t.schema_id=s.schema_id AND t.name=r.TableName
LEFT JOIN sys.indexes i ON i.object_id=t.object_id AND i.name=r.IndexName;

INSERT @Findings
SELECT N'FK constraints enabled and trusted',CASE WHEN EXISTS
(
	SELECT 1 FROM sys.foreign_keys fk JOIN sys.tables t ON t.object_id=fk.parent_object_id JOIN sys.schemas s ON s.schema_id=t.schema_id
	WHERE s.name IN(N'iam',N'cfg',N'mst',N'ten',N'aud') AND t.name IN(N'Users',N'UserCredentials',N'VerificationChallenges',N'AuthSessions',N'RefreshTokens',N'TenantRoleAssignments',N'Tenants',N'TenantMemberships',N'SecurityEvents',N'AuditEvents')
	  AND (fk.is_disabled=1 OR fk.is_not_trusted=1)
) THEN 'BLOCKER' ELSE 'PASS' END,N'Foreign key relationships on auth/session, tenancy and audit tables must be enabled and trusted.';
INSERT @Findings
SELECT N'CHECK constraints enabled',CASE WHEN EXISTS
(
	SELECT 1 FROM sys.check_constraints cc JOIN sys.tables t ON t.object_id=cc.parent_object_id JOIN sys.schemas s ON s.schema_id=t.schema_id
	WHERE s.name IN(N'iam',N'cfg',N'mst',N'ten',N'aud') AND t.name IN(N'Users',N'UserCredentials',N'VerificationChallenges',N'AuthSessions',N'RefreshTokens',N'TenantRoleAssignments',N'Tenants',N'TenantMemberships',N'SecurityEvents',N'AuditEvents')
	  AND cc.is_disabled=1
) THEN 'BLOCKER' ELSE 'PASS' END,N'Auth/session and audit check constraints must be enabled.';

WITH RequiredMasterCodes(SchemaName,TableName,Code,RequireActive) AS
(
	SELECT * FROM (VALUES
		(N'mst',N'SecurityEventTypes',N'LOGIN_FAILED',1),(N'mst',N'SecurityEventTypes',N'LOGIN_SUCCESS',1),(N'mst',N'SecurityEventTypes',N'TOKEN_REVOKED',1),
		(N'mst',N'AuditActionTypes',N'CREATE',1),(N'mst',N'AuditActionTypes',N'DEACTIVATE',1),(N'mst',N'AuditResultTypes',N'SUCCESS',1),
		(N'mst',N'VerificationPurposes',N'EMAIL_CONFIRMATION',1),(N'mst',N'MembershipStatuses',N'ACTIVE',0),
		(N'mst',N'TenantStatuses',N'ACTIVE',0),(N'mst',N'TenantStatuses',N'PENDING',0),(N'mst',N'RoleScopes',N'TENANT',0)
	) v(SchemaName,TableName,Code,RequireActive)
)
INSERT @Findings(CheckName,StatusCode,Details)
SELECT N'Master code '+r.TableName+N'.'+r.Code,
	   CASE WHEN EXISTS
	   (
		   SELECT 1 FROM sys.schemas s JOIN sys.tables t ON t.schema_id=s.schema_id
		   JOIN sys.columns codeColumn ON codeColumn.object_id=t.object_id AND codeColumn.name=N'Code'
		   WHERE s.name=r.SchemaName AND t.name=r.TableName
			 AND ((r.TableName=N'SecurityEventTypes' AND EXISTS(SELECT 1 FROM mst.SecurityEventTypes x WHERE x.Code=r.Code AND (r.RequireActive=0 OR x.IsActive=1)))
			   OR (r.TableName=N'AuditActionTypes' AND EXISTS(SELECT 1 FROM mst.AuditActionTypes x WHERE x.Code=r.Code AND (r.RequireActive=0 OR x.IsActive=1)))
			   OR (r.TableName=N'AuditResultTypes' AND EXISTS(SELECT 1 FROM mst.AuditResultTypes x WHERE x.Code=r.Code AND (r.RequireActive=0 OR x.IsActive=1)))
			   OR (r.TableName=N'VerificationPurposes' AND EXISTS(SELECT 1 FROM mst.VerificationPurposes x WHERE x.Code=r.Code AND (r.RequireActive=0 OR x.IsActive=1)))
			   OR (r.TableName=N'MembershipStatuses' AND EXISTS(SELECT 1 FROM mst.MembershipStatuses x WHERE x.Code=r.Code))
			   OR (r.TableName=N'TenantStatuses' AND EXISTS(SELECT 1 FROM mst.TenantStatuses x WHERE x.Code=r.Code))
			   OR (r.TableName=N'RoleScopes' AND EXISTS(SELECT 1 FROM mst.RoleScopes x WHERE x.Code=r.Code)))
	   ) THEN 'PASS' ELSE 'BLOCKER' END,N'Required source-procedure master data must exist and required event/action codes must be active.'
FROM RequiredMasterCodes r;

INSERT @Findings(CheckName,StatusCode,Details)
SELECT N'Configuration '+r.ConfigurationKey,
	   CASE WHEN c.ConfigurationId IS NOT NULL AND c.ValueType=N'INTEGER' AND c.StorageType=N'PLAIN'
				 AND TRY_CONVERT(INT,c.ConfigurationValue) BETWEEN r.MinimumValue AND r.MaximumValue
			THEN 'PASS' ELSE 'BLOCKER' END,
	   N'Required active INTEGER/PLAIN configuration must be in range; value is intentionally not displayed.'
FROM (VALUES (N'security.max_login_attempts',3,10),(N'security.login_lockout_minutes',5,120)) r(ConfigurationKey,MinimumValue,MaximumValue)
LEFT JOIN cfg.SystemConfigurations c ON c.ConfigurationKey=r.ConfigurationKey AND c.IsActive=1;

SELECT N'DEVELOPMENT_TARGET' AS Section,DB_NAME() AS DatabaseName,CONVERT(NVARCHAR(128),SERVERPROPERTY('ProductVersion')) AS SqlServerVersion;
SELECT CheckName,StatusCode,Details FROM @Findings ORDER BY CASE StatusCode WHEN 'BLOCKER' THEN 0 ELSE 1 END,CheckName;

-- Runtime identity is a separate post-deployment gate; this report is informational for DDL readiness.
SELECT N'RUNTIME_ACCESS_GATE' AS Section,
	   CASE WHEN DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL THEN N'BLOCKED: runtime role absent'
			WHEN (SELECT COUNT_BIG(*) FROM sys.database_role_members rm JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id WHERE r.name=N'klop_app_runtime')=0 THEN N'BLOCKED: role has no members'
			ELSE N'REVIEW REQUIRED: test with the actual API runtime identity' END AS Status;

IF EXISTS (SELECT 1 FROM @Findings WHERE StatusCode='BLOCKER')
	THROW 51500, 'v1.5 preflight failed. Do not apply the migration.', 1;
GO
