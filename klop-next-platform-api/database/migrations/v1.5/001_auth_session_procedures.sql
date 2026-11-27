-- KLOP PLATFORM v1.5 DRAFT. Adds the nine v1.3 auth/session procedures missing in the Development catalog check.
-- DBA review and approved isolated Development deployment are required. Never run automatically or in Production.
-- Execute from the repository root in sqlcmd mode; the procedure bodies remain in the unchanged v1.3 source artifact.
:on error exit
:r database\validation\v1.5_001_auth_session_preflight_READONLY.sql
SET XACT_ABORT ON;
DECLARE @LockResult INT;
BEGIN TRANSACTION;
EXEC @LockResult = sys.sp_getapplock
	@Resource = N'KLOP.Platform.v1.5.AuthSessionProcedures',
	@LockMode = N'Exclusive',
	@LockOwner = N'Transaction',
	@LockTimeout = 10000;
IF @LockResult < 0
	THROW 51510, 'Could not acquire the auth/session migration application lock.', 1;

IF EXISTS
(
	SELECT 1
	FROM (VALUES
		(N'iam',N'usp_GetLocalLoginCandidate'),
		(N'iam',N'usp_RecordLocalLoginFailure'),
		(N'iam',N'usp_IssueEmailVerificationChallenge'),
		(N'iam',N'usp_CreateAuthSession'),
		(N'iam',N'usp_ValidateSessionAccess'),
		(N'iam',N'usp_RotateRefreshToken'),
		(N'iam',N'usp_RevokeAuthSession'),
		(N'iam',N'usp_GetUserProfile'),
		(N'ten',N'usp_ListMyTenants')
	) AS target(SchemaName,ObjectName)
	JOIN sys.schemas AS schemaInfo ON schemaInfo.name = target.SchemaName
	JOIN sys.objects AS existingObject
	  ON existingObject.schema_id = schemaInfo.schema_id
	 AND existingObject.name = target.ObjectName
)
	THROW 51511, 'Migration stopped: a target object appeared after preflight; inspect it before applying.', 1;
GO
:r sql\100_auth_session_delta.sql
IF @@TRANCOUNT <> 1
	THROW 51512, 'Migration transaction state changed unexpectedly.', 1;

DECLARE @CreatedCount INT;
SELECT @CreatedCount = COUNT(*)
FROM (VALUES
	(N'iam',N'usp_GetLocalLoginCandidate'),
	(N'iam',N'usp_RecordLocalLoginFailure'),
	(N'iam',N'usp_IssueEmailVerificationChallenge'),
	(N'iam',N'usp_CreateAuthSession'),
	(N'iam',N'usp_ValidateSessionAccess'),
	(N'iam',N'usp_RotateRefreshToken'),
	(N'iam',N'usp_RevokeAuthSession'),
	(N'iam',N'usp_GetUserProfile'),
	(N'ten',N'usp_ListMyTenants')
) AS target(SchemaName,ObjectName)
JOIN sys.schemas AS schemaInfo ON schemaInfo.name = target.SchemaName
JOIN sys.procedures AS createdProcedure
  ON createdProcedure.schema_id = schemaInfo.schema_id
 AND createdProcedure.name = target.ObjectName;

IF @CreatedCount <> 9
	THROW 51513, 'Migration verification failed; all nine procedures were not created.', 1;

COMMIT TRANSACTION;
GO
