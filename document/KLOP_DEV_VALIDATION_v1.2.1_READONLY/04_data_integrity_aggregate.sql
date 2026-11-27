-- KLOP DEVELOPMENT - READ-ONLY VALIDATION
-- Based on original v1.1, v1.2 and v1.2.1 artifacts.
-- READ-ONLY: no INSERT / UPDATE / DELETE / CREATE / ALTER / DROP on user objects, no stored procedure invocation.
-- Run via SSMS or sqlcmd, against the intended DEVELOPMENT database, with metadata/read privileges.
-- IMPORTANT: output is evidence only when executed and saved from the actual SQL Server.
SET NOCOUNT ON;
GO
-- Optional aggregate-only DATA checks; do not show PII or business row details.
-- Requires SELECT on iam/ten/mst. When least-privileged runtime principal does not have SELECT,
-- run using a separate read-only audit principal, never grant extra rights to runtime to accommodate checks.
SELECT N'RolePermissions scope consistency' AS CheckName,
       COUNT_BIG(*) AS ViolationCount,
       CASE WHEN COUNT_BIG(*)=0 THEN N'PASS' ELSE N'FAIL' END AS CheckResult
FROM mst.RolePermissions RP
JOIN mst.Roles R ON R.RoleId=RP.RoleId
JOIN mst.Permissions P ON P.PermissionId=RP.PermissionId
WHERE R.RoleScopeId<>P.RoleScopeId;
GO
SELECT N'Tenant roles only TENANT scope' AS CheckName,
       COUNT_BIG(*) AS ViolationCount,
       CASE WHEN COUNT_BIG(*)=0 THEN N'PASS' ELSE N'FAIL' END AS CheckResult
FROM iam.TenantRoleAssignments RA
JOIN mst.Roles R ON RA.RoleId=R.RoleId
JOIN mst.RoleScopes S ON S.RoleScopeId=R.RoleScopeId
WHERE S.Code<>N'TENANT';
GO
SELECT N'Platform roles only PLATFORM scope' AS CheckName,
       COUNT_BIG(*) AS ViolationCount,
       CASE WHEN COUNT_BIG(*)=0 THEN N'PASS' ELSE N'FAIL' END AS CheckResult
FROM iam.PlatformRoleAssignments RA
JOIN mst.Roles R ON RA.RoleId=R.RoleId
JOIN mst.RoleScopes S ON S.RoleScopeId=R.RoleScopeId
WHERE S.Code<>N'PLATFORM';
GO
SELECT N'Invited membership without assigned roles' AS CheckName,
       COUNT_BIG(*) AS ViolationCount,
       CASE WHEN COUNT_BIG(*)=0 THEN N'PASS' ELSE N'FAIL' END AS CheckResult
FROM ten.TenantMemberships M
JOIN mst.MembershipStatuses MS ON MS.MembershipStatusId=M.MembershipStatusId
JOIN iam.TenantRoleAssignments RA ON RA.MembershipId=M.MembershipId
WHERE MS.Code=N'INVITED';
GO
-- Owner rule: PERSONAL exactly one active OWNER; ORGANIZATION at least one for PENDING/ACTIVE tenants.
-- Reports only aggregate total violations (no TenantId in output).
;WITH Owners AS (
 SELECT M.TenantId, COUNT_BIG(*) AS ActiveOwnerCount
 FROM ten.TenantMemberships M
 JOIN mst.MembershipStatuses MS ON M.MembershipStatusId=MS.MembershipStatusId AND MS.Code=N'ACTIVE'
 JOIN iam.TenantRoleAssignments RA ON RA.MembershipId=M.MembershipId
 JOIN mst.Roles R ON R.RoleId=RA.RoleId AND R.Code=N'OWNER'
 JOIN mst.RoleScopes RS ON RS.RoleScopeId=R.RoleScopeId AND RS.Code=N'TENANT'
 GROUP BY M.TenantId
), Violations AS (
 SELECT T.TenantId
 FROM ten.Tenants T
 JOIN mst.TenantTypes TT ON TT.TenantTypeId=T.TenantTypeId
 JOIN mst.TenantStatuses TS ON TS.TenantStatusId=T.TenantStatusId
 LEFT JOIN Owners O ON O.TenantId=T.TenantId
 WHERE TS.Code IN (N'ACTIVE',N'PENDING')
 AND ((TT.Code=N'PERSONAL' AND ISNULL(O.ActiveOwnerCount,0)<>1)
      OR (TT.Code=N'ORGANIZATION' AND ISNULL(O.ActiveOwnerCount,0)<1))
)
SELECT N'Active/Pending tenant owner cardinality' AS CheckName, COUNT_BIG(*) AS ViolationCount,
 CASE WHEN COUNT_BIG(*)=0 THEN N'PASS' ELSE N'FAIL' END AS CheckResult
FROM Violations;
GO
