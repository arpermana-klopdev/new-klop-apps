-- Read-only exact-grant verification. Does not add users, roles, memberships, or grants.
SET NOCOUNT ON;

SELECT role.name AS PrincipalName,
       CASE WHEN role.principal_id IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
FROM (VALUES(N'klop_app_runtime')) expected(name)
LEFT JOIN sys.database_principals role ON role.name=expected.name;

SELECT object_schema_name(permission.major_id) AS SchemaName,
       object_name(permission.major_id) AS ProcedureName,
       permission.permission_name AS PermissionName,
       permission.state_desc AS PermissionState
FROM sys.database_permissions permission
JOIN sys.database_principals grantee ON grantee.principal_id=permission.grantee_principal_id
WHERE grantee.name=N'klop_app_runtime'
  AND object_schema_name(permission.major_id)=N'ntf'
ORDER BY object_name(permission.major_id);

DECLARE @RequiredProcedures TABLE(ProcedureName SYSNAME PRIMARY KEY);
INSERT @RequiredProcedures(ProcedureName) VALUES
(N'usp_ListTemplates'),(N'usp_GetTemplate'),(N'usp_GetTemplateVersionForPreview'),
(N'usp_ListChannels'),(N'usp_ListDeliveryHistory'),(N'usp_CreateTemplateDraft'),
(N'usp_UpdateTemplateDraft'),(N'usp_TransitionTemplateVersion'),
(N'usp_GetActiveVerificationTemplate'),(N'usp_RecordDeliveryAttempt');
SELECT required.ProcedureName,
       CASE WHEN procedureInfo.object_id IS NULL THEN N'MISSING PROCEDURE'
            WHEN permission.state IN('G','W') THEN permission.state_desc
            ELSE N'MISSING EXECUTE GRANT' END AS GrantStatus
FROM @RequiredProcedures required
LEFT JOIN sys.procedures procedureInfo
  ON procedureInfo.schema_id=SCHEMA_ID(N'ntf') AND procedureInfo.name=required.ProcedureName
LEFT JOIN sys.database_permissions permission
  ON permission.class=1 AND permission.major_id=procedureInfo.object_id
 AND permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
 AND permission.permission_name=N'EXECUTE'
ORDER BY required.ProcedureName;

SELECT COUNT(*) AS NotificationRoleAssignments
FROM mst.RolePermissions mapping
JOIN mst.Permissions permission ON permission.PermissionId=mapping.PermissionId
WHERE permission.Code LIKE 'platform.notifications.%';
GO
