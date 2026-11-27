:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_LOGIN "REPLACE_WITH_APPROVED_WINDOWS_SERVICE_LOGIN"
:setvar KLOP_RUNTIME_USER "KLOP_PLATFORM_API_DEV"

SET NOCOUNT ON;
DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @RuntimeLogin sysname=N'$(KLOP_RUNTIME_LOGIN)';
DECLARE @RuntimeUser sysname=N'$(KLOP_RUNTIME_USER)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52500,'Refused: this read-only preflight is restricted to the Development SQL instance.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52501,'Refused: connect directly to Development database KlopPlatformDB.',1;

SELECT N'CURRENT_SQL_CONNECTION_NOT_RUNTIME_PROOF' AS Section,
	@@SERVERNAME AS ServerName,DB_NAME() AS DatabaseName,
	ORIGINAL_LOGIN() AS OriginalLogin,SUSER_SNAME() AS EffectiveLogin,USER_NAME() AS DatabaseUser,
	IS_SRVROLEMEMBER(N'sysadmin') AS IsSysadmin,
	IS_ROLEMEMBER(N'db_owner') AS IsDbOwner,
	IS_ROLEMEMBER(N'db_ddladmin') AS IsDbDdlAdmin,
	IS_ROLEMEMBER(N'klop_app_runtime') AS IsRuntimeRoleMember;

SELECT N'PROPOSED_WINDOWS_LOGIN' AS Section,@RuntimeLogin AS ProposedLogin,
	sp.type_desc AS SqlServerPrincipalType,sp.is_disabled AS IsDisabled,
	SUSER_ID(@RuntimeLogin) AS PrincipalId,
	IS_SRVROLEMEMBER(N'sysadmin',@RuntimeLogin) AS IsSysadmin,
	CASE WHEN sp.principal_id IS NULL THEN N'NOT PRESENT: provision dedicated Windows login outside this package'
		 WHEN sp.type<>N'U' THEN N'REJECT: expected an individual Windows login (not SQL login or group)'
		 WHEN sp.is_disabled=1 THEN N'REJECT: login is disabled'
		 ELSE N'REVIEW Windows group nesting and service logon rights before approval' END AS PreflightStatus
FROM (VALUES(1)) seed(n)
LEFT JOIN sys.server_principals sp ON sp.name=@RuntimeLogin;

SELECT N'PROPOSED_LOGIN_SERVER_ROLE_MEMBERSHIP' AS Section,r.name AS ServerRole
FROM sys.server_role_members rm
JOIN sys.server_principals r ON r.principal_id=rm.role_principal_id
JOIN sys.server_principals login ON login.principal_id=rm.member_principal_id
WHERE login.name=@RuntimeLogin;

SELECT N'PROPOSED_DATABASE_MAPPING' AS Section,@RuntimeUser AS ProposedDatabaseUser,
	dp.type_desc AS DatabasePrincipalType,
	CASE WHEN dp.principal_id IS NULL THEN N'USER NOT CREATED'
		 WHEN dp.sid=SUSER_SID(@RuntimeLogin) THEN N'SID MATCHES LOGIN'
		 ELSE N'BLOCKED: SID DOES NOT MATCH LOGIN' END AS MappingStatus,
	r.name AS RoleName
FROM (VALUES(1)) seed(n)
LEFT JOIN sys.database_principals dp ON dp.name=@RuntimeUser
LEFT JOIN sys.database_role_members rm ON rm.member_principal_id=dp.principal_id
LEFT JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id;

DECLARE @Mapped TABLE(SchemaName sysname NOT NULL,ObjectName sysname NOT NULL PRIMARY KEY(SchemaName,ObjectName));
INSERT @Mapped VALUES
(N'cfg',N'usp_Configuration_GetByKey'),(N'mst',N'usp_TenantType_GetAll'),(N'mst',N'usp_OrganizationType_GetAll'),
(N'iam',N'usp_RegisterLocalUser'),(N'iam',N'usp_ConfirmEmail'),(N'ten',N'usp_CreateTenantWithOwner'),
(N'ten',N'usp_InviteExistingUser'),(N'ten',N'usp_AcceptMembership'),(N'ten',N'usp_RemoveTenantMember'),
(N'iam',N'usp_AssignTenantRole'),(N'iam',N'usp_RevokeTenantRole'),(N'iam',N'usp_GetLocalLoginCandidate'),
(N'iam',N'usp_RecordLocalLoginFailure'),(N'iam',N'usp_IssueEmailVerificationChallenge'),
(N'iam',N'usp_CreateAuthSession'),(N'iam',N'usp_ValidateSessionAccess'),(N'iam',N'usp_RotateRefreshToken'),
(N'iam',N'usp_RevokeAuthSession'),(N'iam',N'usp_GetUserProfile'),(N'ten',N'usp_ListMyTenants');

SELECT N'MAPPED_PROCEDURE' AS Section,m.SchemaName,m.ObjectName,
	CASE WHEN o.object_id IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS CatalogStatus,
	CASE WHEN EXISTS(SELECT 1 FROM sys.database_permissions dp
					 WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
					   AND dp.class=1 AND dp.major_id=o.object_id
					   AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W'))
		 THEN N'EXPLICIT ROLE GRANT' ELSE N'NO EXPLICIT ROLE GRANT' END AS RuntimeRoleGrant,
	HAS_PERMS_BY_NAME(QUOTENAME(m.SchemaName)+N'.'+QUOTENAME(m.ObjectName),N'OBJECT',N'EXECUTE')
		AS CurrentConnectionEffectiveExecute_NotRuntimeProof
FROM @Mapped m
LEFT JOIN sys.schemas s ON s.name=m.SchemaName
LEFT JOIN sys.procedures o ON o.schema_id=s.schema_id AND o.name=m.ObjectName
ORDER BY m.SchemaName,m.ObjectName;

SELECT N'RUNTIME_ROLE_MEMBERS' AS Section,member.name AS MemberName,member.type_desc AS MemberType
FROM sys.database_role_members rm
JOIN sys.database_principals role ON role.principal_id=rm.role_principal_id
JOIN sys.database_principals member ON member.principal_id=rm.member_principal_id
WHERE role.name=N'klop_app_runtime';
IF NOT EXISTS(SELECT 1 FROM sys.database_role_members rm
			  JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
			  WHERE r.name=N'klop_app_runtime')
	SELECT N'RUNTIME_ROLE_MEMBERS' AS Section,CAST(NULL AS sysname) AS MemberName,N'ROLE HAS NO MEMBERS' AS MemberType;

SELECT N'RUNTIME_ROLE_PERMISSION' AS Section,dp.state_desc,dp.permission_name,
	COALESCE(OBJECT_SCHEMA_NAME(dp.major_id),SCHEMA_NAME(dp.major_id),N'<database>') AS SecurableSchema,
	COALESCE(OBJECT_NAME(dp.major_id),N'<schema/database scope>') AS SecurableName
FROM sys.database_permissions dp
JOIN sys.database_principals r ON r.principal_id=dp.grantee_principal_id
WHERE r.name=N'klop_app_runtime'
ORDER BY dp.state_desc,dp.permission_name,SecurableSchema,SecurableName;

SELECT N'ENVIRONMENT_FLAGS' AS Section,d.is_db_chaining_on AS CrossDatabaseChainingEnabled,
	d.is_trustworthy_on AS TrustworthyEnabled,
	(SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')) AS AppSchemaCount,
	(SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud') AND USER_NAME(principal_id)=N'dbo') AS DboOwnedAppSchemaCount
FROM sys.databases d WHERE d.database_id=DB_ID();
