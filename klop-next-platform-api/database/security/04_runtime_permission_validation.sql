:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_LOGIN "REPLACE_WITH_APPROVED_WINDOWS_SERVICE_LOGIN"
:setvar KLOP_RUNTIME_USER "KLOP_PLATFORM_API_DEV"

SET NOCOUNT ON;
DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ExpectedLogin sysname=N'$(KLOP_RUNTIME_LOGIN)';
DECLARE @ExpectedUser sysname=N'$(KLOP_RUNTIME_USER)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52550,'Validation refused: Development server/environment mismatch.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52551,'Validation refused: connect directly to KlopPlatformDB.',1;

SELECT N'ACTUAL_CONNECTION_IDENTITY' AS Section,@@SERVERNAME AS ServerName,DB_NAME() AS DatabaseName,
	ORIGINAL_LOGIN() AS OriginalLogin,SUSER_SNAME() AS EffectiveLogin,USER_NAME() AS DatabaseUser,
	IS_SRVROLEMEMBER(N'sysadmin') AS IsSysadmin,IS_ROLEMEMBER(N'db_owner') AS IsDbOwner,
	IS_ROLEMEMBER(N'db_ddladmin') AS IsDbDdlAdmin,IS_ROLEMEMBER(N'db_datareader') AS IsDbDataReader,
	IS_ROLEMEMBER(N'db_datawriter') AS IsDbDataWriter,IS_ROLEMEMBER(N'klop_app_runtime') AS IsRuntimeRoleMember,
	HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CONNECT') AS CanConnect;
IF @ExpectedLogin LIKE N'REPLACE_%' OR ORIGINAL_LOGIN()<>@ExpectedLogin OR SUSER_SNAME()<>@ExpectedLogin OR USER_NAME()<>@ExpectedUser
	THROW 52552,'Validation failed: this is not the approved, non-impersonated API runtime connection.',1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),1)<>0 OR ISNULL(IS_SRVROLEMEMBER(N'serveradmin'),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'securityadmin'),1)<>0 OR ISNULL(IS_SRVROLEMEMBER(N'setupadmin'),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'processadmin'),1)<>0 OR ISNULL(IS_SRVROLEMEMBER(N'diskadmin'),1)<>0
   OR ISNULL(IS_SRVROLEMEMBER(N'dbcreator'),1)<>0 OR ISNULL(IS_SRVROLEMEMBER(N'bulkadmin'),1)<>0
   OR ISNULL(IS_ROLEMEMBER(N'db_owner'),1)<>0 OR ISNULL(IS_ROLEMEMBER(N'db_ddladmin'),1)<>0
   OR ISNULL(IS_ROLEMEMBER(N'db_datareader'),1)<>0 OR ISNULL(IS_ROLEMEMBER(N'db_datawriter'),1)<>0
   OR ISNULL(IS_ROLEMEMBER(N'db_securityadmin'),1)<>0 OR ISNULL(IS_ROLEMEMBER(N'db_accessadmin'),1)<>0
   OR ISNULL(IS_ROLEMEMBER(N'db_backupoperator'),1)<>0 OR ISNULL(IS_ROLEMEMBER(N'klop_app_runtime'),0)<>1
   OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CONNECT'),0)<>1
	THROW 52553,'Validation failed: runtime principal is elevated, missing runtime role, or cannot connect.',1;
IF EXISTS(SELECT 1 FROM sys.database_role_members rm JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
		  WHERE rm.member_principal_id=DATABASE_PRINCIPAL_ID(@ExpectedUser) AND r.name<>N'klop_app_runtime')
	THROW 52554,'Validation failed: runtime user belongs to another database role.',1;

DECLARE @Mapped TABLE(SchemaName sysname NOT NULL,ObjectName sysname NOT NULL PRIMARY KEY(SchemaName,ObjectName));
INSERT @Mapped VALUES
(N'cfg',N'usp_Configuration_GetByKey'),(N'mst',N'usp_TenantType_GetAll'),(N'mst',N'usp_OrganizationType_GetAll'),
(N'iam',N'usp_RegisterLocalUser'),(N'iam',N'usp_ConfirmEmail'),(N'ten',N'usp_CreateTenantWithOwner'),
(N'ten',N'usp_InviteExistingUser'),(N'ten',N'usp_AcceptMembership'),(N'ten',N'usp_RemoveTenantMember'),
(N'iam',N'usp_AssignTenantRole'),(N'iam',N'usp_RevokeTenantRole'),(N'iam',N'usp_GetLocalLoginCandidate'),
(N'iam',N'usp_RecordLocalLoginFailure'),(N'iam',N'usp_IssueEmailVerificationChallenge'),
(N'iam',N'usp_CreateAuthSession'),(N'iam',N'usp_ValidateSessionAccess'),(N'iam',N'usp_RotateRefreshToken'),
(N'iam',N'usp_RevokeAuthSession'),(N'iam',N'usp_GetUserProfile'),(N'ten',N'usp_ListMyTenants');

SELECT N'EFFECTIVE_OBJECT_EXECUTE' AS Section,m.SchemaName,m.ObjectName,
	CASE WHEN OBJECT_ID(QUOTENAME(m.SchemaName)+N'.'+QUOTENAME(m.ObjectName),N'P') IS NOT NULL
		  AND HAS_PERMS_BY_NAME(QUOTENAME(m.SchemaName)+N'.'+QUOTENAME(m.ObjectName),N'OBJECT',N'EXECUTE')=1
		 THEN N'PASS' ELSE N'FAIL' END AS Status
FROM @Mapped m ORDER BY m.SchemaName,m.ObjectName;
IF EXISTS(SELECT 1 FROM @Mapped m WHERE OBJECT_ID(QUOTENAME(m.SchemaName)+N'.'+QUOTENAME(m.ObjectName),N'P') IS NULL
		  OR ISNULL(HAS_PERMS_BY_NAME(QUOTENAME(m.SchemaName)+N'.'+QUOTENAME(m.ObjectName),N'OBJECT',N'EXECUTE'),0)<>1)
	THROW 52555,'Validation failed: one or more of the 20 mapped Stored Procedures is missing or not executable.',1;
IF EXISTS
(
	SELECT 1 FROM sys.procedures p JOIN sys.schemas s ON s.schema_id=p.schema_id
	WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
	  AND HAS_PERMS_BY_NAME(QUOTENAME(s.name)+N'.'+QUOTENAME(p.name),N'OBJECT',N'EXECUTE')=1
	  AND NOT EXISTS(SELECT 1 FROM @Mapped m WHERE m.SchemaName=s.name AND m.ObjectName=p.name)
)
	THROW 52564,'Validation failed: runtime identity can execute an application procedure outside the reviewed allowlist.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_permissions dp WHERE dp.grantee_principal_id IN(DATABASE_PRINCIPAL_ID(@ExpectedUser),DATABASE_PRINCIPAL_ID(N'klop_app_runtime'))
	  AND dp.state IN('G','W') AND dp.permission_name=N'EXECUTE'
	  AND NOT (dp.class=1 AND dp.major_id IN(SELECT p.object_id FROM @Mapped m JOIN sys.schemas s ON s.name=m.SchemaName
											 JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=m.ObjectName))
)
	THROW 52556,'Validation failed: runtime user/role has EXECUTE outside the reviewed 20-object allowlist.',1;
IF EXISTS
(
	SELECT 1 FROM sys.database_permissions dp WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(@ExpectedUser)
	  AND dp.state IN('G','W') AND dp.permission_name IN(N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'CONTROL',N'ALTER',N'TAKE OWNERSHIP',N'IMPERSONATE')
	  AND dp.class IN(0,1,3)
)
	THROW 52557,'Validation failed: runtime user has direct table or broad database/schema permissions.',1;
IF EXISTS
(
	SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
	CROSS JOIN (VALUES(N'SELECT'),(N'INSERT'),(N'UPDATE'),(N'DELETE')) p(PermissionName)
	WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
	  AND ISNULL(HAS_PERMS_BY_NAME(QUOTENAME(s.name)+N'.'+QUOTENAME(t.name),N'OBJECT',p.PermissionName),0)=1
)
	THROW 52558,'Validation failed: effective direct access to an application table was found.',1;
IF EXISTS
(
	SELECT 1 FROM sys.schemas s CROSS JOIN (VALUES(N'SELECT'),(N'INSERT'),(N'UPDATE'),(N'DELETE'),(N'EXECUTE')) p(PermissionName)
	WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
	  AND ISNULL(HAS_PERMS_BY_NAME(QUOTENAME(s.name),N'SCHEMA',p.PermissionName),0)=1
)
	THROW 52559,'Validation failed: broad application-schema permission was found.',1;
IF EXISTS
(
	SELECT 1 FROM (VALUES(N'CONTROL'),(N'ALTER'),(N'TAKE OWNERSHIP'),(N'CREATE TABLE'),(N'CREATE PROCEDURE'),
		(N'ALTER ANY USER'),(N'ALTER ANY ROLE'),(N'SELECT'),(N'INSERT'),(N'UPDATE'),(N'DELETE'),(N'EXECUTE')) p(PermissionName)
	WHERE ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',p.PermissionName),0)=1
)
	THROW 52560,'Validation failed: broad database-level privilege was found.',1;
IF EXISTS(SELECT 1 FROM sys.databases WHERE database_id=DB_ID() AND (is_db_chaining_on=1 OR is_trustworthy_on=1))
	THROW 52561,'Validation failed: cross-database chaining or TRUSTWORTHY is enabled.',1;
IF (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))<>5
   OR EXISTS(SELECT 1 FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud') AND USER_NAME(principal_id)<>N'dbo')
	THROW 52562,'Validation failed: application schemas are missing or ownership chain changed.',1;

DECLARE @Config TABLE
(
	ConfigurationKey varchar(150),ConfigurationValue nvarchar(max),ValueType varchar(20),
	Category varchar(80),StorageType varchar(30),VersionNumber int,RequiresRestart bit,RowVersion binary(8)
);
DECLARE @ConfigKey varchar(150)='database.command_timeout_seconds';
INSERT @Config EXEC cfg.usp_Configuration_GetByKey @ConfigurationKey=@ConfigKey;
SELECT N'RUNTIME_SETTINGS_READ' AS Section,ConfigurationKey,ValueType,StorageType,
	CASE WHEN ValueType=N'INTEGER' AND StorageType=N'PLAIN'
		  AND TRY_CONVERT(int,ConfigurationValue) BETWEEN 1 AND 120 THEN N'PASS' ELSE N'FAIL' END AS Status
FROM @Config;
IF (SELECT COUNT(*) FROM @Config WHERE ConfigurationKey=N'database.command_timeout_seconds' AND ValueType=N'INTEGER'
	AND StorageType=N'PLAIN' AND TRY_CONVERT(int,ConfigurationValue) BETWEEN 1 AND 120)<>1
	THROW 52563,'Validation failed: runtime configuration procedure did not return valid expected settings metadata.',1;

SELECT N'PASS' AS RuntimePermissionValidation,
	N'Only config key/type/status metadata was emitted; configuration values were not selected for display.' AS SafeOutput;
GO
