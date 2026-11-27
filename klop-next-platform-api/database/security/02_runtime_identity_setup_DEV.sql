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
DECLARE @RuntimeLoginId int=SUSER_ID(@RuntimeLogin);
DECLARE @RuntimeUserId int=DATABASE_PRINCIPAL_ID(@RuntimeUser);
DECLARE @RuntimeRoleId int=DATABASE_PRINCIPAL_ID(N'klop_app_runtime');
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52510,'Refused: Development environment and reviewed server are required.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52511,'Refused: this script is restricted to KlopPlatformDB, not a test or Production database.',1;
IF @RuntimeUser<>N'KLOP_PLATFORM_API_DEV'
	THROW 52512,'Refused: use the exact mapped Development database user.',1;
IF LEFT(@RuntimeLogin,8)=N'REPLACE_' OR @RuntimeLoginId IS NULL
BEGIN
	IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
	BEGIN
		SELECT N'DRY RUN - NO CHANGES' AS Status,DB_NAME() AS DatabaseName,
			N'Choose and pre-create the approved individual Windows login, then re-run with its exact name.' AS MissingPrerequisite,
			@RuntimeUser AS ProposedDatabaseUser;
		RETURN;
	END;
	THROW 52513,'Refused: approved Windows login must already exist before applying changes.',1;
END;
IF NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE principal_id=@RuntimeLoginId AND type=N'U' AND is_disabled=0)
	THROW 52513,'Refused: pre-create an enabled individual Windows login; SQL logins and Windows groups are not accepted.',1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'serveradmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'securityadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'setupadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'processadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'diskadmin',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'dbcreator',@RuntimeLogin),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'bulkadmin',@RuntimeLogin),1)<>0
	THROW 52514,'Refused: runtime login or resolved Windows membership has a server role.',1;
IF @RuntimeUser IN(N'dbo',N'guest',N'public',N'sys',N'INFORMATION_SCHEMA')
	THROW 52515,'Refused: reserved database user name.',1;
IF @RuntimeRoleId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE principal_id=@RuntimeRoleId AND type=N'R')
	THROW 52516,'Refused: klop_app_runtime exists but is not a database role.',1;
IF @RuntimeUserId IS NOT NULL AND
   (SELECT sid FROM sys.database_principals WHERE principal_id=@RuntimeUserId)<>SUSER_SID(@RuntimeLogin)
	THROW 52517,'Refused: existing database user is not mapped to the approved Windows login.',1;
IF @RuntimeUserId IS NOT NULL AND EXISTS
(
	SELECT 1 FROM sys.database_role_members rm JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
	WHERE rm.member_principal_id=@RuntimeUserId AND r.name<>N'klop_app_runtime'
)
	THROW 52518,'Refused: runtime database user has other role memberships; DBA review required.',1;
IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
	SELECT 1 FROM sys.database_role_members rm WHERE rm.member_principal_id=@RuntimeRoleId
)
	THROW 52519,'Refused: runtime role is nested in another role; DBA review required.',1;

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
	THROW 52520,'Refused: one or more reviewed application procedures is missing.',1;
IF @RuntimeUserId IS NOT NULL AND EXISTS
(
	SELECT 1 FROM sys.database_permissions dp WHERE dp.grantee_principal_id=@RuntimeUserId AND dp.state IN('G','W')
)
	THROW 52521,'Refused: runtime user has direct GRANTs; reconcile manually without revoking existing permissions.',1;
IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
	SELECT 1 FROM sys.database_permissions dp
	WHERE dp.grantee_principal_id=@RuntimeRoleId AND dp.state IN('G','W')
	  AND NOT (dp.permission_name=N'EXECUTE' AND dp.class=1 AND EXISTS
		  (SELECT 1 FROM @Mapped m JOIN sys.schemas s ON s.name=m.SchemaName
		   JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=m.ObjectName WHERE p.object_id=dp.major_id))
)
	THROW 52522,'Refused: runtime role has grants outside the reviewed object-level EXECUTE allowlist.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_permissions dp
	WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'public') AND dp.state IN('G','W')
	  AND dp.permission_name IN(N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'EXECUTE',N'CONTROL',N'ALTER',N'IMPERSONATE',N'TAKE OWNERSHIP')
	  AND dp.class IN(0,1,3)
	  AND (dp.class<>1 OR dp.major_id IN(SELECT t.object_id FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
										 WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')))
)
	THROW 52523,'Refused: public has a broad or application-table permission; DBA review required.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_permissions dp
	JOIN sys.database_principals p ON p.principal_id=dp.grantee_principal_id
	JOIN sys.procedures appProc ON dp.class=1 AND appProc.object_id=dp.major_id
	JOIN sys.schemas s ON s.schema_id=appProc.schema_id
	WHERE p.name=N'public' AND s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
	  AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')
)
	THROW 52527,'Refused: public has explicit EXECUTE on an application procedure; review inherited procedure access.',1;
IF (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))<>5
   OR EXISTS(SELECT 1 FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud') AND USER_NAME(principal_id)<>N'dbo')
	THROW 52524,'Refused: application schemas must exist and retain reviewed dbo ownership.',1;
IF EXISTS(SELECT 1 FROM sys.databases WHERE database_id=DB_ID() AND (is_db_chaining_on=1 OR is_trustworthy_on=1))
	THROW 52525,'Refused: cross-database chaining and TRUSTWORTHY must remain disabled.',1;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
	SELECT N'DRY RUN - NO CHANGES' AS Status,DB_NAME() AS DatabaseName,@RuntimeLogin AS ProposedWindowsLogin,
		@RuntimeUser AS ProposedDatabaseUser,
		CASE WHEN @RuntimeRoleId IS NULL THEN N'Would create role' ELSE N'Role exists; preserve current grants' END AS RoleAction,
		CASE WHEN @RuntimeUserId IS NULL THEN N'Would create mapped user' ELSE N'User mapping exists' END AS UserAction,
		N'Would add user to klop_app_runtime; object grants are handled only by script 03.' AS MembershipAction,
		N'Provide DBA-approved ticket and set KLOP_APPLY_CHANGES=APPROVED only for the reviewed execution.' AS ApprovalRequired;
	RETURN;
END;

DECLARE @Sql nvarchar(max);
BEGIN TRY
	BEGIN TRANSACTION;
	IF @RuntimeRoleId IS NULL EXEC(N'CREATE ROLE [klop_app_runtime] AUTHORIZATION [dbo];');
	IF @RuntimeUserId IS NULL
	BEGIN
		SET @Sql=N'CREATE USER '+QUOTENAME(@RuntimeUser)+N' FOR LOGIN '+QUOTENAME(@RuntimeLogin)+N';';
		EXEC sys.sp_executesql @Sql;
	END;
	IF NOT EXISTS(SELECT 1 FROM sys.database_role_members
				  WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
					AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser))
	BEGIN
		SET @Sql=N'ALTER ROLE [klop_app_runtime] ADD MEMBER '+QUOTENAME(@RuntimeUser)+N';';
		EXEC sys.sp_executesql @Sql;
	END;
	IF (SELECT sid FROM sys.database_principals WHERE principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser))<>SUSER_SID(@RuntimeLogin)
	   OR NOT EXISTS(SELECT 1 FROM sys.database_role_members
					 WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
					   AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser))
		THROW 52526,'Post-check failed: database mapping or runtime role membership is incorrect.',1;
	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;
SELECT N'PASS' AS SetupStatus,DB_NAME() AS DatabaseName,@RuntimeUser AS DatabaseUser,
	N'Role/user mapping only; no EXECUTE grants, table permissions, or server login were changed.' AS Scope;
GO
