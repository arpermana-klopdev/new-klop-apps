:on error exit
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB_TEST"
:setvar KLOP_EXPECTED_RUNTIME_USER "KLOP_PLATFORM_TEST_RUNTIME"

SET NOCOUNT ON;

DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ExpectedRuntimeUser sysname=N'$(KLOP_EXPECTED_RUNTIME_USER)';
IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52430,'Expected Development SQL Server instance was not selected.',1;
IF DB_NAME()<>@ExpectedDatabase
    THROW 52431,'Connect as the actual runtime identity directly to the expected database.',1;

SELECT N'ACTUAL_CONNECTION_IDENTITY' AS Section,
    @@SERVERNAME AS ServerName,DB_NAME() AS DatabaseName,
    ORIGINAL_LOGIN() AS OriginalLogin,SUSER_SNAME() AS EffectiveLogin,USER_NAME() AS DatabaseUser,
    IS_SRVROLEMEMBER(N'sysadmin') AS IsSysadmin,
    IS_ROLEMEMBER(N'db_owner') AS IsDbOwner,
    IS_ROLEMEMBER(N'db_ddladmin') AS IsDbDdlAdmin,
    IS_ROLEMEMBER(N'db_datareader') AS IsDbDataReader,
    IS_ROLEMEMBER(N'db_datawriter') AS IsDbDataWriter,
    IS_ROLEMEMBER(N'klop_app_runtime') AS IsRuntimeRoleMember,
    HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CONNECT') AS CanConnect;

IF USER_NAME()<>@ExpectedRuntimeUser
    THROW 52432,'The active connection is not the expected dedicated runtime database user.',1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),1)<>0
    OR ISNULL(IS_ROLEMEMBER(N'db_owner'),1)<>0
    OR ISNULL(IS_ROLEMEMBER(N'db_ddladmin'),1)<>0
    OR ISNULL(IS_ROLEMEMBER(N'db_datareader'),1)<>0
    OR ISNULL(IS_ROLEMEMBER(N'db_datawriter'),1)<>0
    OR ISNULL(IS_ROLEMEMBER(N'klop_app_runtime'),0)<>1
    OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CONNECT'),0)<>1
    THROW 52433,'Runtime identity does not satisfy the least-privilege role profile.',1;

DECLARE @MappedProcedures TABLE(SchemaName sysname NOT NULL,ObjectName sysname NOT NULL PRIMARY KEY(SchemaName,ObjectName));
INSERT @MappedProcedures VALUES
(N'cfg',N'usp_Configuration_GetByKey'),
(N'mst',N'usp_TenantType_GetAll'),
(N'mst',N'usp_OrganizationType_GetAll'),
(N'iam',N'usp_RegisterLocalUser'),
(N'iam',N'usp_ConfirmEmail'),
(N'ten',N'usp_CreateTenantWithOwner'),
(N'ten',N'usp_InviteExistingUser'),
(N'ten',N'usp_AcceptMembership'),
(N'ten',N'usp_RemoveTenantMember'),
(N'iam',N'usp_AssignTenantRole'),
(N'iam',N'usp_RevokeTenantRole'),
(N'iam',N'usp_GetLocalLoginCandidate'),
(N'iam',N'usp_RecordLocalLoginFailure'),
(N'iam',N'usp_IssueEmailVerificationChallenge'),
(N'iam',N'usp_CreateAuthSession'),
(N'iam',N'usp_ValidateSessionAccess'),
(N'iam',N'usp_RotateRefreshToken'),
(N'iam',N'usp_RevokeAuthSession'),
(N'iam',N'usp_GetUserProfile'),
(N'ten',N'usp_ListMyTenants');

IF EXISTS
(
    SELECT 1 FROM @MappedProcedures p
    WHERE OBJECT_ID(QUOTENAME(p.SchemaName)+N'.'+QUOTENAME(p.ObjectName),N'P') IS NULL
       OR ISNULL(HAS_PERMS_BY_NAME(QUOTENAME(p.SchemaName)+N'.'+QUOTENAME(p.ObjectName),N'OBJECT',N'EXECUTE'),0)<>1
)
    THROW 52434,'One or more mapped Stored Procedures is missing or not executable by the actual runtime identity.',1;
IF EXISTS
(
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id=t.schema_id
    CROSS JOIN (VALUES(N'SELECT'),(N'INSERT'),(N'UPDATE'),(N'DELETE')) p(PermissionName)
    WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
      AND ISNULL(HAS_PERMS_BY_NAME(QUOTENAME(s.name)+N'.'+QUOTENAME(t.name),N'OBJECT',p.PermissionName),0)=1
)
    THROW 52435,'Actual runtime identity has effective direct permission on one or more application tables.',1;
IF EXISTS
(
    SELECT 1 FROM sys.databases
    WHERE database_id=DB_ID() AND (is_db_chaining_on=1 OR is_trustworthy_on=1)
)
    THROW 52436,'Cross-database chaining and TRUSTWORTHY must remain disabled.',1;
IF (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))<>5
   OR EXISTS(SELECT 1 FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud') AND USER_NAME(principal_id)<>N'dbo')
    THROW 52437,'Application schemas are missing or do not use the reviewed common dbo owner.',1;

SELECT N'OBJECT_EXECUTE' AS Section,p.SchemaName,p.ObjectName,
    CASE WHEN OBJECT_ID(QUOTENAME(p.SchemaName)+N'.'+QUOTENAME(p.ObjectName),N'P') IS NULL
         THEN N'MISSING'
         WHEN HAS_PERMS_BY_NAME(QUOTENAME(p.SchemaName)+N'.'+QUOTENAME(p.ObjectName),N'OBJECT',N'EXECUTE')=1
         THEN N'PASS' ELSE N'FAIL' END AS Status
FROM @MappedProcedures p ORDER BY p.SchemaName,p.ObjectName;

SELECT N'DIRECT_TABLE_PERMISSION' AS Section,t.SchemaName,t.TableName,p.PermissionName,
    HAS_PERMS_BY_NAME(QUOTENAME(t.SchemaName)+N'.'+QUOTENAME(t.TableName),N'OBJECT',p.PermissionName) AS HasPermission
FROM
(
    SELECT s.name AS SchemaName,t.name AS TableName
    FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
    WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
) t
CROSS JOIN (VALUES(N'SELECT'),(N'INSERT'),(N'UPDATE'),(N'DELETE')) p(PermissionName)
ORDER BY t.SchemaName,t.TableName,p.PermissionName;

SELECT N'OWNERSHIP_CHAIN' AS Section,
    CONVERT(bit,d.is_db_chaining_on) AS CrossDatabaseChainingEnabled,
    CONVERT(bit,d.is_trustworthy_on) AS TrustworthyEnabled,
    COUNT(*) AS ApplicationSchemaCount,
    SUM(CASE WHEN USER_NAME(s.principal_id)=N'dbo' THEN 1 ELSE 0 END) AS DboOwnedSchemaCount
FROM sys.databases d
CROSS JOIN sys.schemas s
WHERE d.database_id=DB_ID() AND s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
GROUP BY d.is_db_chaining_on,d.is_trustworthy_on;
GO
