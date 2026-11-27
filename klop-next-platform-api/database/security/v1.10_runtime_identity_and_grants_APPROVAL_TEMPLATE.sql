:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_LOGIN "REPLACE_WITH_PRECREATED_NON_SYSADMIN_WINDOWS_OR_ENTRA_LOGIN"
:setvar KLOP_RUNTIME_USER "klop_platform_api_runtime"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Maps one pre-created Windows/Entra individual login and grants only the reviewed 38 procedures.
-- No CREATE LOGIN, direct table access, broad/schema EXECUTE, role assignments, or application data changes.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Environment NVARCHAR(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase SYSNAME=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @RuntimeLogin SYSNAME=N'$(KLOP_RUNTIME_LOGIN)';
DECLARE @RuntimeUser SYSNAME=N'$(KLOP_RUNTIME_USER)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @RuntimeLoginId INT=SUSER_ID(@RuntimeLogin);
DECLARE @RuntimeUserId INT=DATABASE_PRINCIPAL_ID(@RuntimeUser);
DECLARE @RuntimeRoleId INT=DATABASE_PRINCIPAL_ID(N'klop_app_runtime');

IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52940, 'Refused: only the reviewed Development SQL Server is permitted.', 1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
    THROW 52941, 'Refused: this template is restricted to KlopPlatformDB.', 1;
IF @RuntimeUser IN(N'dbo',N'guest',N'sys',N'INFORMATION_SCHEMA',N'public')
    THROW 52942, 'Refused: runtime database principal name is reserved.', 1;
IF @RuntimeRoleId IS NOT NULL AND NOT EXISTS
(
    SELECT 1 FROM sys.database_principals
    WHERE principal_id=@RuntimeRoleId AND type=N'R'
)
    THROW 52943, 'Refused: klop_app_runtime exists but is not a database role.', 1;

DECLARE @RequiredProcedures TABLE
(
    SchemaName SYSNAME NOT NULL,
    ObjectName SYSNAME NOT NULL,
    PRIMARY KEY(SchemaName,ObjectName)
);
INSERT @RequiredProcedures(SchemaName,ObjectName) VALUES
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
(N'ten',N'usp_ListMyTenants'),
(N'leg',N'usp_GetCurrentTerms'),
(N'leg',N'usp_GetPublicTermsFile'),
(N'reg',N'usp_GetMyApplication'),
(N'reg',N'usp_GetApplicationForOwner'),
(N'reg',N'usp_SavePersonalDraft'),
(N'reg',N'usp_SaveOrganizationDraft'),
(N'reg',N'usp_GetOrganizationRequirements'),
(N'reg',N'usp_SubmitOnboarding'),
(N'reg',N'usp_GetPlatformRegistrationSummary'),
(N'reg',N'usp_ListPlatformRegistrations'),
(N'reg',N'usp_GetPlatformRegistration'),
(N'reg',N'usp_GetPlatformRegistrationTimeline'),
(N'iam',N'usp_ValidatePlatformPermission'),
(N'iam',N'usp_GetPlatformPermissions'),
(N'iam',N'usp_GetTenantPermissions'),
(N'iam',N'usp_GetUnifiedRolePermissionMatrix'),
(N'iam',N'usp_SaveRolePermissionBatch'),
(N'iam',N'usp_GetRolePermissionChangeHistory');

IF (SELECT COUNT(*) FROM @RequiredProcedures)<>38
    THROW 52944, 'The reviewed exact procedure allowlist is malformed.', 1;

IF EXISTS
(
    SELECT 1
    FROM @RequiredProcedures required
    LEFT JOIN sys.schemas schemaInfo ON schemaInfo.name=required.SchemaName
    LEFT JOIN sys.procedures procedureInfo
      ON procedureInfo.schema_id=schemaInfo.schema_id
     AND procedureInfo.name=required.ObjectName
    WHERE procedureInfo.object_id IS NULL
)
    THROW 52945, 'A required application procedure is missing; deploy and validate its approved migration first.', 1;

IF (SELECT COUNT(*) FROM sys.schemas
    WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>7
    THROW 52946, 'One or more reviewed application schemas are missing.', 1;
IF (SELECT COUNT(DISTINCT principal_id) FROM sys.schemas
    WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>1
    THROW 52947, 'Application schemas do not have a common owner; stop for DBA review.', 1;
IF EXISTS
(
    SELECT 1 FROM sys.schemas
    WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg')
      AND USER_NAME(principal_id)<>N'dbo'
)
    THROW 52948, 'Reviewed ownership chaining requires dbo ownership for application schemas.', 1;

IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id=@RuntimeRoleId
      AND permission.state IN('G','W')
      AND permission.permission_name IN
      (N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'CONTROL',N'ALTER',N'TAKE OWNERSHIP',
       N'IMPERSONATE',N'ALTER ANY USER',N'ALTER ANY ROLE',N'ALTER ANY SCHEMA',
       N'CREATE USER',N'CREATE ROLE',N'CREATE SCHEMA',N'CREATE TABLE',N'CREATE PROCEDURE')
)
    THROW 52949, 'Runtime role has direct data or administrative grants; reconcile manually without revoking access.', 1;
IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id=@RuntimeRoleId
      AND permission.permission_name=N'EXECUTE'
      AND permission.state IN('G','W')
      AND NOT EXISTS
      (
          SELECT 1 FROM @RequiredProcedures required
          JOIN sys.schemas schemaInfo ON schemaInfo.name=required.SchemaName
          JOIN sys.procedures procedureInfo
            ON procedureInfo.schema_id=schemaInfo.schema_id
           AND procedureInfo.name=required.ObjectName
          WHERE permission.class=1 AND permission.major_id=procedureInfo.object_id
      )
)
    THROW 52950, 'Runtime role has EXECUTE grants outside the reviewed object allowlist; reconcile manually.', 1;

IF @RuntimeUserId IS NOT NULL AND EXISTS
(
    SELECT 1 FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id=@RuntimeUserId
      AND permission.state IN('G','W')
      AND permission.permission_name IN(N'EXECUTE',N'SELECT',N'INSERT',N'UPDATE',N'DELETE',
         N'CONTROL',N'ALTER',N'TAKE OWNERSHIP',N'IMPERSONATE')
)
    THROW 52951, 'Runtime user has direct privileges; reconcile manually without revoking access.', 1;

IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_role_members membership
    WHERE membership.role_principal_id=@RuntimeRoleId
      AND membership.member_principal_id<>ISNULL(@RuntimeUserId,-1)
)
    THROW 52952, 'klop_app_runtime already has a different member; review before mapping another identity.', 1;
IF @RuntimeRoleId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_role_members membership
    JOIN sys.database_principals parentRole
      ON parentRole.principal_id=membership.role_principal_id
    WHERE membership.member_principal_id=@RuntimeRoleId
      AND parentRole.name<>N'public'
)
    THROW 52960, 'klop_app_runtime is nested in another role; reconcile manually before mapping a runtime identity.', 1;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
    SELECT N'DRY RUN - NO CHANGES' AS Status,
           CASE WHEN @RuntimeLogin LIKE N'REPLACE_%' THEN N'LOGIN NOT CONFIGURED'
                WHEN @RuntimeLoginId IS NULL THEN N'LOGIN NOT FOUND'
                ELSE N'LOGIN EXISTS; approval and identity checks remain required' END AS LoginPrecheck,
           CASE WHEN @RuntimeRoleId IS NULL THEN N'ROLE WOULD BE CREATED'
                ELSE N'ROLE EXISTS; existing reviewed grants are preserved' END AS RolePrecheck,
           (SELECT COUNT(*) FROM @RequiredProcedures) AS ExactAllowlistProcedureCount,
           N'No migration, role membership, permission mapping, or application data is changed in dry-run mode.' AS Scope;
    RETURN;
END;

IF @ApprovalTicket LIKE N'UNSET%' OR @RuntimeLogin LIKE N'REPLACE_%'
   OR @RuntimeLoginId IS NULL
    THROW 52953, 'Refused: supply the approved ticket and pre-created Windows/Entra login.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM sys.server_principals
    WHERE sid=SUSER_SID(@RuntimeLogin) AND type IN(N'U',N'E')
)
    THROW 52954, 'Refused: runtime login must be one Windows/Entra individual, not a SQL login or group.', 1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin',@RuntimeLogin),1)<>0
    THROW 52955, 'Refused: runtime login must not be sysadmin or resolve through a sysadmin group.', 1;

IF @RuntimeUserId IS NOT NULL AND
(
    (SELECT sid FROM sys.database_principals WHERE principal_id=@RuntimeUserId)<>SUSER_SID(@RuntimeLogin)
    OR (SELECT type FROM sys.database_principals WHERE principal_id=@RuntimeUserId) NOT IN(N'S',N'U',N'E')
)
    THROW 52956, 'Refused: existing database user is not mapped to the specified login.', 1;
IF @RuntimeUserId IS NOT NULL AND EXISTS
(
    SELECT 1
    FROM sys.database_role_members membership
    JOIN sys.database_principals roleInfo
      ON roleInfo.principal_id=membership.role_principal_id
    WHERE membership.member_principal_id=@RuntimeUserId
      AND roleInfo.name<>N'klop_app_runtime'
)
    THROW 52957, 'Refused: runtime user belongs to another database role; reconcile manually.', 1;
IF EXISTS
(
    SELECT 1 FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'public')
      AND permission.state IN('G','W')
      AND permission.permission_name IN
      (N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'EXECUTE',N'CONTROL',N'ALTER',
       N'TAKE OWNERSHIP',N'IMPERSONATE',N'ALTER ANY USER',N'ALTER ANY ROLE',
       N'ALTER ANY SCHEMA',N'CREATE USER',N'CREATE ROLE',N'CREATE SCHEMA',
       N'CREATE TABLE',N'CREATE PROCEDURE')
      AND permission.class IN(0,1,3)
      AND NOT
      (
          permission.permission_name=N'SELECT'
          AND permission.class=1
          AND OBJECT_SCHEMA_NAME(permission.major_id)=N'sys'
      )
)
    THROW 52958, 'Refused: public has a broad/data/EXECUTE grant; review inherited access before adding the runtime user.', 1;

DECLARE @DynamicSql NVARCHAR(MAX);
DECLARE @SchemaName SYSNAME;
DECLARE @ObjectName SYSNAME;
DECLARE @ObjectId INT;
DECLARE procedureCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT required.SchemaName,required.ObjectName,procedureInfo.object_id
    FROM @RequiredProcedures required
    JOIN sys.schemas schemaInfo ON schemaInfo.name=required.SchemaName
    JOIN sys.procedures procedureInfo
      ON procedureInfo.schema_id=schemaInfo.schema_id
     AND procedureInfo.name=required.ObjectName
    ORDER BY required.SchemaName,required.ObjectName;

BEGIN TRY
    BEGIN TRANSACTION;

    IF @RuntimeRoleId IS NULL
        EXEC(N'CREATE ROLE [klop_app_runtime] AUTHORIZATION [dbo];');
    IF @RuntimeUserId IS NULL
    BEGIN
        SET @DynamicSql=N'CREATE USER '+QUOTENAME(@RuntimeUser)+N' FOR LOGIN '+QUOTENAME(@RuntimeLogin)+N';';
        EXEC sys.sp_executesql @DynamicSql;
    END;

    SET @RuntimeUserId=DATABASE_PRINCIPAL_ID(@RuntimeUser);
    IF NOT EXISTS
    (
        SELECT 1 FROM sys.database_role_members
        WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
          AND member_principal_id=@RuntimeUserId
    )
    BEGIN
        SET @DynamicSql=N'ALTER ROLE [klop_app_runtime] ADD MEMBER '+QUOTENAME(@RuntimeUser)+N';';
        EXEC sys.sp_executesql @DynamicSql;
    END;

    OPEN procedureCursor;
    FETCH NEXT FROM procedureCursor INTO @SchemaName,@ObjectName,@ObjectId;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1 FROM sys.database_permissions permission
            WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
              AND permission.class=1
              AND permission.major_id=@ObjectId
              AND permission.permission_name=N'EXECUTE'
              AND permission.state IN('G','W')
        )
        BEGIN
            SET @DynamicSql=N'GRANT EXECUTE ON OBJECT::'+QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@ObjectName)
                           +N' TO [klop_app_runtime];';
            EXEC sys.sp_executesql @DynamicSql;
        END;
        FETCH NEXT FROM procedureCursor INTO @SchemaName,@ObjectName,@ObjectId;
    END;
    CLOSE procedureCursor;
    DEALLOCATE procedureCursor;

    IF (SELECT COUNT(*) FROM sys.database_role_members
        WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime'))<>1
        THROW 52959, 'Post-check failed: klop_app_runtime must have exactly the approved service user.', 1;
    IF (SELECT COUNT(*)
        FROM sys.database_permissions permission
        WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
          AND permission.class=1
          AND permission.permission_name=N'EXECUTE'
          AND permission.state IN('G','W'))<>38
        THROW 52961, 'Post-check failed: runtime role must have exactly 38 explicit object EXECUTE grants.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local','procedureCursor')>=0 CLOSE procedureCursor;
    IF CURSOR_STATUS('local','procedureCursor')>-3 DEALLOCATE procedureCursor;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT N'REVIEW REQUIRED' AS Status,
       N'Connect as the actual runtime identity and run database/security/v1.10_runtime_identity_validation_READONLY.sql.' AS NextStep;
GO
