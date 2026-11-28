-- Read-only preflight proposal for Notification Management v1.11.
-- Run only against an owner-selected environment. This script makes no changes.
SET NOCOUNT ON;

SELECT @@SERVERNAME AS ServerName, DB_NAME() AS DatabaseName,
       N'READ ONLY - no v1.11 migration, seed, permission mapping, grant, or SMTP value is applied' AS Scope;

SELECT prerequisite.Name,
       CASE WHEN prerequisite.ObjectId IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
FROM
(
    VALUES
        (N'cfg.SystemConfigurations', OBJECT_ID(N'cfg.SystemConfigurations', N'U')),
        (N'aud.AuditEvents', OBJECT_ID(N'aud.AuditEvents', N'U')),
        (N'mst.AuditActionTypes', OBJECT_ID(N'mst.AuditActionTypes', N'U')),
        (N'mst.AuditResultTypes', OBJECT_ID(N'mst.AuditResultTypes', N'U')),
        (N'iam.Users', OBJECT_ID(N'iam.Users', N'U')),
        (N'mst.Permissions', OBJECT_ID(N'mst.Permissions', N'U')),
        (N'mst.RoleScopes', OBJECT_ID(N'mst.RoleScopes', N'U')),
        (N'mst.PermissionMatrixMetadata', OBJECT_ID(N'mst.PermissionMatrixMetadata', N'U')),
        (N'mst.PermissionReadinessStatuses', OBJECT_ID(N'mst.PermissionReadinessStatuses', N'U')),
        (N'mst.RolePermissions', OBJECT_ID(N'mst.RolePermissions', N'U')),
        (N'iam.PlatformRoleAssignments', OBJECT_ID(N'iam.PlatformRoleAssignments', N'U')),
        (N'iam.usp_ValidateSessionAccess', OBJECT_ID(N'iam.usp_ValidateSessionAccess', N'P')),
        (N'iam.usp_ValidatePlatformPermission', OBJECT_ID(N'iam.usp_ValidatePlatformPermission', N'P')),
        (N'iam.usp_GetPlatformPermissions', OBJECT_ID(N'iam.usp_GetPlatformPermissions', N'P')),
        (N'cfg.usp_Configuration_GetByKey', OBJECT_ID(N'cfg.usp_Configuration_GetByKey', N'P'))
) prerequisite(Name, ObjectId)
ORDER BY prerequisite.Name;

IF OBJECT_ID(N'mst.Permissions',N'U') IS NOT NULL
   AND OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NOT NULL
   AND OBJECT_ID(N'mst.RolePermissions',N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        SELECT expected.Code,
               CASE WHEN permission.PermissionId IS NULL THEN N''MISSING DEFINITION''
                    WHEN permission.RoleScopeId<>scope.RoleScopeId THEN N''WRONG SCOPE''
                    WHEN matrix.PermissionId IS NULL THEN N''MISSING MATRIX METADATA''
                    ELSE matrix.ReadinessCode END AS MatrixStatus,
               CASE WHEN mapping.PermissionId IS NULL THEN N''UNASSIGNED''
                    ELSE N''ASSIGNED - OWNER REVIEW REQUIRED'' END AS RoleMapping
        FROM (VALUES
            (''platform.notifications.read''),
            (''platform.notifications.draft.create''),
            (''platform.notifications.draft.edit''),
            (''platform.notifications.draft.preview''),
            (''platform.notifications.submit''),
            (''platform.notifications.approve''),
            (''platform.notifications.activate''),
            (''platform.notifications.archive''),
            (''platform.notifications.history''),
            (''platform.notifications.settings.read'')
        ) expected(Code)
        CROSS JOIN mst.RoleScopes scope
        LEFT JOIN mst.Permissions permission
          ON permission.Code=expected.Code AND permission.RoleScopeId=scope.RoleScopeId
        LEFT JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
        LEFT JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
        WHERE scope.Code=''PLATFORM'' AND scope.IsActive=1
        ORDER BY expected.Code;';
END;

SELECT Proposed.Name,
       CASE WHEN Proposed.ObjectId IS NULL THEN N'NOT INSTALLED' ELSE N'PRESENT - RECONCILE BEFORE APPLY' END AS Status
FROM
(
    VALUES
        (N'ntf.NotificationChannelStatuses', OBJECT_ID(N'ntf.NotificationChannelStatuses',N'U')),
        (N'ntf.NotificationChannels', OBJECT_ID(N'ntf.NotificationChannels',N'U')),
        (N'ntf.NotificationTemplateTypes', OBJECT_ID(N'ntf.NotificationTemplateTypes',N'U')),
        (N'ntf.NotificationTemplateStatuses', OBJECT_ID(N'ntf.NotificationTemplateStatuses',N'U')),
        (N'ntf.NotificationVariableDefinitions', OBJECT_ID(N'ntf.NotificationVariableDefinitions',N'U')),
        (N'ntf.NotificationTemplates', OBJECT_ID(N'ntf.NotificationTemplates',N'U')),
        (N'ntf.NotificationTemplateVersions', OBJECT_ID(N'ntf.NotificationTemplateVersions',N'U')),
        (N'ntf.NotificationTemplateVersionVariables', OBJECT_ID(N'ntf.NotificationTemplateVersionVariables',N'U')),
        (N'ntf.NotificationTemplateApprovals', OBJECT_ID(N'ntf.NotificationTemplateApprovals',N'U')),
        (N'ntf.NotificationDeliveryOutcomes', OBJECT_ID(N'ntf.NotificationDeliveryOutcomes',N'U')),
        (N'ntf.NotificationErrorCategories', OBJECT_ID(N'ntf.NotificationErrorCategories',N'U')),
        (N'ntf.NotificationDeliveries', OBJECT_ID(N'ntf.NotificationDeliveries',N'U')),
        (N'ntf.NotificationDeliveryAttempts', OBJECT_ID(N'ntf.NotificationDeliveryAttempts',N'U'))
) Proposed(Name,ObjectId)
ORDER BY Proposed.Name;

SELECT N'ntf' AS ProposedSchema,
       CASE WHEN SCHEMA_ID(N'ntf') IS NULL THEN N'AVAILABLE' ELSE N'EXISTS - MANUAL RECONCILIATION REQUIRED' END AS Status;

IF OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NOT NULL
    SELECT Expected.ConfigurationKey,
           CASE WHEN Existing.ConfigurationId IS NULL THEN N'ABSENT - rollout remains disabled'
                WHEN Existing.ValueType <> 'BOOLEAN' OR Existing.StorageType <> 'PLAIN'
                    THEN N'PRESENT WITH INVALID TYPE - startup must fail closed'
                WHEN Existing.ConfigurationValue = N'true' THEN N'PRESENT - rollout enabled; owner approval required'
                WHEN Existing.ConfigurationValue = N'false' THEN N'PRESENT - rollout disabled'
                ELSE N'PRESENT WITH INVALID VALUE - startup must fail closed' END AS Status
    FROM (VALUES
        (N'notification.email_verification_templates.enabled'),
        (N'notification.email_verification_delivery_audit.enabled')
    ) Expected(ConfigurationKey)
    LEFT JOIN cfg.SystemConfigurations Existing
      ON Existing.ConfigurationKey = Expected.ConfigurationKey AND Existing.IsActive = 1;
GO
