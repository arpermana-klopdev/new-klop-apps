-- Read-only verification after an explicitly approved Development deployment.
-- Run using the approved DBA context for metadata, then separately as the actual API runtime identity.
-- This script does not prove Stored Procedure behavior; guarded integration tests are still required.
SET NOCOUNT ON;

DECLARE @ExpectedProcedures TABLE(SchemaName SYSNAME NOT NULL,ObjectName SYSNAME NOT NULL PRIMARY KEY(SchemaName,ObjectName));
INSERT @ExpectedProcedures VALUES
(N'iam',N'usp_GetLocalLoginCandidate'),(N'iam',N'usp_RecordLocalLoginFailure'),
(N'iam',N'usp_IssueEmailVerificationChallenge'),(N'iam',N'usp_CreateAuthSession'),
(N'iam',N'usp_ValidateSessionAccess'),(N'iam',N'usp_RotateRefreshToken'),
(N'iam',N'usp_RevokeAuthSession'),(N'iam',N'usp_GetUserProfile'),(N'ten',N'usp_ListMyTenants');

DECLARE @ExpectedParameters TABLE
(
	SchemaName SYSNAME NOT NULL,ObjectName SYSNAME NOT NULL,ParameterId INT NOT NULL,
	ParameterName SYSNAME NOT NULL,TypeName SYSNAME NOT NULL,MaxLength SMALLINT NOT NULL,
	ScaleValue TINYINT NOT NULL,IsOutput BIT NOT NULL,
	PRIMARY KEY(SchemaName,ObjectName,ParameterId)
);
INSERT @ExpectedParameters VALUES
(N'iam',N'usp_GetLocalLoginCandidate',1,N'@NormalizedEmail',N'nvarchar',640,0,0),
(N'iam',N'usp_RecordLocalLoginFailure',1,N'@UserId',N'bigint',8,0,0),
(N'iam',N'usp_RecordLocalLoginFailure',2,N'@CorrelationId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_IssueEmailVerificationChallenge',1,N'@Email',N'nvarchar',640,0,0),
(N'iam',N'usp_IssueEmailVerificationChallenge',2,N'@TokenHash',N'binary',32,0,0),
(N'iam',N'usp_IssueEmailVerificationChallenge',3,N'@ExpiresAtUtc',N'datetime2',7,3,0),
(N'iam',N'usp_IssueEmailVerificationChallenge',4,N'@RequestId',N'varchar',100,0,0),
(N'iam',N'usp_IssueEmailVerificationChallenge',5,N'@CorrelationId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_IssueEmailVerificationChallenge',6,N'@UserId',N'bigint',8,0,1),
(N'iam',N'usp_CreateAuthSession',1,N'@UserId',N'bigint',8,0,0),
(N'iam',N'usp_CreateAuthSession',2,N'@SessionExpiresAtUtc',N'datetime2',7,3,0),
(N'iam',N'usp_CreateAuthSession',3,N'@RefreshTokenHash',N'binary',32,0,0),
(N'iam',N'usp_CreateAuthSession',4,N'@RefreshExpiresAtUtc',N'datetime2',7,3,0),
(N'iam',N'usp_CreateAuthSession',5,N'@RequestId',N'varchar',100,0,0),
(N'iam',N'usp_CreateAuthSession',6,N'@CorrelationId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_CreateAuthSession',7,N'@PublicSessionId',N'uniqueidentifier',16,0,1),
(N'iam',N'usp_ValidateSessionAccess',1,N'@UserId',N'bigint',8,0,0),
(N'iam',N'usp_ValidateSessionAccess',2,N'@PublicSessionId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_ValidateSessionAccess',3,N'@TenantId',N'bigint',8,0,0),
(N'iam',N'usp_ValidateSessionAccess',4,N'@PermissionCode',N'varchar',120,0,0),
(N'iam',N'usp_RotateRefreshToken',1,N'@PublicSessionId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_RotateRefreshToken',2,N'@OldTokenHash',N'binary',32,0,0),
(N'iam',N'usp_RotateRefreshToken',3,N'@NewTokenHash',N'binary',32,0,0),
(N'iam',N'usp_RotateRefreshToken',4,N'@NewExpiresAtUtc',N'datetime2',7,3,0),
(N'iam',N'usp_RotateRefreshToken',5,N'@CorrelationId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_RotateRefreshToken',6,N'@UserId',N'bigint',8,0,1),
(N'iam',N'usp_RevokeAuthSession',1,N'@UserId',N'bigint',8,0,0),
(N'iam',N'usp_RevokeAuthSession',2,N'@PublicSessionId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_RevokeAuthSession',3,N'@CorrelationId',N'uniqueidentifier',16,0,0),
(N'iam',N'usp_GetUserProfile',1,N'@UserId',N'bigint',8,0,0),
(N'ten',N'usp_ListMyTenants',1,N'@UserId',N'bigint',8,0,0);

DECLARE @ProcedureResults TABLE(SchemaName SYSNAME,ObjectName SYSNAME,StatusCode VARCHAR(16),Details NVARCHAR(400));
INSERT @ProcedureResults
SELECT e.SchemaName,e.ObjectName,
	   CASE WHEN p.object_id IS NULL THEN 'MISSING'
			WHEN mismatch.MismatchCount=0 AND actual.ActualCount=expected.ExpectedCount THEN 'PASS' ELSE 'FAIL' END,
	   CASE WHEN p.object_id IS NULL THEN CONCAT(N'Procedure is absent; expected parameters: ',expected.ExpectedCount,N'.')
			ELSE CONCAT(N'Expected parameters: ',expected.ExpectedCount,N'; actual parameters: ',COALESCE(actual.ActualCount,0),N'; mismatches: ',COALESCE(mismatch.MismatchCount,0),N'.') END
FROM @ExpectedProcedures e
LEFT JOIN sys.schemas s ON s.name=e.SchemaName
LEFT JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=e.ObjectName
OUTER APPLY (SELECT COUNT(*) AS ExpectedCount FROM @ExpectedParameters ep WHERE ep.SchemaName=e.SchemaName AND ep.ObjectName=e.ObjectName) expected
OUTER APPLY (SELECT COUNT(*) AS ActualCount FROM sys.parameters ap WHERE ap.object_id=p.object_id AND ap.parameter_id>0) actual
OUTER APPLY
(
	SELECT COUNT(*) AS MismatchCount
	FROM @ExpectedParameters ep
	FULL OUTER JOIN sys.parameters ap ON ap.object_id=p.object_id AND ap.parameter_id=ep.ParameterId
		AND ep.SchemaName=e.SchemaName AND ep.ObjectName=e.ObjectName
	WHERE (ep.SchemaName=e.SchemaName AND ep.ObjectName=e.ObjectName OR ap.object_id=p.object_id)
	  AND (ep.ParameterId IS NULL OR ap.parameter_id IS NULL
		OR ep.ParameterName<>ap.name
		OR ep.TypeName<>TYPE_NAME(ap.system_type_id)
		OR ep.MaxLength<>ap.max_length
		OR ep.ScaleValue<>ap.scale
		OR ep.IsOutput<>ap.is_output)
) mismatch;

SELECT N'POST_DEPLOY_PROCEDURE_SIGNATURE' AS Section,SchemaName,ObjectName,StatusCode,Details
FROM @ProcedureResults ORDER BY SchemaName,ObjectName;

SELECT N'ACTUAL_PARAMETER_METADATA' AS Section,s.name AS SchemaName,p.name AS ProcedureName,
	   prm.parameter_id AS ParameterId,prm.name AS ParameterName,TYPE_NAME(prm.system_type_id) AS TypeName,
	   prm.max_length AS MaxLengthBytes,prm.scale AS ScaleValue,prm.is_output AS IsOutput
FROM @ExpectedProcedures e
JOIN sys.schemas s ON s.name=e.SchemaName
JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=e.ObjectName
JOIN sys.parameters prm ON prm.object_id=p.object_id AND prm.parameter_id>0
ORDER BY s.name,p.name,prm.parameter_id;

SELECT N'RUNTIME_ROLE_MEMBERS' AS Section,member.name AS MemberName,role.name AS RoleName
FROM sys.database_role_members rm
JOIN sys.database_principals role ON role.principal_id=rm.role_principal_id
JOIN sys.database_principals member ON member.principal_id=rm.member_principal_id
WHERE role.name=N'klop_app_runtime';
IF NOT EXISTS
(
	SELECT 1 FROM sys.database_role_members rm JOIN sys.database_principals role ON role.principal_id=rm.role_principal_id
	WHERE role.name=N'klop_app_runtime'
)
	SELECT N'RUNTIME_ROLE_MEMBERS' AS Section,CAST(NULL AS SYSNAME) AS MemberName,N'BLOCKED: role has no members' AS RoleName;

SELECT N'REQUIRED_EXECUTE_GRANTS' AS Section,e.SchemaName,e.ObjectName,
	   CASE WHEN EXISTS
	   (
		   SELECT 1 FROM sys.database_permissions dp
		   JOIN sys.schemas s ON s.name=e.SchemaName
		   JOIN sys.objects o ON o.schema_id=s.schema_id AND o.name=e.ObjectName
		   WHERE dp.class=1 AND dp.major_id=o.object_id AND dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
			 AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')
	   ) THEN 'PASS' ELSE 'FAIL' END AS Status
FROM @ExpectedProcedures e ORDER BY e.SchemaName,e.ObjectName;

SELECT N'RUNTIME_DIRECT_TABLE_DML_GRANTS' AS Section,grantee.name AS GranteeName,
	   dp.state_desc,dp.permission_name,COALESCE(OBJECT_SCHEMA_NAME(dp.major_id),SCHEMA_NAME(dp.major_id),N'<database>') AS SecurableSchema,
	   COALESCE(OBJECT_NAME(dp.major_id),N'<schema/database scope>') AS SecurableName
FROM sys.database_permissions dp
JOIN sys.database_principals grantee ON grantee.principal_id=dp.grantee_principal_id
WHERE dp.permission_name IN(N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'CONTROL',N'ALTER')
	AND dp.state IN('G','W')
  AND
  (
	  grantee.principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
	  OR grantee.principal_id IN
	  (
		  SELECT rm.member_principal_id FROM sys.database_role_members rm
		  WHERE rm.role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
	  )
  )
  AND (dp.class=0 OR dp.class=3 OR (dp.class=1 AND dp.major_id IN(SELECT object_id FROM sys.tables)));

SELECT N'RUNTIME_PRIVILEGE_REVIEW' AS Section,
	   N'Metadata grants do not establish effective permissions; execute the permission checks under the actual API identity. Reconcile all 20 mapped procedures, not only the nine new procedures, and ensure the runtime principal is not in broad roles.' AS RequiredAction;

SELECT N'FUNCTIONAL_VALIDATION' AS Section,
	   N'NOT PROVEN: signature/object/grant checks do not validate transactions, isolation, refresh replay protection, audit atomicity, or endpoint behavior. Run guarded integration tests against an isolated Development clone.' AS Status;

IF EXISTS (SELECT 1 FROM @ProcedureResults WHERE StatusCode<>'PASS')
	THROW 51520, 'Post-deployment verification found missing procedures or signature mismatches. Do not enable API auth/session traffic.', 1;
GO
