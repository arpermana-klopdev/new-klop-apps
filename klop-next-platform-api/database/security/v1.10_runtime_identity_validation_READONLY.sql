-- Run only through a connection opened by the actual Development API runtime identity.
-- Read-only verification of the least-privilege 38-procedure allowlist.
SET NOCOUNT ON;

IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS' OR DB_NAME()<>N'KlopPlatformDB'
    THROW 52970, 'Runtime validation is restricted to the reviewed Development database.', 1;
IF USER_NAME()=N'dbo'
    THROW 52971, 'Blocked: the API runtime connection maps to dbo.', 1;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>0
    THROW 52972, 'Blocked: the API runtime identity is sysadmin.', 1;
IF ISNULL(IS_ROLEMEMBER(N'db_owner'),0)<>0 OR ISNULL(IS_ROLEMEMBER(N'db_ddladmin'),0)<>0
    THROW 52973, 'Blocked: the API runtime identity has database-owner or DDL-admin membership.', 1;
IF ISNULL(IS_ROLEMEMBER(N'klop_app_runtime'),0)<>1
    THROW 52974, 'Blocked: the API runtime identity is not in klop_app_runtime.', 1;

DECLARE @RuntimeUserId INT=DATABASE_PRINCIPAL_ID(USER_NAME());
DECLARE @RuntimeRoleId INT=DATABASE_PRINCIPAL_ID(N'klop_app_runtime');
IF EXISTS
(
    SELECT 1
    FROM sys.database_role_members membership
    JOIN sys.database_principals roleInfo
      ON roleInfo.principal_id=membership.role_principal_id
    WHERE membership.member_principal_id=@RuntimeUserId
      AND roleInfo.name NOT IN(N'public',N'klop_app_runtime')
)
    THROW 52975, 'Blocked: runtime user belongs to an additional database role.', 1;
IF EXISTS
(
    SELECT 1
    FROM sys.database_role_members membership
    JOIN sys.database_principals parentRole
      ON parentRole.principal_id=membership.role_principal_id
    WHERE membership.member_principal_id=@RuntimeRoleId
      AND parentRole.name<>N'public'
)
    THROW 52976, 'Blocked: klop_app_runtime is nested in an elevated or unrelated database role.', 1;

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
    THROW 52977, 'The reviewed exact procedure allowlist is malformed.', 1;

IF (SELECT COUNT(*) FROM sys.schemas
    WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>7
    THROW 52978, 'One or more reviewed application schemas are missing.', 1;
IF (SELECT COUNT(DISTINCT principal_id) FROM sys.schemas
    WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>1
   OR EXISTS
   (
       SELECT 1 FROM sys.schemas
       WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg')
         AND USER_NAME(principal_id)<>N'dbo'
   )
    THROW 52979, 'Reviewed application schemas do not have common dbo ownership.', 1;

SELECT required.SchemaName,required.ObjectName,
       CASE WHEN schemaInfo.schema_id IS NULL OR procedureInfo.object_id IS NULL THEN 0
            ELSE ISNULL(HAS_PERMS_BY_NAME(
                QUOTENAME(required.SchemaName)+N'.'+QUOTENAME(required.ObjectName),
                N'OBJECT',N'EXECUTE'),0) END AS HasEffectiveExecute
FROM @RequiredProcedures required
LEFT JOIN sys.schemas schemaInfo ON schemaInfo.name=required.SchemaName
LEFT JOIN sys.procedures procedureInfo
  ON procedureInfo.schema_id=schemaInfo.schema_id
 AND procedureInfo.name=required.ObjectName
ORDER BY required.SchemaName,required.ObjectName;

IF EXISTS
(
    SELECT 1
    FROM @RequiredProcedures required
    LEFT JOIN sys.schemas schemaInfo ON schemaInfo.name=required.SchemaName
    LEFT JOIN sys.procedures procedureInfo
      ON procedureInfo.schema_id=schemaInfo.schema_id
     AND procedureInfo.name=required.ObjectName
    WHERE procedureInfo.object_id IS NULL
       OR ISNULL(HAS_PERMS_BY_NAME(
            QUOTENAME(required.SchemaName)+N'.'+QUOTENAME(required.ObjectName),
            N'OBJECT',N'EXECUTE'),0)<>1
)
    THROW 52980, 'Blocked: a required procedure is missing or lacks effective EXECUTE permission.', 1;

IF EXISTS
(
    SELECT 1 FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id IN(@RuntimeUserId,@RuntimeRoleId)
      AND permission.state IN('G','W')
      AND permission.permission_name IN
      (N'SELECT',N'INSERT',N'UPDATE',N'DELETE',N'CONTROL',N'ALTER',N'TAKE OWNERSHIP',
       N'IMPERSONATE',N'ALTER ANY USER',N'ALTER ANY ROLE',N'ALTER ANY SCHEMA',
       N'CREATE USER',N'CREATE ROLE',N'CREATE SCHEMA',N'CREATE TABLE',N'CREATE PROCEDURE')
)
    THROW 52981, 'Blocked: runtime user or role has direct data or administrative permissions.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id=@RuntimeUserId
      AND permission.permission_name=N'EXECUTE'
      AND permission.state IN('G','W')
)
    THROW 52982, 'Blocked: runtime user has direct EXECUTE grants instead of role-scoped grants.', 1;

IF EXISTS
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
    THROW 52983, 'Blocked: runtime role has EXECUTE grants outside the exact object allowlist.', 1;

IF (SELECT COUNT(*)
    FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id=@RuntimeRoleId
      AND permission.class=1
      AND permission.permission_name=N'EXECUTE'
      AND permission.state IN('G','W'))<>38
    THROW 52984, 'Blocked: runtime role does not have exactly 38 explicit object EXECUTE grants.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.database_permissions permission
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
    THROW 52985, 'Blocked: public has a broad or data-access permission.', 1;

SELECT N'PASS' AS RuntimeValidation,
       N'Exactly 38 object-level EXECUTE grants; no admin-role membership or direct app-table access.' AS Result;
GO
