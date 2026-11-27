-- KLOP DEVELOPMENT - READ-ONLY VALIDATION
-- Based on original v1.1, v1.2 and v1.2.1 artifacts.
-- READ-ONLY: no INSERT / UPDATE / DELETE / CREATE / ALTER / DROP on user objects, no stored procedure invocation.
-- Run via SSMS or sqlcmd, against the intended DEVELOPMENT database, with metadata/read privileges.
-- IMPORTANT: output is evidence only when executed and saved from the actual SQL Server.
SET NOCOUNT ON;
GO
-- Metadata-only review. Does NOT prove runtime effective permissions.
SELECT dp.name AS PrincipalName, dp.type_desc AS PrincipalType,
       CASE WHEN dp.principal_id IS NULL THEN N'REVIEW_NOT_CREATED' ELSE N'PRESENT' END AS ReviewResult
FROM (VALUES(N'klop_app_runtime')) AS Expected(name)
LEFT JOIN sys.database_principals dp ON dp.name=Expected.name;
GO
-- Explicit runtime principal privileges. Check other role memberships, ownership and effective privilege separately.
SELECT U.name AS PrincipalName, P.state_desc, P.permission_name,
       COALESCE(OBJECT_SCHEMA_NAME(P.major_id)+N'.'+OBJECT_NAME(P.major_id),SCHEMA_NAME(P.major_id),N'DATABASE') AS Securable
FROM sys.database_permissions P
JOIN sys.database_principals U ON U.principal_id=P.grantee_principal_id
WHERE U.name=N'klop_app_runtime'
ORDER BY P.permission_name,P.state_desc,Securable;
GO
-- Show DB role memberships of runtime role and any database principals directly mapped to it.
SELECT R.name AS RoleName, M.name AS MemberName
FROM sys.database_role_members RM
JOIN sys.database_principals R ON R.principal_id=RM.role_principal_id
JOIN sys.database_principals M ON M.principal_id=RM.member_principal_id
WHERE M.name=N'klop_app_runtime' OR R.name=N'klop_app_runtime'
ORDER BY RoleName,MemberName;
GO
-- An empty permission listing does not prove security: inherited/server permissions are not assessed.
