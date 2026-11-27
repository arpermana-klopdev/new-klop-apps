:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_LOGIN "REPLACE_WITH_APPROVED_WINDOWS_SERVICE_LOGIN"
:setvar KLOP_RUNTIME_USER "KLOP_PLATFORM_API_DEV"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

SET NOCOUNT ON;
DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @RuntimeLogin sysname=N'$(KLOP_RUNTIME_LOGIN)';
DECLARE @RuntimeUser sysname=N'$(KLOP_RUNTIME_USER)';
DECLARE @ApprovalTicket nvarchar(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges nvarchar(20)=N'$(KLOP_APPLY_CHANGES)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52530,'Refused: Development environment and reviewed server are required.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52531,'Refused: this script is restricted to KlopPlatformDB.',1;
IF @RuntimeUser<>N'KLOP_PLATFORM_API_DEV'
	THROW 52532,'Refused: specify the exact mapped Development database user.',1;
IF LEFT(@RuntimeLogin,8)=N'REPLACE_' OR SUSER_ID(@RuntimeLogin) IS NULL
   OR DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL OR DATABASE_PRINCIPAL_ID(@RuntimeUser) IS NULL
BEGIN
	IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
	BEGIN
		SELECT N'DRY RUN - NO CHANGES' AS Status,
			N'Pre-created individual Windows login plus completed script 02 setup are required before the grant plan can be reviewed.' AS MissingPrerequisite,
			@RuntimeLogin AS ProposedLogin,@RuntimeUser AS ProposedDatabaseUser;
		RETURN;
	END;
	THROW 52533,'Refused: approved Windows login and script-02 identity setup must exist before applying grants.',1;
END;
IF NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE name=@RuntimeLogin AND type=N'U' AND is_disabled=0)
	THROW 52533,'Refused: the approved Windows login must already exist and be enabled.',1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'serveradmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'securityadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'setupadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'processadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'diskadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'dbcreator',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'bulkadmin',@RuntimeLogin),1)<>0
	THROW 52534,'Refused: runtime login or resolved Windows membership has a server role.',1;
IF (SELECT sid FROM sys.database_principals WHERE principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser))<>SUSER_SID(@RuntimeLogin)
	THROW 52536,'Refused: runtime user SID does not map to the approved Windows login.',1;
IF NOT EXISTS(SELECT 1 FROM sys.database_role_members
			  WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
				AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser))
	THROW 52537,'Refused: approved runtime user is not a member of klop_app_runtime.',1;
IF EXISTS(SELECT 1 FROM sys.database_role_members rm JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
		  WHERE rm.member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser) AND r.name<>N'klop_app_runtime')
	THROW 52538,'Refused: runtime user belongs to another database role.',1;

DECLARE @Mapped TABLE(SchemaName sysname NOT NULL,ObjectName sysname NOT NULL PRIMARY KEY(SchemaName,ObjectName));
INSERT @Mapped VALUES
(N'cfg',N'usp_Configuration_GetByKey'),(N'mst',N'usp_TenantType_GetAll'),(N'mst',N'usp_OrganizationType_GetAll'),
(N'iam',N'usp_RegisterLocalUser'),(N'iam',N'usp_ConfirmEmail'),(N'ten',N'usp_CreateTenantWithOwner'),
(N'ten',N'usp_InviteExistingUser'),(N'ten',N'usp_AcceptMembership'),(N'ten',N'usp_RemoveTenantMember'),
(N'iam',N'usp_AssignTenantRole'),(N'iam',N'usp_RevokeTenantRole'),(N'iam',N'usp_GetLocalLoginCandidate'),
(N'iam',N'usp_RecordLocalLoginFailure'),(N'iam',N'usp_IssueEmailVerificationChallenge'),
(N'iam',N'usp_CreateAuthSession'),(N'iam',N'usp_ValidateSessionAccess'),(N'iam',N'usp_RotateRefreshToken'),
(N'iam',N'usp_RevokeAuthSession'),(N'iam',N'usp_GetUserProfile'),(N'ten',N'usp_ListMyTenants');
IF EXISTS(SELECT 1 FROM @Mapped m LEFT JOIN sys.schemas s ON s.name=m.SchemaName
		  LEFT JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=m.ObjectName WHERE p.object_id IS NULL)
	THROW 52539,'Refused: one or more mapped procedures is missing.',1;
IF EXISTS(SELECT 1 FROM sys.database_permissions dp
		  WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser) AND dp.state IN('G','W'))
	THROW 52540,'Refused: runtime user has direct GRANTs; DBA review required.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_permissions dp
	WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime') AND dp.state IN('G','W')
	  AND NOT (dp.permission_name=N'EXECUTE' AND dp.class=1 AND EXISTS
		  (SELECT 1 FROM @Mapped m JOIN sys.schemas s ON s.name=m.SchemaName
		   JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=m.ObjectName WHERE p.object_id=dp.major_id))
)
	THROW 52541,'Refused: role has a grant outside the 20-object EXECUTE allowlist.',1;

SELECT N'GRANT_PLAN' AS Section,m.SchemaName,m.ObjectName,
	CASE WHEN EXISTS(SELECT 1 FROM sys.database_permissions dp JOIN sys.schemas s ON s.name=m.SchemaName
					 JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=m.ObjectName
					 WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
					   AND dp.class=1 AND dp.major_id=p.object_id AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W'))
		 THEN N'PRESERVE EXISTING EXPLICIT GRANT' ELSE N'WOULD ADD OBJECT-LEVEL EXECUTE' END AS PlannedAction
FROM @Mapped m ORDER BY m.SchemaName,m.ObjectName;
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
	SELECT N'DRY RUN - NO CHANGES' AS Status,
		N'For rollback, record only the comma-separated SchemaName.ObjectName entries output as newly granted after approved execution.' AS RollbackEvidence;
	RETURN;
END;

BEGIN TRY
	BEGIN TRANSACTION;
	DECLARE @Schema sysname,@Object sysname,@Sql nvarchar(max);
	DECLARE @NewlyGranted TABLE(SchemaName sysname NOT NULL,ObjectName sysname NOT NULL PRIMARY KEY(SchemaName,ObjectName));
	DECLARE GrantCursor CURSOR LOCAL FAST_FORWARD FOR SELECT SchemaName,ObjectName FROM @Mapped ORDER BY SchemaName,ObjectName;
	OPEN GrantCursor;
	FETCH NEXT FROM GrantCursor INTO @Schema,@Object;
	WHILE @@FETCH_STATUS=0
	BEGIN
		IF NOT EXISTS
		(
			SELECT 1 FROM sys.database_permissions dp JOIN sys.schemas s ON s.name=@Schema
			JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=@Object
			WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
			  AND dp.class=1 AND dp.major_id=p.object_id AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')
		)
		BEGIN
			SET @Sql=N'GRANT EXECUTE ON OBJECT::'+QUOTENAME(@Schema)+N'.'+QUOTENAME(@Object)+N' TO [klop_app_runtime];';
			EXEC sys.sp_executesql @Sql;
			INSERT @NewlyGranted VALUES(@Schema,@Object);
		END;
		FETCH NEXT FROM GrantCursor INTO @Schema,@Object;
	END;
	CLOSE GrantCursor;
	DEALLOCATE GrantCursor;
	IF EXISTS
	(
		SELECT 1 FROM @Mapped m JOIN sys.schemas s ON s.name=m.SchemaName JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=m.ObjectName
		WHERE NOT EXISTS(SELECT 1 FROM sys.database_permissions dp
						 WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
						   AND dp.class=1 AND dp.major_id=p.object_id AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W'))
	) THROW 52542,'Post-check failed: one or more object-level grants is missing.',1;
	IF EXISTS
	(
		SELECT 1 FROM sys.database_permissions dp WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
		  AND dp.state IN('G','W') AND NOT (dp.permission_name=N'EXECUTE' AND dp.class=1 AND dp.major_id IN
			  (SELECT p.object_id FROM @Mapped m JOIN sys.schemas s ON s.name=m.SchemaName JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=m.ObjectName))
	) THROW 52543,'Post-check failed: an out-of-allowlist grant exists.',1;
	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	IF CURSOR_STATUS('local','GrantCursor')>=0 CLOSE GrantCursor;
	IF CURSOR_STATUS('local','GrantCursor')>-3 DEALLOCATE GrantCursor;
	IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;

SELECT N'PASS' AS GrantStatus,COUNT(*) AS ExplicitObjectExecuteGrantCount
FROM sys.database_permissions dp
WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
  AND dp.class=1 AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W');
SELECT N'ROLLBACK_MANIFEST' AS Section,
	COALESCE(STRING_AGG(CONVERT(nvarchar(max),m.SchemaName+N'.'+m.ObjectName),N',') WITHIN GROUP (ORDER BY m.SchemaName,m.ObjectName),N'<none>') AS NewlyGrantedObjects
FROM @NewlyGranted m;
GO
