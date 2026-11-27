:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Adds tenant-type-aware role grants and the unified, approval-gated permission matrix routines.
-- Do not run until the API's v1.10 source is deployed and the DBA approves this exact file.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Environment NVARCHAR(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase SYSNAME=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52980, 'Refused: only the reviewed Development SQL Server is permitted.', 1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
    THROW 52981, 'Refused: this template is restricted to KlopPlatformDB.', 1;

IF OBJECT_ID(N'iam.usp_ValidateSessionAccess',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_AssignTenantRole',N'P') IS NULL
   OR OBJECT_ID(N'iam.TenantRoleAssignments',N'U') IS NULL
   OR OBJECT_ID(N'ten.TenantMemberships',N'U') IS NULL
   OR OBJECT_ID(N'ten.Tenants',N'U') IS NULL
   OR OBJECT_ID(N'mst.TenantTypes',N'U') IS NULL
   OR OBJECT_ID(N'mst.TenantStatuses',N'U') IS NULL
   OR OBJECT_ID(N'mst.MembershipStatuses',N'U') IS NULL
   OR OBJECT_ID(N'mst.RoleScopes',N'U') IS NULL
   OR OBJECT_ID(N'mst.Roles',N'U') IS NULL
   OR OBJECT_ID(N'mst.Permissions',N'U') IS NULL
   OR OBJECT_ID(N'mst.RolePermissions',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditActionTypes',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditResultTypes',N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_GetPlatformPermissions',N'P') IS NULL
    THROW 52982, 'An expected existing tenant authorization object is missing.', 1;

IF NOT EXISTS(SELECT 1 FROM mst.TenantTypes WHERE Code='PERSONAL' AND IsActive=1 AND AllowMultipleMembers=0)
   OR NOT EXISTS(SELECT 1 FROM mst.TenantTypes WHERE Code='ORGANIZATION' AND IsActive=1 AND AllowMultipleMembers=1)
    THROW 52983, 'The approved PERSONAL/ORGANIZATION multi-member policy differs from Development.', 1;

IF EXISTS
(
    SELECT membership.TenantId
    FROM ten.TenantMemberships membership
    JOIN mst.MembershipStatuses status
      ON status.MembershipStatusId=membership.MembershipStatusId
     AND status.Code='ACTIVE'
     AND status.IsActive=1
    JOIN iam.TenantRoleAssignments assignment ON assignment.MembershipId=membership.MembershipId
    JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.Code='OWNER'
    GROUP BY membership.TenantId
    HAVING COUNT(*)>1
)
    THROW 52984, 'Existing tenants have multiple active OWNER assignments; resolve manually before deployment.', 1;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 52985, 'Approval gate closed: set the approved Development change ticket and KLOP_APPLY_CHANGES=APPROVED.', 1;

BEGIN TRANSACTION;

IF (SELECT COUNT(*) FROM mst.TenantTypes
    WHERE IsActive=1 AND Code IN('PERSONAL','ORGANIZATION'))<>2
   OR EXISTS
   (
       SELECT 1 FROM mst.TenantTypes
       WHERE IsActive=1 AND Code NOT IN('PERSONAL','ORGANIZATION')
   )
    THROW 52986, 'The matrix migration requires exactly the approved active PERSONAL and ORGANIZATION tenant types.', 1;

DECLARE @PersonalTenantTypeId BIGINT=
    (SELECT TenantTypeId FROM mst.TenantTypes WHERE Code='PERSONAL' AND IsActive=1);
DECLARE @OrganizationTenantTypeId BIGINT=
    (SELECT TenantTypeId FROM mst.TenantTypes WHERE Code='ORGANIZATION' AND IsActive=1);
DECLARE @PlatformScopeId BIGINT=
    (SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='PLATFORM' AND IsActive=1);
DECLARE @TenantScopeId BIGINT=
    (SELECT RoleScopeId FROM mst.RoleScopes WHERE Code='TENANT' AND IsActive=1);
IF @PlatformScopeId IS NULL OR @TenantScopeId IS NULL
    THROW 52986, 'The approved PLATFORM and TENANT role scopes are required.', 1;
IF EXISTS
(
    SELECT 1 FROM mst.RoleScopes
    WHERE IsActive=1 AND Code NOT IN('PLATFORM','TENANT')
)
    THROW 52986, 'The active role-scope catalog differs from the frozen baseline.', 1;

DECLARE @ExpectedRoles TABLE
(
    RoleId BIGINT NOT NULL PRIMARY KEY,
    Code VARCHAR(50) NOT NULL,
    ScopeId BIGINT NOT NULL,
    IsAssignable BIT NOT NULL
);
INSERT @ExpectedRoles(RoleId,Code,ScopeId,IsAssignable)
VALUES
    (1,'SUPER_ADMIN',@PlatformScopeId,1),
    (2,'PLATFORM_SUPPORT',@PlatformScopeId,1),
    (3,'OWNER',@TenantScopeId,1),
    (4,'ADMIN',@TenantScopeId,1),
    (5,'MEMBER',@TenantScopeId,1),
    (6,'VIEWER',@TenantScopeId,0);
IF EXISTS
(
    SELECT 1
    FROM @ExpectedRoles expected
    LEFT JOIN mst.Roles actual ON actual.RoleId=expected.RoleId
    WHERE actual.RoleId IS NULL OR actual.Code<>expected.Code
       OR actual.RoleScopeId<>expected.ScopeId
       OR actual.IsAssignable<>expected.IsAssignable
       OR actual.IsActive<>1 OR actual.IsSystem<>1
)
OR EXISTS
(
    SELECT 1
    FROM mst.Roles actual
    LEFT JOIN @ExpectedRoles expected ON expected.RoleId=actual.RoleId
    WHERE actual.IsActive=1 AND expected.RoleId IS NULL
)
    THROW 52986, 'The six approved role IDs, codes, scopes, and assignability values must remain unchanged.', 1;

IF COL_LENGTH(N'mst.RolePermissions',N'TenantTypeId') IS NULL
    ALTER TABLE mst.RolePermissions ADD TenantTypeId BIGINT NULL;
IF COL_LENGTH(N'mst.RolePermissions',N'MatrixRowVersion') IS NULL
    ALTER TABLE mst.RolePermissions ADD MatrixRowVersion ROWVERSION;

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID(N'mst.RolePermissions')
      AND name=N'UX_RolePermissions_RoleId_PermissionId'
)
    DROP INDEX UX_RolePermissions_RoleId_PermissionId ON mst.RolePermissions;
IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID(N'mst.RolePermissions')
      AND name=N'UX_RolePermissions_RoleId_PermissionId_TenantTypeId'
)
    CREATE UNIQUE INDEX UX_RolePermissions_RoleId_PermissionId_TenantTypeId
        ON mst.RolePermissions(RoleId,PermissionId,TenantTypeId);
IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id=OBJECT_ID(N'mst.RolePermissions')
      AND name=N'FK_RolePermissions_TenantTypes'
)
    ALTER TABLE mst.RolePermissions WITH CHECK
        ADD CONSTRAINT FK_RolePermissions_TenantTypes
        FOREIGN KEY(TenantTypeId) REFERENCES mst.TenantTypes(TenantTypeId);

INSERT mst.RolePermissions(RoleId,PermissionId,TenantTypeId,CreatedAtUtc,CreatedByUserId)
SELECT mapping.RoleId,mapping.PermissionId,@PersonalTenantTypeId,mapping.CreatedAtUtc,mapping.CreatedByUserId
FROM mst.RolePermissions mapping
JOIN mst.Roles role ON role.RoleId=mapping.RoleId AND role.RoleScopeId=@TenantScopeId
WHERE mapping.TenantTypeId IS NULL
  AND NOT EXISTS
  (
      SELECT 1 FROM mst.RolePermissions existing
      WHERE existing.RoleId=mapping.RoleId
        AND existing.PermissionId=mapping.PermissionId
        AND existing.TenantTypeId=@PersonalTenantTypeId
  );

UPDATE mapping
SET TenantTypeId=@OrganizationTenantTypeId
FROM mst.RolePermissions mapping
JOIN mst.Roles role ON role.RoleId=mapping.RoleId AND role.RoleScopeId=@TenantScopeId
WHERE mapping.TenantTypeId IS NULL;

IF EXISTS
(
    SELECT 1
    FROM mst.RolePermissions mapping
    JOIN mst.Roles role ON role.RoleId=mapping.RoleId
    JOIN mst.Permissions permission ON permission.PermissionId=mapping.PermissionId
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
    JOIN mst.RoleScopes permissionScope ON permissionScope.RoleScopeId=permission.RoleScopeId
    LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=mapping.TenantTypeId
    WHERE roleScope.Code<>permissionScope.Code
       OR roleScope.Code NOT IN('PLATFORM','TENANT')
       OR (roleScope.Code='PLATFORM' AND mapping.TenantTypeId IS NOT NULL)
       OR (roleScope.Code='TENANT' AND
           (tenantType.TenantTypeId IS NULL OR tenantType.IsActive=0
            OR tenantType.Code NOT IN('PERSONAL','ORGANIZATION')))
)
    THROW 52986, 'A role-permission mapping has an invalid authorization scope or tenant type.', 1;

IF EXISTS(SELECT 1 FROM mst.RoleScopes WHERE Code='ACCOUNT')
    THROW 52988, 'Account self-service is policy information and must remain outside the role-scope hierarchy.', 1;

IF OBJECT_ID(N'mst.PermissionReadinessStatuses',N'U') IS NULL
BEGIN
    CREATE TABLE mst.PermissionReadinessStatuses
    (
        Code VARCHAR(30) NOT NULL CONSTRAINT PK_PermissionReadinessStatuses PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        AllowsEffective BIT NOT NULL,
        AllowsMatrixEdit BIT NOT NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_PermissionReadinessStatuses_IsActive DEFAULT(1)
    );
END;

IF OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NULL
BEGIN
    CREATE TABLE mst.PermissionMatrixMetadata
    (
        PermissionId BIGINT NOT NULL CONSTRAINT PK_PermissionMatrixMetadata PRIMARY KEY,
        ModuleCode VARCHAR(80) NOT NULL,
        ResourceCode VARCHAR(100) NOT NULL,
        ActionCode VARCHAR(120) NOT NULL,
        PermissionDescription NVARCHAR(1000) NOT NULL,
        ReadinessCode VARCHAR(30) NOT NULL,
        RestrictionReason NVARCHAR(500) NULL,
        UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_PermissionMatrixMetadata_UpdatedAtUtc DEFAULT(SYSUTCDATETIME()),
        MatrixRowVersion ROWVERSION NOT NULL,
        CONSTRAINT FK_PermissionMatrixMetadata_Permissions
            FOREIGN KEY(PermissionId) REFERENCES mst.Permissions(PermissionId),
        CONSTRAINT FK_PermissionMatrixMetadata_Readiness
            FOREIGN KEY(ReadinessCode) REFERENCES mst.PermissionReadinessStatuses(Code)
    );
END;

INSERT mst.PermissionReadinessStatuses(Code,Name,AllowsEffective,AllowsMatrixEdit)
SELECT seed.Code,seed.Name,seed.AllowsEffective,seed.AllowsMatrixEdit
FROM (VALUES
    ('ACTIVE',N'Active',CONVERT(BIT,1),CONVERT(BIT,1)),
    ('PLANNED',N'Planned',CONVERT(BIT,0),CONVERT(BIT,0)),
    ('HOLD',N'Hold',CONVERT(BIT,0),CONVERT(BIT,0)),
    ('CONDITIONAL',N'Conditional',CONVERT(BIT,0),CONVERT(BIT,0)),
    ('SYSTEM RESTRICTED',N'System restricted',CONVERT(BIT,1),CONVERT(BIT,0)),
    ('INVALID SCOPE',N'Invalid scope',CONVERT(BIT,0),CONVERT(BIT,0))
) seed(Code,Name,AllowsEffective,AllowsMatrixEdit)
WHERE NOT EXISTS
(
    SELECT 1 FROM mst.PermissionReadinessStatuses existing
    WHERE existing.Code=seed.Code
);

IF EXISTS
(
    SELECT 1 FROM mst.PermissionReadinessStatuses
    WHERE (Code='ACTIVE' AND (AllowsEffective<>1 OR AllowsMatrixEdit<>1))
       OR (Code IN('PLANNED','HOLD','CONDITIONAL','INVALID SCOPE')
           AND (AllowsEffective<>0 OR AllowsMatrixEdit<>0))
       OR (Code='SYSTEM RESTRICTED' AND (AllowsEffective<>1 OR AllowsMatrixEdit<>0))
)
    THROW 52987, 'Permission readiness policy differs from the approved fail-closed matrix rules.', 1;

DECLARE @PermissionSeeds TABLE
(
    Code VARCHAR(150) NOT NULL PRIMARY KEY,
    ScopeCode VARCHAR(50) NOT NULL,
    Name NVARCHAR(300) NOT NULL,
    Description NVARCHAR(1000) NOT NULL,
    SortOrder INT NOT NULL,
    ReadinessCode VARCHAR(30) NOT NULL,
    IsActive BIT NOT NULL
);

INSERT @PermissionSeeds
    (Code,ScopeCode,Name,Description,SortOrder,ReadinessCode,IsActive)
VALUES
('platform.role_permissions.read','PLATFORM',N'Read role permission matrix',N'View configured grants, scope eligibility, readiness, restrictions, and audit history.',760,'SYSTEM RESTRICTED',1),
('platform.role_permissions.update','PLATFORM',N'Update role permission matrix',N'Validate and save approved role permission changes through a transactional batch.',761,'SYSTEM RESTRICTED',1);

IF OBJECT_ID(N'mst.AccountSelfServicePolicies',N'U') IS NULL
BEGIN
    CREATE TABLE mst.AccountSelfServicePolicies
    (
        PolicyCode VARCHAR(150) NOT NULL CONSTRAINT PK_AccountSelfServicePolicies PRIMARY KEY,
        ModuleCode VARCHAR(80) NOT NULL,
        ResourceCode VARCHAR(100) NOT NULL,
        ActionCode VARCHAR(120) NOT NULL,
        Name NVARCHAR(300) NOT NULL,
        Description NVARCHAR(1000) NOT NULL,
        ReadinessCode VARCHAR(30) NOT NULL,
        PublicAllowed BIT NOT NULL,
        UnverifiedAllowed BIT NOT NULL,
        VerifiedAllowed BIT NOT NULL,
        RestrictionReason NVARCHAR(500) NOT NULL,
        SortOrder INT NOT NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_AccountSelfServicePolicies_IsActive DEFAULT(1),
        UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_AccountSelfServicePolicies_UpdatedAtUtc DEFAULT(SYSUTCDATETIME()),
        MatrixRowVersion ROWVERSION NOT NULL,
        CONSTRAINT FK_AccountSelfServicePolicies_Readiness
            FOREIGN KEY(ReadinessCode) REFERENCES mst.PermissionReadinessStatuses(Code)
    );
END;

DECLARE @AccountPolicySeeds TABLE
(
    PolicyCode VARCHAR(150) NOT NULL PRIMARY KEY,
    Name NVARCHAR(300) NOT NULL,
    Description NVARCHAR(1000) NOT NULL,
    ReadinessCode VARCHAR(30) NOT NULL,
    PublicAllowed BIT NOT NULL,
    UnverifiedAllowed BIT NOT NULL,
    VerifiedAllowed BIT NOT NULL,
    RestrictionReason NVARCHAR(500) NOT NULL,
    SortOrder INT NOT NULL
);
INSERT @AccountPolicySeeds
    (PolicyCode,Name,Description,ReadinessCode,PublicAllowed,UnverifiedAllowed,
     VerifiedAllowed,RestrictionReason,SortOrder)
VALUES
('account.self_service.register',N'Register account',N'Create a local account.', 'ACTIVE',1,0,0,N'Informational self-service policy; not a role grant.',800),
('account.self_service.email.verify',N'Verify email using valid token',N'Confirm the account email with a valid token.', 'ACTIVE',1,1,0,N'Informational self-service policy; not a role grant.',801),
('account.self_service.email.resend',N'Resend verification email',N'Request delivery of a new verification email.', 'ACTIVE',1,1,0,N'Informational self-service policy; not a role grant.',802),
('account.self_service.login',N'Login',N'Create an authenticated session after credential and verification checks.', 'ACTIVE',1,0,1,N'Informational self-service policy; session and account checks remain authoritative.',803),
('account.self_service.password.reset.request',N'Request password reset',N'Request a password reset; reset workflow is not implemented.', 'PLANNED',1,1,1,N'Password reset is not implemented; policy values are informational only.',804),
('account.self_service.profile.read',N'View own account',N'Read the authenticated account profile.', 'ACTIVE',0,0,1,N'Informational self-service policy; authenticated identity is required.',805),
('account.self_service.profile.update',N'Update own account profile',N'Update the authenticated account profile.', 'PLANNED',0,0,1,N'No approved profile-update endpoint is available.',806),
('account.self_service.password.change',N'Change own password',N'Change the authenticated account password.', 'PLANNED',0,0,1,N'No approved password-change endpoint is available.',807),
('account.self_service.registration.read',N'View own registration status',N'Read the authenticated account registration status.', 'ACTIVE',0,0,1,N'Informational self-service policy; authenticated identity is required.',808),
('account.self_service.registration.complete',N'Complete registration profile',N'Complete the authenticated account registration profile.', 'ACTIVE',0,0,1,N'Informational self-service policy; authenticated identity is required.',809),
('account.self_service.registration.submit',N'Submit registration application',N'Submit an application only when all conditional verification and consent policies are satisfied.', 'CONDITIONAL',0,0,0,N'Conditional verification and consent policy is not implemented.',810),
('account.self_service.security_activity.read',N'View own security activity',N'Read security activity for the authenticated account.', 'PLANNED',0,0,1,N'No approved security-activity endpoint is available.',811),
('account.self_service.sessions.manage',N'Manage own sessions',N'Revoke or otherwise manage the authenticated account sessions.', 'PLANNED',0,0,1,N'Session inventory management is not implemented.',812),
('account.self_service.tenant.access',N'Access Tenant workspace',N'Access tenant data only with a valid verified session and active tenant membership.', 'CONDITIONAL',0,0,0,N'Tenant access requires valid session, active membership, and tenant-scoped permissions.',813),
('account.self_service.users.read',N'View other user accounts',N'Cross-user account access is denied by default.', 'SYSTEM RESTRICTED',0,0,0,N'Cross-user account access is denied by default.',814),
('account.self_service.platform.access',N'Access Platform Administration',N'Platform access requires the explicit database-backed platform permission checks.', 'CONDITIONAL',0,0,0,N'Platform access requires explicit database-backed platform permission checks.',815);

IF EXISTS
(
    SELECT 1
    FROM @AccountPolicySeeds seed
    JOIN mst.Permissions permission ON permission.Code=seed.PolicyCode
)
    THROW 52988, 'Account policy identifiers must not be inserted into the grantable permission master.', 1;
IF EXISTS
(
    SELECT 1
    FROM @AccountPolicySeeds seed
    JOIN mst.AccountSelfServicePolicies policy ON policy.PolicyCode=seed.PolicyCode
    WHERE policy.Name<>seed.Name
       OR policy.Description<>seed.Description
       OR policy.ReadinessCode<>seed.ReadinessCode
       OR policy.PublicAllowed<>seed.PublicAllowed
       OR policy.UnverifiedAllowed<>seed.UnverifiedAllowed
       OR policy.VerifiedAllowed<>seed.VerifiedAllowed
       OR policy.RestrictionReason<>seed.RestrictionReason
       OR policy.SortOrder<>seed.SortOrder
)
    THROW 52988, 'An existing account policy differs from the approved read-only matrix catalog.', 1;

DECLARE @SeededAccountPolicies TABLE(PolicyCode VARCHAR(150) NOT NULL PRIMARY KEY);
INSERT mst.AccountSelfServicePolicies
    (PolicyCode,ModuleCode,ResourceCode,ActionCode,Name,Description,ReadinessCode,
     PublicAllowed,UnverifiedAllowed,VerifiedAllowed,RestrictionReason,SortOrder)
OUTPUT inserted.PolicyCode INTO @SeededAccountPolicies(PolicyCode)
SELECT seed.PolicyCode,
       LEFT(seed.PolicyCode,CHARINDEX('.',seed.PolicyCode)-1),
       SUBSTRING(seed.PolicyCode,CHARINDEX('.',seed.PolicyCode)+1,
           CASE WHEN CHARINDEX('.',seed.PolicyCode,CHARINDEX('.',seed.PolicyCode)+1)=0
                THEN LEN(seed.PolicyCode)
                ELSE CHARINDEX('.',seed.PolicyCode,CHARINDEX('.',seed.PolicyCode)+1)
                     -CHARINDEX('.',seed.PolicyCode)-1 END),
       CASE WHEN CHARINDEX('.',seed.PolicyCode,CHARINDEX('.',seed.PolicyCode)+1)=0
            THEN 'unspecified'
            ELSE SUBSTRING(seed.PolicyCode,
                 CHARINDEX('.',seed.PolicyCode,CHARINDEX('.',seed.PolicyCode)+1)+1,120) END,
       seed.Name,seed.Description,seed.ReadinessCode,seed.PublicAllowed,
       seed.UnverifiedAllowed,seed.VerifiedAllowed,seed.RestrictionReason,seed.SortOrder
FROM @AccountPolicySeeds seed
WHERE NOT EXISTS
(
    SELECT 1 FROM mst.AccountSelfServicePolicies existing
    WHERE existing.PolicyCode=seed.PolicyCode
);

IF EXISTS
(
    SELECT 1
    FROM @PermissionSeeds seed
    JOIN mst.Permissions existing ON existing.Code=seed.Code
    JOIN mst.RoleScopes scope ON scope.RoleScopeId=existing.RoleScopeId
    WHERE scope.Code<>seed.ScopeCode
       OR existing.IsSystem<>1
)
    THROW 52989, 'A matrix permission code exists with an incompatible scope or system flag.', 1;

DECLARE @SeededPermissions TABLE
(
    PermissionId BIGINT NOT NULL PRIMARY KEY,
    Code VARCHAR(150) NOT NULL
);
INSERT mst.Permissions
    (RoleScopeId,Code,Name,Description,SortOrder,IsActive,IsSystem,CreatedAtUtc)
OUTPUT inserted.PermissionId,inserted.Code INTO @SeededPermissions(PermissionId,Code)
SELECT scope.RoleScopeId,seed.Code,seed.Name,seed.Description,seed.SortOrder,
       seed.IsActive,1,SYSUTCDATETIME()
FROM @PermissionSeeds seed
JOIN mst.RoleScopes scope ON scope.Code=seed.ScopeCode AND scope.IsActive=1
WHERE NOT EXISTS(SELECT 1 FROM mst.Permissions existing WHERE existing.Code=seed.Code);

IF EXISTS
(
    SELECT 1 FROM @PermissionSeeds seed
    JOIN mst.Permissions permission ON permission.Code=seed.Code
    LEFT JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
    WHERE scope.Code<>seed.ScopeCode
)
    THROW 52989, 'Permission master scope validation failed for a matrix catalog entry.', 1;

DECLARE @SeededRolePermissions TABLE
(
    RoleId BIGINT NOT NULL,
    PermissionId BIGINT NOT NULL,
    PRIMARY KEY(RoleId,PermissionId)
);
INSERT mst.RolePermissions(RoleId,PermissionId,TenantTypeId,CreatedAtUtc)
OUTPUT inserted.RoleId,inserted.PermissionId
    INTO @SeededRolePermissions(RoleId,PermissionId)
SELECT superAdmin.RoleId,permission.PermissionId,NULL,SYSUTCDATETIME()
FROM mst.Roles superAdmin
JOIN mst.RoleScopes scope ON scope.RoleScopeId=superAdmin.RoleScopeId AND scope.Code='PLATFORM'
JOIN mst.Permissions permission
  ON permission.Code IN('platform.role_permissions.read','platform.role_permissions.update')
 AND permission.RoleScopeId=superAdmin.RoleScopeId
WHERE superAdmin.RoleId=1 AND superAdmin.Code='SUPER_ADMIN'
  AND NOT EXISTS
  (
      SELECT 1 FROM mst.RolePermissions existing
      WHERE existing.RoleId=superAdmin.RoleId
        AND existing.PermissionId=permission.PermissionId
        AND existing.TenantTypeId IS NULL
  );

DECLARE @MatrixSeedCorrelationId UNIQUEIDENTIFIER=NEWID();
DECLARE @MatrixSeedCreateActionId BIGINT=
    (SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1);
DECLARE @MatrixSeedUpdateActionId BIGINT=
    (SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='UPDATE' AND IsActive=1);
DECLARE @MatrixSeedSuccessId BIGINT=
    (SELECT AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1);
IF EXISTS(SELECT 1 FROM @SeededPermissions)
   AND (@MatrixSeedCreateActionId IS NULL OR @MatrixSeedSuccessId IS NULL)
    THROW 52989, 'Permission catalog seed audit metadata is unavailable.', 1;
IF EXISTS(SELECT 1 FROM @SeededAccountPolicies)
   AND (@MatrixSeedCreateActionId IS NULL OR @MatrixSeedSuccessId IS NULL)
    THROW 52989, 'Account policy seed audit metadata is unavailable.', 1;
IF EXISTS(SELECT 1 FROM @SeededRolePermissions)
   AND (@MatrixSeedUpdateActionId IS NULL OR @MatrixSeedSuccessId IS NULL)
    THROW 52989, 'Role permission seed audit metadata is unavailable.', 1;

INSERT aud.AuditEvents
    (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
     ChangeSummaryJson,RequestId,CorrelationId)
SELECT CONCAT(N'KLOP.RBAC.V1.10 DBA: ',SUSER_SNAME()),@MatrixSeedCreateActionId,
         @MatrixSeedSuccessId,N'PERMISSION_CATALOG',seeded.Code,
         (SELECT seeded.Code AS PermissionCode,scope.Code AS ScopeCode,
                 seed.ReadinessCode AS ReadinessStatus
          FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
         CONVERT(VARCHAR(100),@ApprovalTicket),@MatrixSeedCorrelationId
FROM @SeededPermissions seeded
JOIN mst.Permissions permission ON permission.PermissionId=seeded.PermissionId
JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
JOIN @PermissionSeeds seed ON seed.Code=seeded.Code;

INSERT aud.AuditEvents
    (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
     ChangeSummaryJson,RequestId,CorrelationId)
SELECT CONCAT(N'KLOP.RBAC.V1.10 DBA: ',SUSER_SNAME()),@MatrixSeedUpdateActionId,
         @MatrixSeedSuccessId,N'ROLE_PERMISSION',CONCAT(role.Code,N':',permission.Code),
         (SELECT role.Code AS RoleCode,permission.Code AS PermissionCode,
                 CAST(1 AS BIT) AS NewGrant
          FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
         CONVERT(VARCHAR(100),@ApprovalTicket),@MatrixSeedCorrelationId
FROM @SeededRolePermissions seeded
JOIN mst.Roles role ON role.RoleId=seeded.RoleId
JOIN mst.Permissions permission ON permission.PermissionId=seeded.PermissionId;

INSERT aud.AuditEvents
    (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
     ChangeSummaryJson,RequestId,CorrelationId)
SELECT CONCAT(N'KLOP.RBAC.V1.10 DBA: ',SUSER_SNAME()),@MatrixSeedCreateActionId,
         @MatrixSeedSuccessId,N'ACCOUNT_SELF_SERVICE_POLICY',policy.PolicyCode,
         (SELECT policy.PolicyCode,policy.ReadinessCode AS ReadinessStatus,
                 policy.PublicAllowed,policy.UnverifiedAllowed,policy.VerifiedAllowed
          FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
         CONVERT(VARCHAR(100),@ApprovalTicket),@MatrixSeedCorrelationId
FROM @SeededAccountPolicies seeded
JOIN mst.AccountSelfServicePolicies policy ON policy.PolicyCode=seeded.PolicyCode;

INSERT mst.PermissionMatrixMetadata
    (PermissionId,ModuleCode,ResourceCode,ActionCode,PermissionDescription,ReadinessCode,
     RestrictionReason)
SELECT permission.PermissionId,
       LEFT(permission.Code,CHARINDEX('.',permission.Code)-1),
       SUBSTRING(permission.Code,CHARINDEX('.',permission.Code)+1,
           CASE WHEN CHARINDEX('.',permission.Code,CHARINDEX('.',permission.Code)+1)=0
                THEN LEN(permission.Code)
                ELSE CHARINDEX('.',permission.Code,CHARINDEX('.',permission.Code)+1)
                     -CHARINDEX('.',permission.Code)-1 END),
       CASE WHEN CHARINDEX('.',permission.Code,CHARINDEX('.',permission.Code)+1)=0
            THEN 'unspecified'
            ELSE SUBSTRING(permission.Code,
                 CHARINDEX('.',permission.Code,CHARINDEX('.',permission.Code)+1)+1,120) END,
       COALESCE(permission.Description,CONCAT(permission.Name,N' capability.')),
       CASE WHEN permission.Code IN
            ('platform.role_permissions.read','platform.role_permissions.update',
             'platform.permissions.manage')
            THEN 'SYSTEM RESTRICTED'
            WHEN permission.Code IN
            ('platform.config.manage','platform.roles.manage','platform.tenants.manage',
             'platform.verifications.review')
            THEN 'HOLD'
            WHEN seed.Code IS NOT NULL THEN seed.ReadinessCode
            WHEN permission.IsActive=1 THEN 'ACTIVE'
            ELSE 'PLANNED' END,
       CASE
           WHEN permission.Code IN('platform.role_permissions.read','platform.role_permissions.update')
               THEN N'Essential matrix access; system restricted and not editable through this matrix.'
           WHEN permission.Code='platform.permissions.manage'
               THEN N'Legacy broad permission capability is locked; use the explicit matrix read/update permissions.'
           WHEN permission.Code IN('platform.config.manage','platform.roles.manage',
                                   'platform.tenants.manage','platform.verifications.review')
               THEN N'Platform Setup capabilities remain on HOLD outside the approved matrix scope.'
           WHEN readiness.AllowsMatrixEdit=0
               THEN N'Permission is not ready for activation; matrix changes are disabled.'
           ELSE NULL
       END
FROM mst.Permissions permission
JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
LEFT JOIN @PermissionSeeds seed ON seed.Code=permission.Code
LEFT JOIN mst.PermissionReadinessStatuses readiness
  ON readiness.Code=CASE WHEN permission.Code IN
      ('platform.role_permissions.read','platform.role_permissions.update',
       'platform.permissions.manage')
      THEN 'SYSTEM RESTRICTED'
      WHEN permission.Code IN
      ('platform.config.manage','platform.roles.manage','platform.tenants.manage',
       'platform.verifications.review')
      THEN 'HOLD'
      WHEN seed.Code IS NOT NULL THEN seed.ReadinessCode
      WHEN permission.IsActive=1 THEN 'ACTIVE'
      ELSE 'PLANNED' END
WHERE NOT EXISTS
(
    SELECT 1 FROM mst.PermissionMatrixMetadata existing
    WHERE existing.PermissionId=permission.PermissionId
);

IF EXISTS
(
    SELECT 1
    FROM mst.Permissions permission
    JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
    LEFT JOIN mst.PermissionMatrixMetadata matrix
      ON matrix.PermissionId=permission.PermissionId
    WHERE matrix.PermissionId IS NULL
)
    THROW 52989, 'Every permission must have matrix readiness metadata.', 1;

EXEC sys.sp_executesql N'
CREATE OR ALTER TRIGGER mst.trg_RolePermissions_ValidateMatrixScope
ON mst.RolePermissions
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (
        SELECT 1
        FROM inserted mapping
        JOIN mst.Roles role ON role.RoleId=mapping.RoleId
        JOIN mst.Permissions permission ON permission.PermissionId=mapping.PermissionId
        JOIN mst.RoleScopes scope ON scope.RoleScopeId=role.RoleScopeId
        WHERE role.RoleScopeId<>permission.RoleScopeId
           OR scope.Code NOT IN(''PLATFORM'',''TENANT'')
           OR (scope.Code=''PLATFORM'' AND mapping.TenantTypeId IS NOT NULL)
           OR (scope.Code=''TENANT'' AND mapping.TenantTypeId IS NULL)
    )
        THROW 52995, ''Role permission scope and tenant context are incompatible.'', 1;
END;';

GO

CREATE OR ALTER PROCEDURE iam.usp_ValidateSessionAccess
    @UserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @TenantId BIGINT=NULL,
    @PermissionCode VARCHAR(120)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME2(3)=SYSUTCDATETIME();

    IF NOT EXISTS
    (
        SELECT 1
        FROM iam.AuthSessions session
        JOIN iam.Users usr ON usr.UserId=session.UserId
        WHERE session.PublicSessionId=@PublicSessionId
          AND session.UserId=@UserId
          AND session.RevokedAtUtc IS NULL
          AND session.ExpiresAtUtc>@Now
          AND usr.IsActive=1
          AND usr.EmailVerifiedAtUtc IS NOT NULL
    )
        THROW 52330, 'Session inactive', 1;

    IF @TenantId IS NOT NULL
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM ten.TenantMemberships membership
            JOIN mst.MembershipStatuses membershipStatus
              ON membershipStatus.MembershipStatusId=membership.MembershipStatusId
             AND membershipStatus.Code='ACTIVE'
             AND membershipStatus.IsActive=1
            JOIN ten.Tenants tenant ON tenant.TenantId=membership.TenantId
            JOIN mst.TenantStatuses tenantStatus
              ON tenantStatus.TenantStatusId=tenant.TenantStatusId
             AND tenantStatus.Code IN('ACTIVE','PENDING')
             AND tenantStatus.IsActive=1
            JOIN mst.TenantTypes tenantType
              ON tenantType.TenantTypeId=tenant.TenantTypeId
             AND tenantType.IsActive=1
            WHERE membership.UserId=@UserId
              AND membership.TenantId=@TenantId
        )
            THROW 52331, 'Tenant membership inactive', 1;

        IF @PermissionCode IS NOT NULL AND NOT EXISTS
        (
            SELECT 1
            FROM ten.TenantMemberships membership
            JOIN mst.MembershipStatuses membershipStatus
              ON membershipStatus.MembershipStatusId=membership.MembershipStatusId
             AND membershipStatus.Code='ACTIVE'
             AND membershipStatus.IsActive=1
            JOIN ten.Tenants tenant ON tenant.TenantId=membership.TenantId
            JOIN mst.TenantTypes tenantType
              ON tenantType.TenantTypeId=tenant.TenantTypeId
             AND tenantType.IsActive=1
            JOIN iam.TenantRoleAssignments assignment ON assignment.MembershipId=membership.MembershipId
            JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.IsActive=1
            JOIN mst.RoleScopes roleScope
              ON roleScope.RoleScopeId=role.RoleScopeId
             AND roleScope.Code='TENANT'
             AND roleScope.IsActive=1
            JOIN mst.RolePermissions mapping ON mapping.RoleId=role.RoleId
             AND mapping.TenantTypeId=tenantType.TenantTypeId
            JOIN mst.Permissions permission
              ON permission.PermissionId=mapping.PermissionId
             AND permission.RoleScopeId=roleScope.RoleScopeId
             AND permission.Code=@PermissionCode
             AND permission.IsActive=1
            JOIN mst.PermissionMatrixMetadata matrix
              ON matrix.PermissionId=permission.PermissionId
            JOIN mst.PermissionReadinessStatuses readiness
              ON readiness.Code=matrix.ReadinessCode
             AND readiness.IsActive=1
             AND readiness.AllowsEffective=1
            WHERE membership.UserId=@UserId
              AND membership.TenantId=@TenantId
              AND NOT
              (
                  tenantType.AllowMultipleMembers=0
                  AND @PermissionCode IN
                  ('tenant.members.invite','tenant.members.remove','tenant.roles.assign')
              )
        )
            THROW 52332, 'Permission denied', 1;
    END
    ELSE IF @PermissionCode IS NOT NULL
        THROW 52333, 'Tenant required for permission', 1;

    SELECT CAST(1 AS BIT) AS IsAuthorized;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_AssignTenantRole
    @MembershipId BIGINT,
    @ActorUserId BIGINT,
    @RoleCode VARCHAR(50),
    @RequestId VARCHAR(100)=NULL,
    @CorrelationId UNIQUEIDENTIFIER=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0
        THROW 52170, 'Procedure must own the transaction.', 1;

    DECLARE @TenantId BIGINT,
            @RoleId BIGINT,
            @RoleName VARCHAR(50)=UPPER(LTRIM(RTRIM(@RoleCode))),
            @ActiveStatusId BIGINT,
            @OwnerRoleId BIGINT,
            @ActionId BIGINT,
            @ResultId BIGINT,
            @AllowMultipleMembers BIT,
            @TenantTypeId BIGINT,
            @Assignable BIT,
            @ActiveOwnerCount BIGINT,
            @LockResult INT,
            @LockResource NVARCHAR(255),
            @Json NVARCHAR(MAX);

    IF @MembershipId IS NULL OR @ActorUserId IS NULL OR @RoleName IS NULL OR @RoleName=''
        THROW 52171, 'Invalid role assignment parameters.', 1;

    SELECT @TenantId=membership.TenantId
    FROM ten.TenantMemberships membership
    WHERE membership.MembershipId=@MembershipId;
    IF @TenantId IS NULL
        THROW 52172, 'Target membership not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @LockResource=CONCAT(N'KLOP/TENANT/',CONVERT(NVARCHAR(20),@TenantId));
        EXEC @LockResult=sys.sp_getapplock
            @Resource=@LockResource,
            @LockMode='Exclusive',
            @LockOwner='Transaction',
            @LockTimeout=10000;
        IF @LockResult<0
            THROW 52192, 'Tenant role operation is busy.', 1;

        SELECT @ActiveStatusId=MembershipStatusId
        FROM mst.MembershipStatuses
        WHERE Code='ACTIVE' AND IsActive=1;
        SELECT @OwnerRoleId=role.RoleId
        FROM mst.Roles role
        JOIN mst.RoleScopes scope ON scope.RoleScopeId=role.RoleScopeId
        WHERE scope.Code='TENANT' AND scope.IsActive=1
          AND role.Code='OWNER' AND role.IsActive=1;
        SELECT @ActionId=AuditActionTypeId
        FROM mst.AuditActionTypes
        WHERE Code='ASSIGN_ROLE' AND IsActive=1;
        SELECT @ResultId=AuditResultTypeId
        FROM mst.AuditResultTypes
        WHERE Code='SUCCESS' AND IsActive=1;
        IF @ActiveStatusId IS NULL OR @OwnerRoleId IS NULL
           OR @ActionId IS NULL OR @ResultId IS NULL
            THROW 52174, 'Role or required master data unavailable.', 1;

        SELECT @AllowMultipleMembers=tenantType.AllowMultipleMembers,
               @TenantTypeId=tenantType.TenantTypeId
        FROM ten.Tenants tenant
        JOIN mst.TenantTypes tenantType
          ON tenantType.TenantTypeId=tenant.TenantTypeId
         AND tenantType.IsActive=1
        JOIN mst.TenantStatuses tenantStatus
          ON tenantStatus.TenantStatusId=tenant.TenantStatusId
         AND tenantStatus.Code IN('ACTIVE','PENDING')
         AND tenantStatus.IsActive=1
        WHERE tenant.TenantId=@TenantId;
        IF @AllowMultipleMembers IS NULL
            THROW 52174, 'Tenant is not active or eligible for role management.', 1;
        IF @AllowMultipleMembers=0
            THROW 52191, 'Role assignment is not allowed for a PERSONAL tenant.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM ten.TenantMemberships membership WITH(UPDLOCK,HOLDLOCK)
            WHERE membership.MembershipId=@MembershipId
              AND membership.TenantId=@TenantId
              AND membership.MembershipStatusId=@ActiveStatusId
        )
            THROW 52175, 'Target must be an active tenant member.', 1;

        SELECT @ActiveOwnerCount=COUNT_BIG(*)
        FROM ten.TenantMemberships membership
        JOIN iam.TenantRoleAssignments assignment
          ON assignment.MembershipId=membership.MembershipId
         AND assignment.RoleId=@OwnerRoleId
        WHERE membership.TenantId=@TenantId
          AND membership.MembershipStatusId=@ActiveStatusId;
        IF @ActiveOwnerCount<>1
            THROW 52192, 'Role changes require exactly one active OWNER; resolve ownership manually.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM ten.TenantMemberships actorMembership
            JOIN iam.TenantRoleAssignments actorAssignment
              ON actorAssignment.MembershipId=actorMembership.MembershipId
            JOIN mst.Roles actorRole
              ON actorRole.RoleId=actorAssignment.RoleId
             AND actorRole.IsActive=1
            JOIN mst.RoleScopes actorScope
              ON actorScope.RoleScopeId=actorRole.RoleScopeId
             AND actorScope.Code='TENANT'
             AND actorScope.IsActive=1
            JOIN mst.RolePermissions mapping
              ON mapping.RoleId=actorRole.RoleId
             AND mapping.TenantTypeId=@TenantTypeId
            JOIN mst.Permissions permission
              ON permission.PermissionId=mapping.PermissionId
             AND permission.RoleScopeId=actorScope.RoleScopeId
             AND permission.Code='tenant.roles.assign'
             AND permission.IsActive=1
            JOIN mst.PermissionMatrixMetadata matrix
              ON matrix.PermissionId=permission.PermissionId
            JOIN mst.PermissionReadinessStatuses readiness
              ON readiness.Code=matrix.ReadinessCode
             AND readiness.IsActive=1
             AND readiness.AllowsEffective=1
            WHERE actorMembership.TenantId=@TenantId
              AND actorMembership.UserId=@ActorUserId
              AND actorMembership.MembershipStatusId=@ActiveStatusId
        )
            THROW 52191, 'Actor lacks tenant role assignment permission.', 1;

        SELECT @RoleId=role.RoleId,@Assignable=role.IsAssignable
        FROM mst.Roles role
        JOIN mst.RoleScopes scope
          ON scope.RoleScopeId=role.RoleScopeId
         AND scope.Code='TENANT'
         AND scope.IsActive=1
        WHERE role.Code=@RoleName AND role.IsActive=1;
        IF @RoleId IS NULL
            THROW 52174, 'Role or required master data unavailable.', 1;
        IF @Assignable=0
            THROW 52191, 'The requested tenant role is not assignable.', 1;
        IF @RoleName NOT IN('MEMBER','ADMIN')
            THROW 52191, 'Only approved MEMBER and ADMIN assignments are enabled; OWNER transfer remains on HOLD.', 1;
        IF @RoleName='ADMIN' AND NOT EXISTS
        (
            SELECT 1
            FROM ten.TenantMemberships actorMembership
            JOIN iam.TenantRoleAssignments actorAssignment
              ON actorAssignment.MembershipId=actorMembership.MembershipId
             AND actorAssignment.RoleId=@OwnerRoleId
            WHERE actorMembership.TenantId=@TenantId
              AND actorMembership.UserId=@ActorUserId
              AND actorMembership.MembershipStatusId=@ActiveStatusId
        )
            THROW 52191, 'Only an active OWNER may assign the ADMIN role.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM ten.TenantMemberships actorMembership
            WHERE actorMembership.MembershipId=@MembershipId
              AND actorMembership.UserId=@ActorUserId
        )
            THROW 52191, 'A user cannot assign a role to their own membership.', 1;

        IF EXISTS
        (
            SELECT 1 FROM iam.TenantRoleAssignments WITH(UPDLOCK,HOLDLOCK)
            WHERE MembershipId=@MembershipId AND RoleId=@RoleId
        )
            THROW 52178, 'Role is already assigned.', 1;

        INSERT iam.TenantRoleAssignments(MembershipId,RoleId,AssignedByUserId)
        VALUES(@MembershipId,@RoleId,@ActorUserId);

        SELECT @Json=
        (
            SELECT @MembershipId AS MembershipId,@RoleName AS RoleCode
            FOR JSON PATH,WITHOUT_ARRAY_WRAPPER
        );
        INSERT aud.AuditEvents
            (TenantId,ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
             ChangeSummaryJson,RequestId,CorrelationId)
        VALUES
            (@TenantId,@ActorUserId,@ActionId,@ResultId,'TENANT_ROLE',
             CONVERT(NVARCHAR(150),@MembershipId),@Json,@RequestId,@CorrelationId);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_GetTenantPermissions
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @TenantId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @SessionValidation TABLE(IsAuthorized BIT NOT NULL);

    INSERT @SessionValidation(IsAuthorized)
    EXEC iam.usp_ValidateSessionAccess
        @UserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @TenantId=@TenantId,
        @PermissionCode=NULL;

    SELECT DISTINCT permission.Code AS PermissionCode
    FROM ten.TenantMemberships membership
    JOIN mst.MembershipStatuses membershipStatus
      ON membershipStatus.MembershipStatusId=membership.MembershipStatusId
     AND membershipStatus.Code='ACTIVE'
     AND membershipStatus.IsActive=1
    JOIN ten.Tenants tenant ON tenant.TenantId=membership.TenantId
    JOIN mst.TenantStatuses tenantStatus
      ON tenantStatus.TenantStatusId=tenant.TenantStatusId
     AND tenantStatus.Code IN('ACTIVE','PENDING')
     AND tenantStatus.IsActive=1
    JOIN mst.TenantTypes tenantType
      ON tenantType.TenantTypeId=tenant.TenantTypeId
     AND tenantType.IsActive=1
    JOIN iam.TenantRoleAssignments assignment ON assignment.MembershipId=membership.MembershipId
    JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.IsActive=1
    JOIN mst.RoleScopes roleScope
      ON roleScope.RoleScopeId=role.RoleScopeId
     AND roleScope.Code='TENANT'
     AND roleScope.IsActive=1
    JOIN mst.RolePermissions mapping
      ON mapping.RoleId=role.RoleId
     AND mapping.TenantTypeId=tenantType.TenantTypeId
    JOIN mst.Permissions permission
      ON permission.PermissionId=mapping.PermissionId
     AND permission.RoleScopeId=roleScope.RoleScopeId
     AND permission.IsActive=1
    JOIN mst.PermissionMatrixMetadata matrix
      ON matrix.PermissionId=permission.PermissionId
    JOIN mst.PermissionReadinessStatuses readiness
      ON readiness.Code=matrix.ReadinessCode
     AND readiness.IsActive=1
     AND readiness.AllowsEffective=1
    WHERE membership.UserId=@ActorUserId
      AND membership.TenantId=@TenantId
      AND NOT
      (
          tenantType.AllowMultipleMembers=0
          AND permission.Code IN
          ('tenant.members.invite','tenant.members.remove','tenant.roles.assign')
      )
    ORDER BY permission.Code;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_ValidatePlatformPermission
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @PermissionCode VARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;
    IF @PermissionCode NOT IN
    (
        'platform.legal_documents.read',
        'platform.legal_documents.draft.create',
        'platform.legal_documents.draft.edit',
        'platform.legal_documents.draft.preview',
        'platform.legal_documents.submit',
        'platform.legal_documents.approve',
        'platform.legal_documents.publish',
        'platform.legal_documents.archive',
        'platform.registrations.read',
        'platform.role_permissions.read',
        'platform.role_permissions.update'
    )
        THROW 52332, 'Platform permission denied.', 1;

    DECLARE @SessionValidation TABLE(IsAuthorized BIT NOT NULL);
    INSERT @SessionValidation(IsAuthorized)
    EXEC iam.usp_ValidateSessionAccess
        @UserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @TenantId=NULL,
        @PermissionCode=NULL;

    IF NOT EXISTS
    (
        SELECT 1
        FROM iam.PlatformRoleAssignments assignment
        JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.IsActive=1
        JOIN mst.RoleScopes roleScope
          ON roleScope.RoleScopeId=role.RoleScopeId
         AND roleScope.Code='PLATFORM'
         AND roleScope.IsActive=1
        JOIN mst.RolePermissions mapping
          ON mapping.RoleId=role.RoleId
         AND mapping.TenantTypeId IS NULL
        JOIN mst.Permissions permission
          ON permission.PermissionId=mapping.PermissionId
         AND permission.RoleScopeId=roleScope.RoleScopeId
         AND permission.Code=@PermissionCode
         AND permission.IsActive=1
        JOIN mst.PermissionMatrixMetadata matrix
          ON matrix.PermissionId=permission.PermissionId
        JOIN mst.PermissionReadinessStatuses readiness
          ON readiness.Code=matrix.ReadinessCode
         AND readiness.IsActive=1
         AND readiness.AllowsEffective=1
        WHERE assignment.UserId=@ActorUserId
    )
        THROW 52332, 'Platform permission denied.', 1;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_GetPlatformPermissions
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @SessionValidation TABLE(IsAuthorized BIT NOT NULL);
    INSERT @SessionValidation(IsAuthorized)
    EXEC iam.usp_ValidateSessionAccess
        @UserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @TenantId=NULL,
        @PermissionCode=NULL;

    SELECT DISTINCT permission.Code AS PermissionCode
    FROM iam.PlatformRoleAssignments assignment
    JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.IsActive=1
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
        AND roleScope.Code='PLATFORM' AND roleScope.IsActive=1
    JOIN mst.RolePermissions mapping
      ON mapping.RoleId=role.RoleId
     AND mapping.TenantTypeId IS NULL
    JOIN mst.Permissions permission
      ON permission.PermissionId=mapping.PermissionId
     AND permission.RoleScopeId=roleScope.RoleScopeId
     AND permission.IsActive=1
    JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    JOIN mst.PermissionReadinessStatuses readiness
      ON readiness.Code=matrix.ReadinessCode
     AND readiness.IsActive=1
     AND readiness.AllowsEffective=1
    WHERE assignment.UserId=@ActorUserId
      AND permission.Code IN
      (
        'platform.legal_documents.read',
        'platform.legal_documents.draft.create',
        'platform.legal_documents.draft.edit',
        'platform.legal_documents.draft.preview',
        'platform.legal_documents.submit',
        'platform.legal_documents.approve',
        'platform.legal_documents.publish',
        'platform.legal_documents.archive',
        'platform.registrations.read',
        'platform.role_permissions.read',
        'platform.role_permissions.update'
      )
    ORDER BY permission.Code;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_GetUnifiedRolePermissionMatrix
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission
        @ActorUserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @PermissionCode='platform.role_permissions.read';

    ;WITH RoleColumns AS
    (
        SELECT role.RoleId,role.Code AS RoleCode,role.Name AS RoleName,
               roleScope.Code AS RoleScopeCode,CAST(NULL AS BIGINT) AS TenantTypeId,
               CAST(NULL AS VARCHAR(50)) AS TenantTypeCode,role.IsAssignable
        FROM mst.Roles role
        JOIN mst.RoleScopes roleScope
          ON roleScope.RoleScopeId=role.RoleScopeId
         AND roleScope.Code='PLATFORM'
         AND roleScope.IsActive=1
        WHERE role.IsActive=1
        UNION ALL
        SELECT role.RoleId,role.Code,role.Name,roleScope.Code,
               tenantType.TenantTypeId,tenantType.Code,role.IsAssignable
        FROM mst.Roles role
        JOIN mst.RoleScopes roleScope
          ON roleScope.RoleScopeId=role.RoleScopeId
         AND roleScope.Code='TENANT'
         AND roleScope.IsActive=1
        CROSS JOIN mst.TenantTypes tenantType
        WHERE role.IsActive=1
          AND tenantType.IsActive=1
          AND tenantType.Code IN('PERSONAL','ORGANIZATION')
          AND (role.Code='OWNER' OR tenantType.AllowMultipleMembers=1)
    )
    SELECT permission.PermissionId,
           matrix.ModuleCode AS Module,
           matrix.ResourceCode AS Resource,
           matrix.ActionCode AS Action,
           permission.Code AS PermissionCode,
           permission.Name AS PermissionName,
           matrix.PermissionDescription,
           permissionScope.Code AS ScopeCode,
           CASE WHEN roleColumn.RoleScopeCode<>permissionScope.Code
                      OR (permissionScope.Code='PLATFORM' AND roleColumn.TenantTypeId IS NOT NULL)
                      OR (permissionScope.Code='TENANT' AND roleColumn.TenantTypeId IS NULL)
                THEN 'INVALID SCOPE'
                ELSE matrix.ReadinessCode END AS ReadinessStatus,
           CONVERT(BIT,0) AS IsAccountPolicy,
           CAST(NULL AS BIT) AS PublicAllowed,
           CAST(NULL AS BIT) AS UnverifiedAllowed,
           CAST(NULL AS BIT) AS VerifiedAllowed,
           roleColumn.RoleId,
           roleColumn.RoleCode,
           roleColumn.RoleName,
           roleColumn.RoleScopeCode,
           roleColumn.TenantTypeId,
           roleColumn.TenantTypeCode,
           roleColumn.IsAssignable,
           CONVERT(BIT,CASE WHEN roleColumn.RoleScopeCode=permissionScope.Code
                             AND (permissionScope.Code='PLATFORM' AND roleColumn.TenantTypeId IS NULL
                                  OR permissionScope.Code='TENANT'
                                     AND roleColumn.TenantTypeId IS NOT NULL)
                             AND mapping.RoleId IS NOT NULL THEN 1 ELSE 0 END) AS ConfiguredGrant,
           CONVERT(BIT,CASE WHEN roleColumn.RoleScopeCode=permissionScope.Code
                         AND (permissionScope.Code='PLATFORM' AND roleColumn.TenantTypeId IS NULL
                              OR permissionScope.Code='TENANT'
                                 AND roleColumn.TenantTypeId IS NOT NULL)
                         AND mapping.RoleId IS NOT NULL
                         AND permission.IsActive=1
                         AND readiness.AllowsEffective=1
                         AND permission.Code<>'platform.permissions.manage'
                         AND NOT
                         (
                             roleColumn.TenantTypeCode='PERSONAL'
                             AND tenantType.AllowMultipleMembers=0
                             AND permission.Code IN
                                 ('tenant.members.invite','tenant.members.remove','tenant.roles.assign')
                         )
                         THEN 1 ELSE 0 END) AS EffectiveAllowed,
           CONVERT(BIT,CASE WHEN roleColumn.RoleScopeCode=permissionScope.Code
                             AND (permissionScope.Code='PLATFORM' AND roleColumn.TenantTypeId IS NULL
                                  OR permissionScope.Code='TENANT'
                                     AND roleColumn.TenantTypeId IS NOT NULL)
                             AND permission.IsActive=1
                             AND readiness.AllowsMatrixEdit=1
                             AND NOT
                             (
                                 roleColumn.TenantTypeCode='PERSONAL'
                                 AND tenantType.AllowMultipleMembers=0
                                 AND permission.Code IN
                                     ('tenant.members.invite','tenant.members.remove','tenant.roles.assign')
                             )
                             THEN 1 ELSE 0 END) AS IsEditable,
           CASE
               WHEN roleColumn.RoleScopeCode<>permissionScope.Code
                    OR (permissionScope.Code='PLATFORM' AND roleColumn.TenantTypeId IS NOT NULL)
                    OR (permissionScope.Code='TENANT' AND roleColumn.TenantTypeId IS NULL)
                   THEN N'Permission and role authorization scopes do not match.'
               WHEN roleColumn.TenantTypeCode='PERSONAL'
                    AND tenantType.AllowMultipleMembers=0
                    AND permission.Code IN
                        ('tenant.members.invite','tenant.members.remove','tenant.roles.assign')
                   THEN N'PERSONAL tenants are single-member; membership and role management are disabled.'
               WHEN readiness.AllowsMatrixEdit=0 THEN matrix.RestrictionReason
               ELSE NULL
           END AS RestrictionReason,
           CONVERT(VARBINARY(8),mapping.MatrixRowVersion) AS ConcurrencyVersion
    FROM mst.Permissions permission
    JOIN mst.RoleScopes permissionScope
      ON permissionScope.RoleScopeId=permission.RoleScopeId
     AND permissionScope.IsActive=1
    JOIN mst.PermissionMatrixMetadata matrix
      ON matrix.PermissionId=permission.PermissionId
    JOIN mst.PermissionReadinessStatuses readiness
      ON readiness.Code=matrix.ReadinessCode
     AND readiness.IsActive=1
    CROSS JOIN RoleColumns roleColumn
    LEFT JOIN mst.TenantTypes tenantType
      ON tenantType.TenantTypeId=roleColumn.TenantTypeId
    LEFT JOIN mst.RolePermissions mapping
      ON mapping.RoleId=roleColumn.RoleId
     AND mapping.PermissionId=permission.PermissionId
     AND
     (
         permissionScope.Code='PLATFORM' AND mapping.TenantTypeId IS NULL
         OR permissionScope.Code='TENANT' AND mapping.TenantTypeId=roleColumn.TenantTypeId
     )
    UNION ALL
    SELECT CAST(NULL AS BIGINT),policy.ModuleCode,policy.ResourceCode,policy.ActionCode,
           policy.PolicyCode,policy.Name,policy.Description,CAST('ACCOUNT' AS VARCHAR(50)),
           policy.ReadinessCode,CONVERT(BIT,1),policy.PublicAllowed,
           policy.UnverifiedAllowed,policy.VerifiedAllowed,
           CAST(NULL AS BIGINT),CAST(NULL AS VARCHAR(50)),CAST(NULL AS NVARCHAR(300)),
           CAST(NULL AS VARCHAR(50)),CAST(NULL AS BIGINT),CAST(NULL AS VARCHAR(50)),
           CAST(NULL AS BIT),CAST(NULL AS BIT),CAST(NULL AS BIT),CAST(0 AS BIT),
           policy.RestrictionReason,CAST(NULL AS VARBINARY(8))
    FROM mst.AccountSelfServicePolicies policy
    WHERE policy.IsActive=1
    ORDER BY Module,Resource,PermissionCode,ScopeCode,RoleId,TenantTypeCode;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_SaveRolePermissionBatch
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @ChangeReason NVARCHAR(500),
    @ChangesJson NVARCHAR(MAX),
    @RequestId VARCHAR(100)=NULL,
    @CorrelationId UNIQUEIDENTIFIER=NULL,
    @ApplyChanges BIT=0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ApplyChanges=1 AND @@TRANCOUNT<>0
        THROW 52990, 'The permission batch procedure must own its transaction.', 1;
    EXEC iam.usp_ValidatePlatformPermission
        @ActorUserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @PermissionCode='platform.role_permissions.update';

    IF @ChangeReason IS NULL OR LEN(LTRIM(RTRIM(@ChangeReason)))<10
       OR LEN(@ChangeReason)>500 OR ISJSON(@ChangesJson)<>1
       OR LEFT(LTRIM(@ChangesJson),1)<>'['
        THROW 52990, 'A change reason and valid permission change list are required.', 1;

    DECLARE @Changes TABLE
    (
        ChangeIndex INT NOT NULL PRIMARY KEY,
        PermissionId BIGINT NOT NULL,
        RoleId BIGINT NOT NULL,
        TenantTypeId BIGINT NULL,
        IsGranted BIT NOT NULL,
        ExpectedVersionText NVARCHAR(20) NULL,
        ExpectedVersion VARBINARY(8) NULL
    );
    INSERT @Changes
        (ChangeIndex,PermissionId,RoleId,TenantTypeId,IsGranted,ExpectedVersionText,ExpectedVersion)
    SELECT TRY_CONVERT(INT,[key])+1,PermissionId,RoleId,TenantTypeId,IsGranted,
           ConcurrencyVersion,TRY_CONVERT(VARBINARY(8),ConcurrencyVersion,1)
    FROM OPENJSON(@ChangesJson)
    WITH
    (
        PermissionId BIGINT '$.permissionId',
        RoleId BIGINT '$.roleId',
        TenantTypeId BIGINT '$.tenantTypeId',
        IsGranted BIT '$.isGranted',
        ConcurrencyVersion NVARCHAR(20) '$.concurrencyVersion'
    );

    IF NOT EXISTS(SELECT 1 FROM @Changes)
       OR (SELECT COUNT(*) FROM @Changes)>100
        THROW 52990, 'Permission batches must contain between 1 and 100 changes.', 1;

    IF @ApplyChanges=1
    BEGIN
        BEGIN TRANSACTION;
        DECLARE @LockResult INT;
        EXEC @LockResult=sys.sp_getapplock
            @Resource=N'KLOP/PLATFORM/ROLE_PERMISSION_MATRIX',
            @LockMode='Exclusive',
            @LockOwner='Transaction',
            @LockTimeout=10000;
        IF @LockResult<0
            THROW 52990, 'The permission matrix is busy; retry after reloading.', 1;
    END;

    DECLARE @Issues TABLE
    (
        ChangeIndex INT NOT NULL,
        PermissionCode VARCHAR(150) NULL,
        Code VARCHAR(40) NOT NULL,
        Message NVARCHAR(300) NOT NULL
    );

    INSERT @Issues(ChangeIndex,PermissionCode,Code,Message)
    SELECT change.ChangeIndex,permission.Code,'INVALID_CELL',N'The permission, role, or tenant context does not exist.'
    FROM @Changes change
    LEFT JOIN mst.Permissions permission ON permission.PermissionId=change.PermissionId
    LEFT JOIN mst.Roles role ON role.RoleId=change.RoleId
    LEFT JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
    LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=change.TenantTypeId
    WHERE permission.PermissionId IS NULL OR role.RoleId IS NULL
       OR permission.IsActive=0 OR role.IsActive=0
       OR roleScope.RoleScopeId IS NULL
       OR roleScope.Code NOT IN('PLATFORM','TENANT')
       OR roleScope.Code<>(
            SELECT permissionScope.Code FROM mst.RoleScopes permissionScope
            WHERE permissionScope.RoleScopeId=permission.RoleScopeId)
       OR (roleScope.Code='PLATFORM' AND change.TenantTypeId IS NOT NULL)
       OR (roleScope.Code='TENANT' AND
           (tenantType.TenantTypeId IS NULL OR tenantType.IsActive=0
            OR (role.Code<>'OWNER' AND tenantType.AllowMultipleMembers=0)));

    INSERT @Issues(ChangeIndex,PermissionCode,Code,Message)
    SELECT change.ChangeIndex,permission.Code,'INVALID_CONCURRENCY_VERSION',
           N'The permission cell concurrency version is invalid.'
    FROM @Changes change
    LEFT JOIN mst.Permissions permission ON permission.PermissionId=change.PermissionId
    WHERE change.ExpectedVersionText IS NOT NULL
      AND (change.ExpectedVersion IS NULL OR DATALENGTH(change.ExpectedVersion)<>8);

    INSERT @Issues(ChangeIndex,PermissionCode,Code,Message)
    SELECT change.ChangeIndex,permission.Code,'NOT_EDITABLE',
           COALESCE(matrix.RestrictionReason,N'The permission is not editable in its current readiness state.')
    FROM @Changes change
    JOIN mst.Permissions permission ON permission.PermissionId=change.PermissionId
    JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    JOIN mst.PermissionReadinessStatuses readiness ON readiness.Code=matrix.ReadinessCode
    WHERE readiness.AllowsMatrixEdit=0
      AND NOT EXISTS(SELECT 1 FROM @Issues issue WHERE issue.ChangeIndex=change.ChangeIndex);

    INSERT @Issues(ChangeIndex,PermissionCode,Code,Message)
    SELECT change.ChangeIndex,permission.Code,'TENANT_TYPE_RESTRICTED',
           N'PERSONAL tenants are single-member; membership and role management are disabled.'
    FROM @Changes change
    JOIN mst.Permissions permission ON permission.PermissionId=change.PermissionId
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=permission.RoleScopeId
    JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=change.TenantTypeId
    WHERE roleScope.Code='TENANT'
      AND tenantType.AllowMultipleMembers=0
      AND permission.Code IN('tenant.members.invite','tenant.members.remove','tenant.roles.assign')
      AND NOT EXISTS(SELECT 1 FROM @Issues issue WHERE issue.ChangeIndex=change.ChangeIndex);

    INSERT @Issues(ChangeIndex,PermissionCode,Code,Message)
    SELECT change.ChangeIndex,permission.Code,'SELF_PRIVILEGE_ESCALATION',
           N'You cannot add a permission grant to a role currently assigned to your own account.'
    FROM @Changes change
    JOIN mst.Permissions permission ON permission.PermissionId=change.PermissionId
    JOIN mst.Roles role ON role.RoleId=change.RoleId
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
    WHERE change.IsGranted=1
      AND roleScope.Code IN('PLATFORM','TENANT')
      AND
      (
          roleScope.Code='PLATFORM'
          AND EXISTS
          (
              SELECT 1 FROM iam.PlatformRoleAssignments assignment
              WHERE assignment.UserId=@ActorUserId AND assignment.RoleId=role.RoleId
          )
          OR roleScope.Code='TENANT'
          AND EXISTS
          (
              SELECT 1
              FROM iam.TenantRoleAssignments assignment
              JOIN ten.TenantMemberships membership ON membership.MembershipId=assignment.MembershipId
              JOIN ten.Tenants tenant ON tenant.TenantId=membership.TenantId
              WHERE membership.UserId=@ActorUserId
                AND assignment.RoleId=role.RoleId
                AND tenant.TenantTypeId=change.TenantTypeId
          )
      )
      AND NOT EXISTS
      (
          SELECT 1 FROM mst.RolePermissions mapping
          WHERE mapping.RoleId=change.RoleId
            AND mapping.PermissionId=change.PermissionId
            AND
            (
                roleScope.Code='PLATFORM' AND mapping.TenantTypeId IS NULL
                OR roleScope.Code='TENANT' AND mapping.TenantTypeId=change.TenantTypeId
            )
      )
      AND NOT EXISTS(SELECT 1 FROM @Issues issue WHERE issue.ChangeIndex=change.ChangeIndex);

    INSERT @Issues(ChangeIndex,PermissionCode,Code,Message)
    SELECT change.ChangeIndex,permission.Code,'STALE_CONCURRENCY',
           N'The permission cell changed after it was loaded.'
    FROM @Changes change
    JOIN mst.Permissions permission ON permission.PermissionId=change.PermissionId
    JOIN mst.Roles role ON role.RoleId=change.RoleId
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
    OUTER APPLY
    (
        SELECT TOP(1) mapping.MatrixRowVersion
        FROM mst.RolePermissions mapping
        WHERE mapping.RoleId=change.RoleId
          AND mapping.PermissionId=change.PermissionId
          AND
          (
              roleScope.Code='PLATFORM' AND mapping.TenantTypeId IS NULL
              OR roleScope.Code='TENANT' AND mapping.TenantTypeId=change.TenantTypeId
          )
    ) currentMapping
    WHERE
        (
            (currentMapping.MatrixRowVersion IS NULL AND change.ExpectedVersion IS NOT NULL)
            OR (currentMapping.MatrixRowVersion IS NOT NULL AND
                (change.ExpectedVersion IS NULL OR
                 currentMapping.MatrixRowVersion<>change.ExpectedVersion))
        )
        AND NOT EXISTS(SELECT 1 FROM @Issues issue WHERE issue.ChangeIndex=change.ChangeIndex);

    IF @ApplyChanges=0
    BEGIN
        SELECT ChangeIndex,PermissionCode,Code,Message
        FROM @Issues
        ORDER BY ChangeIndex,Code;
        RETURN;
    END;

    IF EXISTS(SELECT 1 FROM @Issues)
    BEGIN
        DECLARE @FailureCode INT=
            CASE WHEN EXISTS(SELECT 1 FROM @Issues WHERE Code='STALE_CONCURRENCY')
                 THEN 52991 ELSE 52990 END;
        DECLARE @FailureActionId BIGINT=
            (SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='UPDATE' AND IsActive=1);
        DECLARE @FailureResultId BIGINT=
            (SELECT AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='FAILED' AND IsActive=1);
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        IF @FailureActionId IS NOT NULL AND @FailureResultId IS NOT NULL
        BEGIN
            INSERT aud.AuditEvents
                (ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                 ChangeSummaryJson,RequestId,CorrelationId)
            SELECT @ActorUserId,@FailureActionId,@FailureResultId,N'ROLE_PERMISSION_MATRIX',
                   CONCAT(COALESCE(role.Code,N'unknown'),N':',COALESCE(permission.Code,N'unknown')),
                   (SELECT permission.Code AS PermissionCode,role.Code AS RoleCode,
                           roleScope.Code AS ScopeCode,tenantType.Code AS TenantTypeCode,
                           CONVERT(BIT,COALESCE(mapping.RoleId,0)) AS PreviousGrant,
                           change.IsGranted AS NewGrant,LTRIM(RTRIM(@ChangeReason)) AS Reason,
                           N'FAILED' AS Outcome,issue.Code AS FailureCode
                    FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
                   @RequestId,@CorrelationId
            FROM @Issues issue
            JOIN @Changes change ON change.ChangeIndex=issue.ChangeIndex
            LEFT JOIN mst.Permissions permission ON permission.PermissionId=change.PermissionId
            LEFT JOIN mst.Roles role ON role.RoleId=change.RoleId
            LEFT JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
            LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=change.TenantTypeId
            LEFT JOIN mst.RolePermissions mapping
              ON mapping.RoleId=change.RoleId
             AND mapping.PermissionId=change.PermissionId
             AND
             (
                 roleScope.Code='PLATFORM' AND mapping.TenantTypeId IS NULL
                 OR roleScope.Code='TENANT' AND mapping.TenantTypeId=change.TenantTypeId
             );
        END;
        IF @FailureCode=52991
            THROW 52991, 'Permission matrix concurrency check failed.', 1;
        THROW 52990, 'Permission batch was rejected; no changes were applied.', 1;
    END;

    DECLARE @Changed TABLE
    (
        PermissionId BIGINT NOT NULL,
        RoleId BIGINT NOT NULL,
        TenantTypeId BIGINT NULL,
        PreviousGrant BIT NOT NULL,
        NewGrant BIT NOT NULL
    );

    DELETE mapping
    OUTPUT deleted.PermissionId,deleted.RoleId,deleted.TenantTypeId,CONVERT(BIT,1),CONVERT(BIT,0)
        INTO @Changed(PermissionId,RoleId,TenantTypeId,PreviousGrant,NewGrant)
    FROM mst.RolePermissions mapping
    JOIN @Changes change
      ON change.RoleId=mapping.RoleId
     AND change.PermissionId=mapping.PermissionId
     AND change.IsGranted=0
     AND
     (
         change.TenantTypeId IS NULL AND mapping.TenantTypeId IS NULL
         OR change.TenantTypeId=mapping.TenantTypeId
     );

    INSERT mst.RolePermissions(RoleId,PermissionId,TenantTypeId,CreatedAtUtc,CreatedByUserId)
    OUTPUT inserted.PermissionId,inserted.RoleId,inserted.TenantTypeId,CONVERT(BIT,0),CONVERT(BIT,1)
        INTO @Changed(PermissionId,RoleId,TenantTypeId,PreviousGrant,NewGrant)
    SELECT change.RoleId,change.PermissionId,change.TenantTypeId,SYSUTCDATETIME(),@ActorUserId
    FROM @Changes change
    WHERE change.IsGranted=1
      AND NOT EXISTS
      (
          SELECT 1 FROM mst.RolePermissions mapping
          WHERE mapping.RoleId=change.RoleId
            AND mapping.PermissionId=change.PermissionId
            AND
            (
                change.TenantTypeId IS NULL AND mapping.TenantTypeId IS NULL
                OR change.TenantTypeId=mapping.TenantTypeId
            )
      );

    DECLARE @AuditActionId BIGINT=
        (SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='UPDATE' AND IsActive=1);
    DECLARE @AuditResultId BIGINT=
        (SELECT AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1);
    IF EXISTS(SELECT 1 FROM @Changed) AND (@AuditActionId IS NULL OR @AuditResultId IS NULL)
        THROW 52990, 'Permission audit metadata is unavailable; the batch was rolled back.', 1;

    INSERT aud.AuditEvents
        (ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
         ChangeSummaryJson,RequestId,CorrelationId)
    SELECT @ActorUserId,@AuditActionId,@AuditResultId,N'ROLE_PERMISSION_MATRIX',
           CONCAT(role.Code,N':',COALESCE(tenantType.Code,N'PLATFORM'),N':',permission.Code),
           (SELECT permission.Code AS PermissionCode,role.Code AS RoleCode,
                   roleScope.Code AS ScopeCode,tenantType.Code AS TenantTypeCode,
                   changed.PreviousGrant,changed.NewGrant,
                   LTRIM(RTRIM(@ChangeReason)) AS Reason,N'SUCCESS' AS Outcome
            FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
           @RequestId,@CorrelationId
    FROM @Changed changed
    JOIN mst.Permissions permission ON permission.PermissionId=changed.PermissionId
    JOIN mst.Roles role ON role.RoleId=changed.RoleId
    JOIN mst.RoleScopes roleScope ON roleScope.RoleScopeId=role.RoleScopeId
    LEFT JOIN mst.TenantTypes tenantType ON tenantType.TenantTypeId=changed.TenantTypeId;

    DECLARE @SavedAtUtc DATETIME2(3)=SYSUTCDATETIME();
    DECLARE @ChangedCount INT=(SELECT COUNT(*) FROM @Changed);
    COMMIT TRANSACTION;
    SELECT @ChangedCount AS ChangedCount,@SavedAtUtc AS SavedAtUtc;
END;
GO

CREATE OR ALTER PROCEDURE iam.usp_GetRolePermissionChangeHistory
    @ActorUserId BIGINT,
    @PublicSessionId UNIQUEIDENTIFIER,
    @PageNumber INT=1,
    @PageSize INT=20
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber IS NULL OR @PageNumber<1 OR @PageNumber>100000
       OR @PageSize IS NULL OR @PageSize<1 OR @PageSize>100
        THROW 52996, 'The permission history page request is invalid.', 1;

    EXEC iam.usp_ValidatePlatformPermission
        @ActorUserId=@ActorUserId,
        @PublicSessionId=@PublicSessionId,
        @PermissionCode='platform.role_permissions.read';

    SELECT audit.AuditEventId,
           JSON_VALUE(audit.ChangeSummaryJson,'$.PermissionCode') AS PermissionCode,
           JSON_VALUE(audit.ChangeSummaryJson,'$.RoleCode') AS RoleCode,
           JSON_VALUE(audit.ChangeSummaryJson,'$.ScopeCode') AS ScopeCode,
           JSON_VALUE(audit.ChangeSummaryJson,'$.TenantTypeCode') AS TenantTypeCode,
           TRY_CONVERT(BIT,JSON_VALUE(audit.ChangeSummaryJson,'$.PreviousGrant')) AS PreviousGrant,
           TRY_CONVERT(BIT,JSON_VALUE(audit.ChangeSummaryJson,'$.NewGrant')) AS NewGrant,
           JSON_VALUE(audit.ChangeSummaryJson,'$.Reason') AS ChangeReason,
           actor.DisplayName AS ActorDisplayName,
           audit.OccurredAtUtc,
           CONVERT(VARCHAR(36),audit.CorrelationId) AS CorrelationId,
           result.Code AS Outcome
    FROM aud.AuditEvents audit
    JOIN mst.AuditResultTypes result ON result.AuditResultTypeId=audit.AuditResultTypeId
    LEFT JOIN iam.Users actor ON actor.UserId=audit.ActorUserId
    WHERE audit.TargetType='ROLE_PERMISSION_MATRIX'
    ORDER BY audit.OccurredAtUtc DESC,audit.AuditEventId DESC
    OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

COMMIT TRANSACTION;
GO

SELECT N'v1.10 tenant and unified RBAC matrix routines installed' AS DeploymentStatus,
       N'Validate SQL grants and restart the API before exercising matrix or tenant authorization.' AS NextStep;
GO
