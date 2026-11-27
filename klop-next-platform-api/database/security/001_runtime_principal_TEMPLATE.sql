:on error exit
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB_TEST"
:setvar KLOP_RUNTIME_LOGIN "REPLACE_WITH_PRECREATED_NON_SYSADMIN_LOGIN"
:setvar KLOP_RUNTIME_USER "KLOP_PLATFORM_TEST_RUNTIME"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

SET NOCOUNT ON;

DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @RuntimeLogin sysname=N'$(KLOP_RUNTIME_LOGIN)';
DECLARE @RuntimeUser sysname=N'$(KLOP_RUNTIME_USER)';
DECLARE @ApprovalTicket nvarchar(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges nvarchar(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @RuntimeLoginId int=SUSER_ID(@RuntimeLogin);
DECLARE @RuntimeUserId int=DATABASE_PRINCIPAL_ID(@RuntimeUser);
DECLARE @RuntimeRoleId int=DATABASE_PRINCIPAL_ID(N'klop_app_runtime');

IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52410,'Refused: this reviewed template is restricted to DEV-PC\SQLEXPRESS.',1;
IF @ExpectedDatabase NOT IN(N'KlopPlatformDB',N'KlopPlatformDB_TEST')
    THROW 52411,'Refused: target must be the exact Development or isolated test database.',1;
IF DB_NAME()<>@ExpectedDatabase
    THROW 52412,'Refused: connect directly to the exact approved target database.',1;
IF @RuntimeUser IN(N'dbo',N'guest',N'sys',N'INFORMATION_SCHEMA',N'public')
    THROW 52413,'Refused: the runtime database principal name is reserved.',1;
IF @RuntimeRoleId IS NOT NULL AND NOT EXISTS
(
    SELECT 1 FROM sys.database_principals
    WHERE principal_id=@RuntimeRoleId AND type=N'R'
)
    THROW 52414,'Refused: klop_app_runtime exists but is not a database role.',1;

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
    LEFT JOIN sys.schemas s ON s.name=p.SchemaName
    LEFT JOIN sys.procedures o ON o.schema_id=s.schema_id AND o.name=p.ObjectName
    WHERE o.object_id IS NULL
)
    THROW 52415,'Refused: one or more of the 20 mapped Stored Procedures is missing.',1;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
    SELECT N'NO CHANGES' AS Status,DB_NAME() AS DatabaseName,
        CASE WHEN @RuntimeLogin LIKE N'REPLACE_%' THEN N'NOT CONFIGURED'
             WHEN @RuntimeLoginId IS NULL THEN N'LOGIN NOT FOUND'
             ELSE N'LOGIN EXISTS; approval and identity checks still required' END AS LoginPrecheck,
        CASE WHEN @RuntimeRoleId IS NULL THEN N'ROLE WILL BE CREATED'
             ELSE N'ROLE EXISTS; existing grants will not be revoked' END AS RolePrecheck;
    RETURN;
END;

IF @RuntimeLogin LIKE N'REPLACE_%' OR @RuntimeLoginId IS NULL
    THROW 52416,'Refused: provision and specify the approved Windows/Entra login first.',1;
IF NOT EXISTS
(
    SELECT 1 FROM sys.server_principals
    WHERE sid=SUSER_SID(@RuntimeLogin) AND type IN(N'U',N'E')
)
    THROW 52428,'Refused: use a dedicated Windows/Entra login, not a SQL login or Windows group.',1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin',@RuntimeLogin),1)<>0
    THROW 52417,'Refused: runtime login must not be a sysadmin or resolve through a sysadmin group.',1;
IF @RuntimeUserId IS NOT NULL AND
(
    (SELECT sid FROM sys.database_principals WHERE principal_id=@RuntimeUserId)<>SUSER_SID(@RuntimeLogin)
    OR (SELECT type FROM sys.database_principals WHERE principal_id=@RuntimeUserId) NOT IN(N'S',N'U',N'E')
)
    THROW 52418,'Refused: existing database user is not mapped to the specified login.',1;
IF @RuntimeUserId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
    WHERE rm.member_principal_id=@RuntimeUserId AND r.name<>N'klop_app_runtime'
)
    THROW 52419,'Refused: runtime user already belongs to another database role; reconcile manually without revoking privileges.',1;
IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
    WHERE rm.member_principal_id=@RuntimeRoleId AND r.name<>N'public'
)
    THROW 52420,'Refused: klop_app_runtime is nested in another role; reconcile manually.',1;
IF EXISTS
(
    SELECT 1 FROM sys.database_permissions dp
    WHERE dp.grantee_principal_id IN(@RuntimeUserId,@RuntimeRoleId)
      AND dp.state IN('G','W')
      AND dp.permission_name IN
      (
          N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'CONTROL',N'ALTER',N'TAKE OWNERSHIP',
          N'IMPERSONATE',N'ALTER ANY USER',N'ALTER ANY ROLE',N'ALTER ANY SCHEMA',
          N'CREATE USER',N'CREATE ROLE',N'CREATE SCHEMA',N'CREATE TABLE',N'CREATE PROCEDURE'
      )
)
    THROW 52421,'Refused: direct table/data or broad administrative grants already exist; do not silently revoke them.',1;
IF @RuntimeUserId IS NOT NULL AND EXISTS
(
    SELECT 1 FROM sys.database_permissions dp
    WHERE dp.grantee_principal_id=@RuntimeUserId
      AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')
)
    THROW 52426,'Refused: the runtime user has direct EXECUTE grants; reconcile them manually without revoking privileges.',1;
IF EXISTS
(
    SELECT 1 FROM sys.database_permissions dp
    WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'public')
      AND dp.state IN('G','W')
      AND dp.permission_name IN
      (
          N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'EXECUTE',N'CONTROL',N'ALTER',
          N'TAKE OWNERSHIP',N'IMPERSONATE',N'ALTER ANY USER',N'ALTER ANY ROLE',
          N'ALTER ANY SCHEMA',N'CREATE USER',N'CREATE ROLE',N'CREATE SCHEMA',
          N'CREATE TABLE',N'CREATE PROCEDURE'
      )
      AND dp.class IN(0,1,3)
)
    THROW 52427,'Refused: public has a broad/data/EXECUTE grant; review inherited access before adding the runtime user.',1;
IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_permissions dp
    WHERE dp.grantee_principal_id=@RuntimeRoleId
      AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')
      AND NOT EXISTS
      (
          SELECT 1 FROM @MappedProcedures p
          JOIN sys.schemas s ON s.name=p.SchemaName
          JOIN sys.procedures o ON o.schema_id=s.schema_id AND o.name=p.ObjectName
          WHERE dp.class=1 AND dp.major_id=o.object_id
      )
)
    THROW 52422,'Refused: runtime role has EXECUTE grants outside the reviewed 20-object allowlist.',1;
IF (SELECT COUNT(*) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))<>5
    THROW 52423,'Refused: one or more application schemas are missing.',1;
IF (SELECT COUNT(DISTINCT principal_id) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))<>1
    THROW 52424,'Refused: application schemas do not have a common owner; do not grant table DML to compensate.',1;
IF EXISTS(SELECT 1 FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud') AND USER_NAME(principal_id)<>N'dbo')
    THROW 52425,'Refused: reviewed ownership chaining expects dbo ownership for all five application schemas.',1;

DECLARE @DynamicSql nvarchar(max);
BEGIN TRY
    BEGIN TRANSACTION;

    IF @RuntimeRoleId IS NULL
        EXEC(N'CREATE ROLE [klop_app_runtime] AUTHORIZATION [dbo];');

    IF @RuntimeUserId IS NULL
    BEGIN
        SET @DynamicSql=N'CREATE USER '+QUOTENAME(@RuntimeUser)+N' FOR LOGIN '+QUOTENAME(@RuntimeLogin)+N';';
        EXEC sys.sp_executesql @DynamicSql;
    END;

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.database_role_members
        WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
          AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser)
    )
    BEGIN
        SET @DynamicSql=N'ALTER ROLE [klop_app_runtime] ADD MEMBER '+QUOTENAME(@RuntimeUser)+N';';
        EXEC sys.sp_executesql @DynamicSql;
    END;

    GRANT EXECUTE ON OBJECT::cfg.usp_Configuration_GetByKey TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::mst.usp_TenantType_GetAll TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::mst.usp_OrganizationType_GetAll TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_RegisterLocalUser TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_ConfirmEmail TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::ten.usp_CreateTenantWithOwner TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::ten.usp_InviteExistingUser TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::ten.usp_AcceptMembership TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::ten.usp_RemoveTenantMember TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_AssignTenantRole TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_RevokeTenantRole TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_GetLocalLoginCandidate TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_RecordLocalLoginFailure TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_IssueEmailVerificationChallenge TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_CreateAuthSession TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_ValidateSessionAccess TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_RotateRefreshToken TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_RevokeAuthSession TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::iam.usp_GetUserProfile TO klop_app_runtime;
    GRANT EXECUTE ON OBJECT::ten.usp_ListMyTenants TO klop_app_runtime;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT N'REVIEW REQUIRED' AS Status,
    N'Connect as the actual runtime identity and run database/security/002_runtime_identity_validation_READONLY.sql.' AS NextStep;
GO
