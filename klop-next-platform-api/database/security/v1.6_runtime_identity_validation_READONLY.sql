:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_LOGIN "REPLACE_WITH_APPROVED_WINDOWS_SERVICE_LOGIN"
:setvar KLOP_RUNTIME_USER "KLOP_PLATFORM_API_DEV"

-- Read-only security verification. Run as DBA for catalog/DMV evidence and separately
-- under the approved runtime identity for its login-token/effective-permission evidence.
SET NOCOUNT ON;
DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ExpectedLogin sysname=N'$(KLOP_RUNTIME_LOGIN)';
DECLARE @ExpectedUser sysname=N'$(KLOP_RUNTIME_USER)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52730,'Runtime validation is restricted to Development DEV-PC\SQLEXPRESS.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52731,'Runtime validation is restricted to KlopPlatformDB.',1;

SELECT N'CURRENT_SESSION_CONTEXT' AS Section,
	@@SERVERNAME AS ServerName,DB_NAME() AS DatabaseName,
	ORIGINAL_LOGIN() AS OriginalLogin,SUSER_SNAME() AS EffectiveLogin,
	USER_NAME() AS DatabaseUser,APP_NAME() AS ApplicationName,
	IS_SRVROLEMEMBER(N'sysadmin') AS CurrentSessionIsSysadmin,
	IS_ROLEMEMBER(N'db_owner') AS CurrentSessionIsDbOwner,
	IS_ROLEMEMBER(N'klop_app_runtime') AS CurrentSessionIsRuntimeRoleMember,
	CASE WHEN ORIGINAL_LOGIN()=@ExpectedLogin AND SUSER_SNAME()=@ExpectedLogin
			  AND USER_NAME()=@ExpectedUser AND APP_NAME()=N'KLOP.Platform.API'
		 THEN N'API SESSION MATCH' ELSE N'NOT API RUNTIME PROOF (SSMS/SQLCMD/other context)' END AS RuntimeContextAssessment;

SELECT N'APPROVED_WINDOWS_LOGIN' AS Section,@ExpectedLogin AS ExpectedLogin,
	sp.type_desc AS LoginType,sp.is_disabled AS IsDisabled,
	CASE WHEN sp.principal_id IS NULL THEN N'NOT PROVISIONED'
		 WHEN sp.type=N'U' AND sp.is_disabled=0 THEN N'PRESENT WINDOWS LOGIN'
		 ELSE N'REJECT: expected enabled Windows login' END AS LoginStatus,
	IS_SRVROLEMEMBER(N'sysadmin',@ExpectedLogin) AS IsSysadmin,
	IS_SRVROLEMEMBER(N'serveradmin',@ExpectedLogin) AS IsServeradmin,
	IS_SRVROLEMEMBER(N'securityadmin',@ExpectedLogin) AS IsSecurityadmin,
	IS_SRVROLEMEMBER(N'setupadmin',@ExpectedLogin) AS IsSetupadmin,
	IS_SRVROLEMEMBER(N'processadmin',@ExpectedLogin) AS IsProcessadmin,
	IS_SRVROLEMEMBER(N'diskadmin',@ExpectedLogin) AS IsDiskadmin,
	IS_SRVROLEMEMBER(N'dbcreator',@ExpectedLogin) AS IsDbcreator,
	IS_SRVROLEMEMBER(N'bulkadmin',@ExpectedLogin) AS IsBulkadmin
FROM (VALUES(1)) seed(n)
LEFT JOIN sys.server_principals sp ON sp.name=@ExpectedLogin;

SELECT N'DATABASE_USER_MAPPING' AS Section,@ExpectedUser AS ExpectedDatabaseUser,
	dp.type_desc AS DatabasePrincipalType,
	CASE WHEN dp.principal_id IS NULL THEN N'NOT MAPPED'
		 WHEN dp.sid=SUSER_SID(@ExpectedLogin) THEN N'SID MATCHES APPROVED LOGIN'
		 ELSE N'SID MISMATCH' END AS MappingStatus,
	CASE WHEN EXISTS
	(
		SELECT 1 FROM sys.database_role_members rm
		WHERE rm.member_principal_id=dp.principal_id
		  AND rm.role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
	) THEN N'MEMBER' ELSE N'NOT A MEMBER' END AS RuntimeRoleStatus
FROM (VALUES(1)) seed(n)
LEFT JOIN sys.database_principals dp ON dp.name=@ExpectedUser;

SELECT N'RUNTIME_ROLE_MEMBERS' AS Section,r.name AS RoleName,m.name AS MemberName,m.type_desc AS MemberType
FROM sys.database_principals r
LEFT JOIN sys.database_role_members rm ON rm.role_principal_id=r.principal_id
LEFT JOIN sys.database_principals m ON m.principal_id=rm.member_principal_id
WHERE r.name=N'klop_app_runtime';

SELECT N'EXPECTED_USER_DATABASE_ROLE_MEMBERSHIPS' AS Section,p.name AS DatabaseUser,r.name AS RoleName
FROM sys.database_principals p
LEFT JOIN sys.database_role_members rm ON rm.member_principal_id=p.principal_id
LEFT JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
WHERE p.name=@ExpectedUser;

DECLARE @RequiredProcedures TABLE
(
	SchemaName sysname NOT NULL,
	ProcedureName sysname NOT NULL,
	PRIMARY KEY(SchemaName,ProcedureName)
);
INSERT @RequiredProcedures(SchemaName,ProcedureName) VALUES
	(N'iam',N'usp_RegisterLocalUser'),(N'iam',N'usp_ConfirmEmail'),
	(N'iam',N'usp_IssueEmailVerificationChallenge'),(N'iam',N'usp_GetLocalLoginCandidate'),
	(N'iam',N'usp_RecordLocalLoginFailure'),(N'iam',N'usp_CreateAuthSession'),
	(N'iam',N'usp_ValidateSessionAccess'),(N'iam',N'usp_RotateRefreshToken'),
	(N'iam',N'usp_RevokeAuthSession'),(N'iam',N'usp_GetUserProfile'),
	(N'iam',N'usp_AssignTenantRole'),(N'iam',N'usp_RevokeTenantRole'),
	(N'ten',N'usp_ListMyTenants'),(N'ten',N'usp_CreateTenantWithOwner'),
	(N'ten',N'usp_InviteExistingUser'),(N'ten',N'usp_AcceptMembership'),
	(N'ten',N'usp_RemoveTenantMember'),(N'mst',N'usp_OrganizationType_GetAll'),
	(N'mst',N'usp_TenantType_GetAll'),(N'cfg',N'usp_Configuration_GetByKey'),
	(N'reg',N'usp_GetMyApplication'),(N'reg',N'usp_GetApplicationForOwner'),
	(N'reg',N'usp_SavePersonalDraft'),(N'reg',N'usp_SaveOrganizationDraft'),
	(N'reg',N'usp_GetOrganizationRequirements'),(N'reg',N'usp_SubmitOnboarding'),
	(N'leg',N'usp_GetCurrentTerms'),(N'leg',N'usp_GetPublicTermsFile');

SELECT N'REQUIRED_PROCEDURE_AND_GRANT_MATRIX' AS Section,r.SchemaName,r.ProcedureName,
	CASE WHEN p.object_id IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS CatalogStatus,
	CASE WHEN p.object_id IS NOT NULL AND EXISTS
	(
		SELECT 1 FROM sys.database_permissions dp
		WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
		  AND dp.class=1 AND dp.major_id=p.object_id
		  AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')
	) THEN N'EXPLICIT ROLE EXECUTE' ELSE N'NO EXPLICIT ROLE EXECUTE' END AS RoleGrantStatus,
	CASE WHEN p.object_id IS NOT NULL AND HAS_PERMS_BY_NAME(
			QUOTENAME(r.SchemaName)+N'.'+QUOTENAME(r.ProcedureName),N'OBJECT',N'EXECUTE')=1
		 THEN N'CURRENT SESSION CAN EXECUTE (ONLY RUNTIME PROOF WHEN SESSION CONTEXT ABOVE MATCHES)'
		 ELSE N'CURRENT SESSION CANNOT EXECUTE OR PROCEDURE MISSING' END AS CurrentSessionEffectiveStatus
FROM @RequiredProcedures r
LEFT JOIN sys.schemas s ON s.name=r.SchemaName
LEFT JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ProcedureName
ORDER BY r.SchemaName,r.ProcedureName;

SELECT N'RUNTIME_ROLE_PERMISSION_CATALOG' AS Section,dp.state_desc,dp.permission_name,dp.class_desc,
	CASE WHEN dp.class=1 THEN OBJECT_SCHEMA_NAME(dp.major_id) ELSE SCHEMA_NAME(dp.major_id) END AS SecurableSchema,
	CASE WHEN dp.class=1 THEN OBJECT_NAME(dp.major_id) ELSE NULL END AS SecurableName
FROM sys.database_permissions dp
WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
ORDER BY dp.state_desc,dp.permission_name,SecurableSchema,SecurableName;

SELECT N'RUNTIME_PRINCIPAL_DIRECT_GRANTS' AS Section,dp.state_desc,dp.permission_name,dp.class_desc,
	CASE WHEN dp.class=1 THEN OBJECT_SCHEMA_NAME(dp.major_id) ELSE SCHEMA_NAME(dp.major_id) END AS SecurableSchema,
	CASE WHEN dp.class=1 THEN OBJECT_NAME(dp.major_id) ELSE NULL END AS SecurableName
FROM sys.database_permissions dp
JOIN sys.database_principals p ON p.principal_id=dp.grantee_principal_id
WHERE p.name=@ExpectedUser AND dp.state IN('G','W')
ORDER BY dp.permission_name,SecurableSchema,SecurableName;

SELECT N'CURRENT_SESSION_EFFECTIVE_APPLICATION_TABLE_ACCESS' AS Section,
	s.name AS SchemaName,t.name AS TableName,p.PermissionName,
	HAS_PERMS_BY_NAME(QUOTENAME(s.name)+N'.'+QUOTENAME(t.name),N'OBJECT',p.PermissionName) AS CurrentSessionHasPermission,
	N'Interpret only when CURRENT_SESSION_CONTEXT reports API SESSION MATCH.' AS Interpretation
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id=t.schema_id
CROSS JOIN (VALUES(N'SELECT'),(N'INSERT'),(N'UPDATE'),(N'DELETE')) p(PermissionName)
WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg')
ORDER BY s.name,t.name,p.PermissionName;

SELECT N'LIVE_API_CONNECTIONS' AS Section,s.session_id,s.host_name,s.program_name,
	s.login_name,s.original_login_name,DB_NAME(s.database_id) AS DatabaseName,c.auth_scheme,
	CASE WHEN s.login_name=@ExpectedLogin AND s.original_login_name=@ExpectedLogin
			  AND DB_NAME(s.database_id)=@ExpectedDatabase
		 THEN N'LOGIN/DATABASE MATCH' ELSE N'REVIEW IDENTITY/TARGET' END AS SessionAssessment
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_connections c ON c.session_id=s.session_id
WHERE s.is_user_process=1 AND s.program_name=N'KLOP.Platform.API'
ORDER BY s.session_id;
GO
