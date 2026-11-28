-- Read-only postdeploy checks. Never selects ConfigurationValue or any unclassified key name.
SET NOCOUNT ON;

SELECT Proposed.Name,
       CASE WHEN Proposed.ObjectId IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
FROM
(
    VALUES
        (N'cfg.ConfigurationManagementPolicies',OBJECT_ID(N'cfg.ConfigurationManagementPolicies',N'U')),
        (N'cfg.ConfigurationChangeRequests',OBJECT_ID(N'cfg.ConfigurationChangeRequests',N'U')),
        (N'cfg.ConfigurationChangeDecisions',OBJECT_ID(N'cfg.ConfigurationChangeDecisions',N'U')),
        (N'cfg.ConfigurationAppliedHistory',OBJECT_ID(N'cfg.ConfigurationAppliedHistory',N'U')),
        (N'cfg.usp_ConfigurationManagement_ListCatalog',OBJECT_ID(N'cfg.usp_ConfigurationManagement_ListCatalog',N'P')),
        (N'cfg.usp_ConfigurationManagement_ListRequests',OBJECT_ID(N'cfg.usp_ConfigurationManagement_ListRequests',N'P')),
        (N'cfg.usp_ConfigurationManagement_ListHistory',OBJECT_ID(N'cfg.usp_ConfigurationManagement_ListHistory',N'P')),
        (N'cfg.usp_ConfigurationManagement_CreateDraft',OBJECT_ID(N'cfg.usp_ConfigurationManagement_CreateDraft',N'P')),
        (N'cfg.usp_ConfigurationManagement_UpdateDraft',OBJECT_ID(N'cfg.usp_ConfigurationManagement_UpdateDraft',N'P')),
        (N'cfg.usp_ConfigurationManagement_Transition',OBJECT_ID(N'cfg.usp_ConfigurationManagement_Transition',N'P')),
        (N'cfg.usp_ConfigurationManagement_Apply',OBJECT_ID(N'cfg.usp_ConfigurationManagement_Apply',N'P')),
        (N'iam.usp_ValidatePlatformPermission',OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P')),
        (N'iam.usp_GetPlatformPermissions',OBJECT_ID(N'iam.usp_GetPlatformPermissions',N'P'))
) Proposed(Name,ObjectId)
ORDER BY Proposed.Name;

IF OBJECT_ID(N'cfg.ConfigurationManagementPolicies',N'U') IS NOT NULL
BEGIN
    DECLARE @ApprovedCatalog TABLE(ConfigurationKey VARCHAR(150) PRIMARY KEY);
    INSERT @ApprovedCatalog VALUES
      ('auth.access_token_minutes'),
      ('auth.refresh_token_days'),
      ('auth.email_verification_hours'),
      ('security.max_login_attempts'),
      ('security.password.min_length'),
      ('security.auth_requests_per_minute'),
      ('registration.personal.enabled'),
      ('registration.organization.enabled'),
      ('registration.legal_consent_enforcement'),
      ('notification.email_verification_templates.enabled'),
      ('notification.email_verification_delivery_audit.enabled'),
      ('database.command_timeout_seconds');

    SELECT approved.ConfigurationKey,
           CASE WHEN policy.ConfigurationKey IS NULL THEN N'POLICY MISSING'
                WHEN config.ConfigurationId IS NULL THEN N'CONFIGURATION MISSING'
                WHEN config.IsActive=0 THEN N'INACTIVE'
                WHEN config.ValueType<>policy.ValueType OR config.StorageType<>policy.StorageType
                    THEN N'INVALID'
                ELSE N'PRESENCE ONLY - value not selected' END AS MetadataStatus,
           policy.ManagementStatus,policy.IsManageable,policy.RequiresApproval,policy.RequiresRestart,
           policy.MinimumInteger,policy.MaximumInteger,
           config.VersionNumber,config.CreatedAtUtc,config.UpdatedAtUtc
    FROM @ApprovedCatalog approved
    LEFT JOIN cfg.ConfigurationManagementPolicies policy
      ON policy.ConfigurationKey=approved.ConfigurationKey
    LEFT JOIN cfg.SystemConfigurations config
      ON config.ConfigurationKey=approved.ConfigurationKey
    ORDER BY approved.ConfigurationKey;

    SELECT (SELECT COUNT_BIG(*) FROM cfg.ConfigurationManagementPolicies) AS PolicyRowCount,
           (SELECT COUNT_BIG(*) FROM cfg.ConfigurationManagementPolicies policy
             WHERE NOT EXISTS(SELECT 1 FROM @ApprovedCatalog approved
                              WHERE approved.ConfigurationKey=policy.ConfigurationKey)) AS UnapprovedPolicyRowCount,
           (SELECT COUNT_BIG(*) FROM cfg.SystemConfigurations config
             WHERE NOT EXISTS(SELECT 1 FROM @ApprovedCatalog approved
                              WHERE approved.ConfigurationKey=config.ConfigurationKey)) AS UnclassifiedConfigurationCount;
END;

IF OBJECT_ID(N'cfg.ConfigurationChangeRequests',N'U') IS NOT NULL
    SELECT StatusCode,COUNT_BIG(*) AS RequestCount
    FROM cfg.ConfigurationChangeRequests
    GROUP BY StatusCode ORDER BY StatusCode;

IF OBJECT_ID(N'mst.Permissions',N'U') IS NOT NULL
   AND OBJECT_ID(N'mst.PermissionMatrixMetadata',N'U') IS NOT NULL
   AND OBJECT_ID(N'mst.RolePermissions',N'U') IS NOT NULL
BEGIN
    SELECT expected.Code,matrix.ReadinessCode,
           CASE WHEN permission.PermissionId IS NULL THEN N'MISSING DEFINITION'
                WHEN matrix.PermissionId IS NULL THEN N'MISSING MATRIX METADATA'
                WHEN matrix.ReadinessCode<>'HOLD' THEN N'OWNER REVIEW REQUIRED'
                ELSE N'HOLD' END AS AuthorizationReadiness,
           CASE WHEN mapping.PermissionId IS NULL THEN N'UNASSIGNED'
                ELSE N'ASSIGNED - OWNER REVIEW REQUIRED' END AS RoleMapping
    FROM (VALUES
      ('platform.configurations.read'),
      ('platform.configurations.request.create'),
      ('platform.configurations.request.edit'),
      ('platform.configurations.request.submit'),
      ('platform.configurations.request.cancel'),
      ('platform.configurations.approve'),
      ('platform.configurations.apply'),
      ('platform.configurations.history')
    ) expected(Code)
    LEFT JOIN mst.Permissions permission ON permission.Code=expected.Code
    LEFT JOIN mst.PermissionMatrixMetadata matrix ON matrix.PermissionId=permission.PermissionId
    LEFT JOIN mst.RolePermissions mapping ON mapping.PermissionId=permission.PermissionId
    ORDER BY expected.Code;
END;

SELECT N'Metadata-only evidence; no SQL Server execution, live UAT, effective grant, readiness activation, or production-ready claim.' AS Scope;
GO
