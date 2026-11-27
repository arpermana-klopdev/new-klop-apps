:on error exit

USE [KlopPlatformDB_TEST];
GO
SET NOCOUNT ON;
IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS' OR DB_NAME()<>N'KlopPlatformDB_TEST'
    THROW 52480,'Read-only validation must target DEV-PC\SQLEXPRESS / KlopPlatformDB_TEST.',1;

SELECT N'TARGET' AS Section,@@SERVERNAME AS ServerName,DB_NAME() AS DatabaseName,
    CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')) AS SqlServerVersion,
    compatibility_level,is_db_chaining_on,is_trustworthy_on
FROM sys.databases WHERE database_id=DB_ID();

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

SELECT N'MAPPED_PROCEDURE' AS Section,p.SchemaName,p.ObjectName,
    CASE WHEN o.object_id IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
FROM @MappedProcedures p
LEFT JOIN sys.schemas s ON s.name=p.SchemaName
LEFT JOIN sys.procedures o ON o.schema_id=s.schema_id AND o.name=p.ObjectName
ORDER BY p.SchemaName,p.ObjectName;

IF EXISTS
(
    SELECT 1 FROM @MappedProcedures p
    LEFT JOIN sys.schemas s ON s.name=p.SchemaName
    LEFT JOIN sys.procedures o ON o.schema_id=s.schema_id AND o.name=p.ObjectName
    WHERE o.object_id IS NULL
)
    THROW 52481,'One or more mapped Stored Procedures is missing from the test database.',1;

DECLARE @ExpectedConfiguration TABLE
(
    ConfigurationKey varchar(150) NOT NULL PRIMARY KEY,
    ExpectedValueType varchar(40) NOT NULL,
    ExpectedStorageType varchar(40) NOT NULL,
    IsRequired bit NOT NULL
);
INSERT @ExpectedConfiguration VALUES
('auth.jwt.issuer','STRING','PLAIN',1),
('auth.jwt.audience','STRING','PLAIN',1),
('web.allowed_origin','STRING','PLAIN',1),
('smtp.require_tls','BOOLEAN','PLAIN',1),
('smtp.host','STRING','PLAIN',1),
('smtp.port','INTEGER','PLAIN',1),
('smtp.from','STRING','PLAIN',1),
('auth.access_token_minutes','INTEGER','PLAIN',1),
('auth.refresh_token_days','INTEGER','PLAIN',1),
('security.max_login_attempts','INTEGER','PLAIN',1),
('security.login_lockout_minutes','INTEGER','PLAIN',1),
('security.password.min_length','INTEGER','PLAIN',1),
('auth.email_verification_hours','INTEGER','PLAIN',1),
('database.command_timeout_seconds','INTEGER','PLAIN',1),
('security.auth_requests_per_minute','INTEGER','PLAIN',1),
('smtp.username','STRING','PLAIN',0),
('smtp.password_ref','STRING','KEYVAULT_REFERENCE',0),
('auth.signing_key_ref','STRING','KEYVAULT_REFERENCE',0);

SELECT N'RUNTIME_CONFIGURATION' AS Section,e.ConfigurationKey,e.IsRequired,
    CASE
        WHEN c.ConfigurationId IS NULL AND e.IsRequired=0 THEN N'OPTIONAL_NOT_CONFIGURED'
        WHEN c.ConfigurationId IS NULL THEN N'MISSING'
        WHEN c.ValueType<>e.ExpectedValueType OR c.StorageType<>e.ExpectedStorageType THEN N'TYPE_MISMATCH'
        WHEN e.IsRequired=1 AND NULLIF(LTRIM(RTRIM(c.ConfigurationValue)),N'') IS NULL THEN N'EMPTY_REQUIRED'
        WHEN NULLIF(LTRIM(RTRIM(c.ConfigurationValue)),N'') IS NULL THEN N'OPTIONAL_EMPTY'
        ELSE N'PRESENT'
    END AS Status,
    c.ValueType AS ActualValueType,c.StorageType AS ActualStorageType
FROM @ExpectedConfiguration e
LEFT JOIN cfg.SystemConfigurations c
    ON c.ConfigurationKey=e.ConfigurationKey AND c.IsActive=1
ORDER BY e.ConfigurationKey;

IF EXISTS
(
    SELECT 1 FROM @ExpectedConfiguration e
    LEFT JOIN cfg.SystemConfigurations c
        ON c.ConfigurationKey=e.ConfigurationKey AND c.IsActive=1
    WHERE (c.ConfigurationId IS NULL AND e.IsRequired=1)
       OR (c.ConfigurationId IS NOT NULL AND
           (c.ValueType<>e.ExpectedValueType OR c.StorageType<>e.ExpectedStorageType))
       OR (c.ConfigurationId IS NOT NULL AND e.IsRequired=1
           AND NULLIF(LTRIM(RTRIM(c.ConfigurationValue)),N'') IS NULL)
)
    THROW 52482,'Required runtime configuration is missing/empty or has an incompatible type/storage mode.',1;

IF (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))<>5
   OR EXISTS(SELECT 1 FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud') AND USER_NAME(principal_id)<>N'dbo')
    THROW 52483,'Application schemas are missing or do not have the reviewed common dbo owner.',1;
IF EXISTS
(
    SELECT 1 FROM sys.databases
    WHERE database_id=DB_ID() AND (is_db_chaining_on=1 OR is_trustworthy_on=1)
)
    THROW 52484,'Cross-database chaining and TRUSTWORTHY must remain disabled.',1;

SELECT N'SCHEMA_OWNERSHIP' AS Section,s.name AS SchemaName,USER_NAME(s.principal_id) AS SchemaOwner
FROM sys.schemas s
WHERE s.name IN(N'cfg',N'iam',N'mst',N'ten',N'aud')
ORDER BY s.name;

SELECT N'RUNTIME_ROLE_METADATA' AS Section,
    CASE WHEN DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS RoleStatus,
    (SELECT COUNT(*) FROM sys.database_role_members
        WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')) AS MemberCount,
    (SELECT COUNT(*) FROM sys.database_permissions
        WHERE grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
          AND permission_name=N'EXECUTE' AND state IN('G','W')) AS ExplicitExecuteGrantCount;
GO

:r database\validation\v1.5_001_auth_session_postdeploy_READONLY.sql
