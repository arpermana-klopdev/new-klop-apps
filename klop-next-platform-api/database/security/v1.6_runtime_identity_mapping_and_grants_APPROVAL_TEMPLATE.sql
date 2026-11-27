:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_LOGIN "REPLACE_WITH_APPROVED_WINDOWS_SERVICE_LOGIN"
:setvar KLOP_RUNTIME_USER "KLOP_PLATFORM_API_DEV"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- APPROVAL REQUIRED. NOT EXECUTED during diagnosis.
-- This template does not create a SQL Server login or role, grant server/database/table rights,
-- modify Production, or alter the frozen database baseline. It only maps a pre-existing,
-- dedicated non-admin Windows login and grants EXECUTE on the reviewed API procedures.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @RuntimeLogin sysname=N'$(KLOP_RUNTIME_LOGIN)';
DECLARE @RuntimeUser sysname=N'$(KLOP_RUNTIME_USER)';
DECLARE @ApprovalTicket nvarchar(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges nvarchar(20)=N'$(KLOP_APPLY_CHANGES)';

IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52600,'Refused: this template is restricted to the reviewed Development SQL Server.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52601,'Refused: this template is restricted to Development database KlopPlatformDB.',1;
IF @RuntimeUser<>N'KLOP_PLATFORM_API_DEV'
	THROW 52602,'Refused: use the exact approved Development database user name.',1;
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
	SELECT N'NO CHANGES' AS Status,
		N'Set APPROVED and provide the approved change ticket only after DBA review.' AS ApprovalRequired,
		@RuntimeLogin AS ProposedPreExistingWindowsLogin,
		@RuntimeUser AS ProposedDatabaseUser;
	RETURN;
END;

IF LEFT(@RuntimeLogin,8)=N'REPLACE_' OR SUSER_ID(@RuntimeLogin) IS NULL
	THROW 52603,'Refused: specify an already-provisioned Windows login; this script never creates logins.',1;
IF NOT EXISTS
(
	SELECT 1 FROM sys.server_principals
	WHERE name=@RuntimeLogin AND type=N'U' AND is_disabled=0
)
	THROW 52604,'Refused: runtime login must be an enabled individual Windows login, not a SQL login or group.',1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'serveradmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'securityadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'setupadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'processadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'diskadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'dbcreator',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'bulkadmin',@RuntimeLogin),1)<>0
	THROW 52605,'Refused: runtime login or resolved Windows membership has a SQL Server fixed-role membership.',1;

DECLARE @RoleId int=DATABASE_PRINCIPAL_ID(N'klop_app_runtime');
DECLARE @UserId int=DATABASE_PRINCIPAL_ID(@RuntimeUser);
IF @RoleId IS NULL OR NOT EXISTS
(
	SELECT 1 FROM sys.database_principals WHERE principal_id=@RoleId AND type=N'R'
)
	THROW 52606,'Refused: the reviewed klop_app_runtime database role is missing or is not a role.',1;
IF @UserId IS NOT NULL AND
   (SELECT sid FROM sys.database_principals WHERE principal_id=@UserId)<>SUSER_SID(@RuntimeLogin)
	THROW 52607,'Refused: existing database user SID does not map to the approved Windows login.',1;
IF @UserId IS NOT NULL AND EXISTS
(
	SELECT 1 FROM sys.database_role_members
	WHERE member_principal_id=@UserId AND role_principal_id<>@RoleId
)
	THROW 52608,'Refused: runtime database user belongs to another database role; reconcile manually.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_role_members
	WHERE role_principal_id=@RoleId AND member_principal_id<>ISNULL(@UserId,-1)
)
	THROW 52609,'Refused: klop_app_runtime has another member; reconcile approved membership before proceeding.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_role_members WHERE member_principal_id=@RoleId
)
	THROW 52616,'Refused: klop_app_runtime is nested in another role; reconcile role nesting before proceeding.',1;
IF @UserId IS NOT NULL AND EXISTS
(
	SELECT 1 FROM sys.database_permissions
	WHERE grantee_principal_id=@UserId AND state IN('G','W')
)
	THROW 52610,'Refused: runtime user has direct GRANTs; reconcile them without revoking existing permissions.',1;

DECLARE @RequiredProcedures TABLE
(
	SchemaName sysname NOT NULL,
	ProcedureName sysname NOT NULL,
	PRIMARY KEY(SchemaName,ProcedureName)
);
INSERT @RequiredProcedures(SchemaName,ProcedureName) VALUES
	(N'iam',N'usp_RegisterLocalUser'),
	(N'iam',N'usp_ConfirmEmail'),
	(N'iam',N'usp_IssueEmailVerificationChallenge'),
	(N'iam',N'usp_GetLocalLoginCandidate'),
	(N'iam',N'usp_RecordLocalLoginFailure'),
	(N'iam',N'usp_CreateAuthSession'),
	(N'iam',N'usp_ValidateSessionAccess'),
	(N'iam',N'usp_RotateRefreshToken'),
	(N'iam',N'usp_RevokeAuthSession'),
	(N'iam',N'usp_GetUserProfile'),
	(N'iam',N'usp_AssignTenantRole'),
	(N'iam',N'usp_RevokeTenantRole'),
	(N'ten',N'usp_ListMyTenants'),
	(N'ten',N'usp_CreateTenantWithOwner'),
	(N'ten',N'usp_InviteExistingUser'),
	(N'ten',N'usp_AcceptMembership'),
	(N'ten',N'usp_RemoveTenantMember'),
	(N'mst',N'usp_OrganizationType_GetAll'),
	(N'mst',N'usp_TenantType_GetAll'),
	(N'cfg',N'usp_Configuration_GetByKey'),
	(N'reg',N'usp_GetMyApplication'),
	(N'reg',N'usp_GetApplicationForOwner'),
	(N'reg',N'usp_SavePersonalDraft'),
	(N'reg',N'usp_SaveOrganizationDraft'),
	(N'reg',N'usp_GetOrganizationRequirements'),
	(N'reg',N'usp_SubmitOnboarding'),
	(N'leg',N'usp_GetCurrentTerms'),
	(N'leg',N'usp_GetPublicTermsFile');

IF EXISTS
(
	SELECT 1 FROM @RequiredProcedures r
	LEFT JOIN sys.schemas s ON s.name=r.SchemaName
	LEFT JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ProcedureName
	WHERE p.object_id IS NULL
)
	THROW 52611,'Refused: one or more reviewed API procedures is missing; reconcile/deploy the v1.6 objects first.',1;
IF (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>7
   OR EXISTS
   (
	   SELECT 1 FROM sys.schemas
	   WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg')
		 AND USER_NAME(principal_id)<>N'dbo'
   )
	THROW 52612,'Refused: application schemas are missing or do not have the reviewed dbo owner.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_permissions dp
	WHERE dp.grantee_principal_id=@RoleId AND dp.state IN('G','W')
	  AND NOT
	  (
		  dp.permission_name=N'EXECUTE' AND dp.class=1 AND EXISTS
		  (
			  SELECT 1 FROM @RequiredProcedures r
			  JOIN sys.schemas s ON s.name=r.SchemaName
			  JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ProcedureName
			  WHERE p.object_id=dp.major_id
		  )
	  )
)
	THROW 52613,'Refused: runtime role has a GRANT outside the reviewed object-level EXECUTE allowlist.',1;

BEGIN TRY
	BEGIN TRANSACTION;

	IF @UserId IS NULL
	BEGIN
		DECLARE @CreateUserSql nvarchar(max)=N'CREATE USER '+QUOTENAME(@RuntimeUser)+N' FOR LOGIN '+QUOTENAME(@RuntimeLogin)+N';';
		EXEC sys.sp_executesql @CreateUserSql;
	END;

	IF NOT EXISTS
	(
		SELECT 1 FROM sys.database_role_members
		WHERE role_principal_id=@RoleId AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser)
	)
	BEGIN
		DECLARE @AddMemberSql nvarchar(max)=N'ALTER ROLE [klop_app_runtime] ADD MEMBER '+QUOTENAME(@RuntimeUser)+N';';
		EXEC sys.sp_executesql @AddMemberSql;
	END;

	DECLARE @SchemaName sysname,@ProcedureName sysname,@GrantSql nvarchar(max);
	DECLARE GrantCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT SchemaName,ProcedureName FROM @RequiredProcedures ORDER BY SchemaName,ProcedureName;
	OPEN GrantCursor;
	FETCH NEXT FROM GrantCursor INTO @SchemaName,@ProcedureName;
	WHILE @@FETCH_STATUS=0
	BEGIN
		SET @GrantSql=N'GRANT EXECUTE ON OBJECT::'+QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@ProcedureName)+N' TO [klop_app_runtime];';
		EXEC sys.sp_executesql @GrantSql;
		FETCH NEXT FROM GrantCursor INTO @SchemaName,@ProcedureName;
	END;
	CLOSE GrantCursor;
	DEALLOCATE GrantCursor;

	IF NOT EXISTS
	(
		SELECT 1 FROM sys.database_role_members
		WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
		  AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser)
	)
		THROW 52614,'Post-check failed: approved database user is not a runtime-role member.',1;
	IF EXISTS
	(
		SELECT 1 FROM @RequiredProcedures r
		JOIN sys.schemas s ON s.name=r.SchemaName
		JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ProcedureName
		WHERE NOT EXISTS
		(
			SELECT 1 FROM sys.database_permissions dp
			WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
			  AND dp.class=1 AND dp.major_id=p.object_id
			  AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')
		)
	)
		THROW 52615,'Post-check failed: one or more reviewed procedure EXECUTE grants is missing.',1;

	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	IF CURSOR_STATUS('local','GrantCursor')>=0 CLOSE GrantCursor;
	IF CURSOR_STATUS('local','GrantCursor')>-3 DEALLOCATE GrantCursor;
	IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;

SELECT N'PASS' AS MappingAndGrantStatus,
	DB_NAME() AS DatabaseName,
	@RuntimeLogin AS ApprovedWindowsLogin,
	@RuntimeUser AS MappedDatabaseUser,
	(SELECT COUNT(*) FROM @RequiredProcedures) AS ReviewedObjectExecuteCount;
GO
