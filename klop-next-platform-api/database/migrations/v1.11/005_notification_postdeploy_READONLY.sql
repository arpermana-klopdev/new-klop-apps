-- Read-only post-deployment checks for the owner-reviewed v1.11 proposal.
SET NOCOUNT ON;

SELECT N'ntf.NotificationChannels' AS ObjectName,
       CASE WHEN OBJECT_ID(N'ntf.NotificationChannels',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
UNION ALL SELECT N'ntf.NotificationChannelStatuses',
       CASE WHEN OBJECT_ID(N'ntf.NotificationChannelStatuses',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationTemplateTypes',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplateTypes',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationTemplateStatuses',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplateStatuses',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationVariableDefinitions',
       CASE WHEN OBJECT_ID(N'ntf.NotificationVariableDefinitions',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationTemplates',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplates',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationTemplateVersions',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplateVersions',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationTemplateVersionVariables',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplateVersionVariables',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationTemplateApprovals',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplateApprovals',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationDeliveryOutcomes',
       CASE WHEN OBJECT_ID(N'ntf.NotificationDeliveryOutcomes',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationErrorCategories',
       CASE WHEN OBJECT_ID(N'ntf.NotificationErrorCategories',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationDeliveries',
       CASE WHEN OBJECT_ID(N'ntf.NotificationDeliveries',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationDeliveryAttempts',
       CASE WHEN OBJECT_ID(N'ntf.NotificationDeliveryAttempts',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.trg_NotificationTemplateVersions_ActiveImmutable',
       CASE WHEN OBJECT_ID(N'ntf.trg_NotificationTemplateVersions_ActiveImmutable',N'TR') IS NULL
            THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.trg_NotificationTemplateVersions_ActiveDelete',
       CASE WHEN OBJECT_ID(N'ntf.trg_NotificationTemplateVersions_ActiveDelete',N'TR') IS NULL
            THEN N'MISSING' ELSE N'PRESENT' END;

SELECT Dependency.Name,
       CASE WHEN Dependency.ObjectId IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
FROM
(
    VALUES
        (N'mst.PermissionMatrixMetadata',OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U')),
        (N'mst.PermissionReadinessStatuses',OBJECT_ID(N'mst.PermissionReadinessStatuses',N'U')),
        (N'iam.usp_ValidateSessionAccess',OBJECT_ID(N'iam.usp_ValidateSessionAccess',N'P')),
        (N'iam.usp_ValidatePlatformPermission',OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P')),
        (N'iam.usp_GetPlatformPermissions',OBJECT_ID(N'iam.usp_GetPlatformPermissions',N'P')),
        (N'ntf.usp_ListTemplates',OBJECT_ID(N'ntf.usp_ListTemplates',N'P')),
        (N'ntf.usp_GetTemplate',OBJECT_ID(N'ntf.usp_GetTemplate',N'P')),
        (N'ntf.usp_GetTemplateVersionForPreview',OBJECT_ID(N'ntf.usp_GetTemplateVersionForPreview',N'P')),
        (N'ntf.usp_ListChannels',OBJECT_ID(N'ntf.usp_ListChannels',N'P')),
        (N'ntf.usp_ListDeliveryHistory',OBJECT_ID(N'ntf.usp_ListDeliveryHistory',N'P')),
        (N'ntf.usp_CreateTemplateDraft',OBJECT_ID(N'ntf.usp_CreateTemplateDraft',N'P')),
        (N'ntf.usp_UpdateTemplateDraft',OBJECT_ID(N'ntf.usp_UpdateTemplateDraft',N'P')),
        (N'ntf.usp_TransitionTemplateVersion',OBJECT_ID(N'ntf.usp_TransitionTemplateVersion',N'P')),
        (N'ntf.usp_GetActiveVerificationTemplate',OBJECT_ID(N'ntf.usp_GetActiveVerificationTemplate',N'P')),
        (N'ntf.usp_RecordDeliveryAttempt',OBJECT_ID(N'ntf.usp_RecordDeliveryAttempt',N'P'))
) Dependency(Name,ObjectId)
ORDER BY Dependency.Name;

IF OBJECT_ID(N'mst.Permissions',N'U') IS NOT NULL
   AND OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NOT NULL
   AND OBJECT_ID(N'mst.RolePermissions',N'U') IS NOT NULL
BEGIN
    ;WITH Expected(Code) AS
    (
        SELECT Code FROM (VALUES
            ('platform.notifications.read'),
            ('platform.notifications.draft.create'),
            ('platform.notifications.draft.edit'),
            ('platform.notifications.draft.preview'),
            ('platform.notifications.submit'),
            ('platform.notifications.approve'),
            ('platform.notifications.activate'),
            ('platform.notifications.archive'),
            ('platform.notifications.history'),
            ('platform.notifications.settings.read')
        ) valuesTable(Code)
    )
    SELECT expected.Code,scope.Code AS ScopeCode,matrix.ReadinessCode,
           CASE WHEN permission.PermissionId IS NULL THEN N'MISSING DEFINITION'
                WHEN matrix.PermissionId IS NULL THEN N'MISSING MATRIX METADATA'
                WHEN matrix.ReadinessCode<>'HOLD' THEN N'NOT HOLD - OWNER REVIEW REQUIRED'
                ELSE N'HOLD' END AS AuthorizationReadiness,
           CASE WHEN permission.PermissionId IS NULL THEN N'MISSING DEFINITION'
                WHEN mapping.PermissionId IS NULL THEN N'UNASSIGNED'
                ELSE N'ASSIGNED - OWNER REVIEW REQUIRED' END AS RoleMapping
    FROM Expected expected
    LEFT JOIN mst.Permissions permission ON permission.Code=expected.Code
    LEFT JOIN mst.RoleScopes scope ON scope.RoleScopeId=permission.RoleScopeId
    LEFT JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    LEFT JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
    ORDER BY expected.Code;
END;

IF OBJECT_ID(N'ntf.NotificationChannels',N'U') IS NOT NULL
    SELECT ChannelCode,IsEnabled,StatusCode FROM ntf.NotificationChannels ORDER BY ChannelCode;
IF OBJECT_ID(N'ntf.NotificationTemplates',N'U') IS NOT NULL
    SELECT TemplateCode,LocaleCode,COUNT_BIG(*) AS VersionCount,
           SUM(CASE WHEN StatusCode='ACTIVE' THEN 1 ELSE 0 END) AS ActiveVersionCount
    FROM ntf.NotificationTemplates t
    LEFT JOIN ntf.NotificationTemplateVersions v ON v.TemplateId=t.TemplateId
    GROUP BY TemplateCode,LocaleCode
    ORDER BY TemplateCode,LocaleCode;

IF OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NOT NULL
    SELECT expected.ConfigurationKey,
           CASE WHEN configuration.ConfigurationId IS NULL THEN N'ABSENT - runtime default is disabled'
                WHEN configuration.ValueType='BOOLEAN' AND configuration.StorageType='PLAIN'
                     AND configuration.ConfigurationValue=N'false' THEN N'PRESENT - disabled'
                WHEN configuration.ValueType='BOOLEAN' AND configuration.StorageType='PLAIN'
                     AND configuration.ConfigurationValue=N'true' THEN N'PRESENT - enabled by owner decision'
                ELSE N'INVALID - startup must fail closed' END AS GateStatus
    FROM (VALUES
        (N'notification.email_verification_templates.enabled'),
        (N'notification.email_verification_delivery_audit.enabled')
    ) expected(ConfigurationKey)
    LEFT JOIN cfg.SystemConfigurations configuration
      ON configuration.ConfigurationKey=expected.ConfigurationKey AND configuration.IsActive=1
    ORDER BY expected.ConfigurationKey;
GO
