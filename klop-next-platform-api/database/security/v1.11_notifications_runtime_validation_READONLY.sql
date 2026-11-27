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

SELECT COUNT(*) AS NotificationRoleAssignments
FROM mst.RolePermissions mapping
JOIN mst.Permissions permission ON permission.PermissionId=mapping.PermissionId
WHERE permission.Code LIKE 'platform.notifications.%';
GO
