-- Read-only prerequisite and collision check for the proposed v1.12 configuration workflow.
-- Does not inspect configuration values, configuration keys, users, roles, or secret references.
SET NOCOUNT ON;

SELECT @@SERVERNAME AS ServerName, DB_NAME() AS DatabaseName,
       N'READ ONLY - no schema, seed, authorization, value, grant, or SMTP change' AS Scope;

SELECT prerequisite.Name,
       CASE WHEN prerequisite.ObjectId IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
FROM
(
    VALUES
        (N'cfg.SystemConfigurations', OBJECT_ID(N'cfg.SystemConfigurations', N'U')),
        (N'aud.AuditEvents', OBJECT_ID(N'aud.AuditEvents', N'U')),
        (N'mst.AuditActionTypes', OBJECT_ID(N'mst.AuditActionTypes', N'U')),
        (N'mst.AuditResultTypes', OBJECT_ID(N'mst.AuditResultTypes', N'U')),
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

SELECT Proposed.Name,
       CASE WHEN Proposed.ObjectId IS NULL THEN N'AVAILABLE'
            ELSE N'EXISTS - STOP AND RECONCILE; DO NOT OVERWRITE' END AS Status
FROM
(
    VALUES
        (N'cfg.ConfigurationManagementPolicies', OBJECT_ID(N'cfg.ConfigurationManagementPolicies', N'U')),
        (N'cfg.ConfigurationChangeRequests', OBJECT_ID(N'cfg.ConfigurationChangeRequests', N'U')),
        (N'cfg.ConfigurationChangeDecisions', OBJECT_ID(N'cfg.ConfigurationChangeDecisions', N'U')),
        (N'cfg.ConfigurationAppliedHistory', OBJECT_ID(N'cfg.ConfigurationAppliedHistory', N'U')),
        (N'cfg.usp_ConfigurationManagement_ListCatalog', OBJECT_ID(N'cfg.usp_ConfigurationManagement_ListCatalog', N'P')),
        (N'cfg.usp_ConfigurationManagement_ListRequests', OBJECT_ID(N'cfg.usp_ConfigurationManagement_ListRequests', N'P')),
        (N'cfg.usp_ConfigurationManagement_ListHistory', OBJECT_ID(N'cfg.usp_ConfigurationManagement_ListHistory', N'P')),
        (N'cfg.usp_ConfigurationManagement_CreateDraft', OBJECT_ID(N'cfg.usp_ConfigurationManagement_CreateDraft', N'P')),
        (N'cfg.usp_ConfigurationManagement_UpdateDraft', OBJECT_ID(N'cfg.usp_ConfigurationManagement_UpdateDraft', N'P')),
        (N'cfg.usp_ConfigurationManagement_Transition', OBJECT_ID(N'cfg.usp_ConfigurationManagement_Transition', N'P')),
        (N'cfg.usp_ConfigurationManagement_Apply', OBJECT_ID(N'cfg.usp_ConfigurationManagement_Apply', N'P'))
) Proposed(Name,ObjectId)
ORDER BY Proposed.Name;

IF OBJECT_ID(N'cfg.SystemConfigurations', N'U') IS NOT NULL
BEGIN
    SELECT RequiredColumn.Name,
           CASE WHEN columnInfo.name IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
    FROM (VALUES
        (N'ConfigurationKey'),(N'ConfigurationValue'),(N'ValueType'),(N'Category'),
        (N'StorageType'),(N'MinNumericValue'),(N'MaxNumericValue'),(N'RequiresApproval'),
        (N'VersionNumber'),(N'IsActive'),(N'IsEditable'),(N'IsSensitive'),
        (N'RequiresRestart'),(N'CreatedAtUtc'),(N'UpdatedAtUtc'),(N'RowVersion')
    ) RequiredColumn(Name)
    LEFT JOIN sys.columns columnInfo
      ON columnInfo.object_id=OBJECT_ID(N'cfg.SystemConfigurations')
     AND columnInfo.name=RequiredColumn.Name
    ORDER BY RequiredColumn.Name;
END;

SELECT N'Execution remains HOLD: owner-reviewed Development target and separate approval are required.' AS NextStep;
GO
