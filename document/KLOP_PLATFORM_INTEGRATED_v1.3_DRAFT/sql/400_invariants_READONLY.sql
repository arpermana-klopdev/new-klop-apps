-- Read-only invariants on Development. Any result row is a candidate violation to investigate.
-- 1: Tenant without active OWNER (all tenant lifecycles; adjust only through approved design).
WITH OwnerCounts AS (
 SELECT t.TenantId,t.TenantCode,
  COUNT(CASE WHEN ms.Code='ACTIVE' AND r.Code='OWNER' AND scope.Code='TENANT' THEN 1 END) AS OwnerCount
 FROM ten.Tenants t LEFT JOIN ten.TenantMemberships m ON m.TenantId=t.TenantId
 LEFT JOIN mst.MembershipStatuses ms ON ms.MembershipStatusId=m.MembershipStatusId
 LEFT JOIN iam.TenantRoleAssignments a ON a.MembershipId=m.MembershipId
 LEFT JOIN mst.Roles r ON r.RoleId=a.RoleId
 LEFT JOIN mst.RoleScopes scope ON scope.RoleScopeId=r.RoleScopeId
 GROUP BY t.TenantId,t.TenantCode)
 SELECT * FROM OwnerCounts WHERE OwnerCount<1;
-- 2: More than one ACTIVE member in PERSONAL tenant.
SELECT t.TenantId,t.TenantCode,COUNT_BIG(*) AS ActiveMembers
 FROM ten.Tenants t JOIN mst.TenantTypes tt ON tt.TenantTypeId=t.TenantTypeId AND tt.Code='PERSONAL'
 JOIN ten.TenantMemberships m ON m.TenantId=t.TenantId
 JOIN mst.MembershipStatuses ms ON ms.MembershipStatusId=m.MembershipStatusId AND ms.Code='ACTIVE'
 GROUP BY t.TenantId,t.TenantCode HAVING COUNT_BIG(*)>1;
-- 3: Tenant role assignment with wrong scope.
SELECT tra.TenantRoleAssignmentId,tra.MembershipId,r.Code AS RoleCode,s.Code AS ScopeCode
 FROM iam.TenantRoleAssignments tra JOIN mst.Roles r ON r.RoleId=tra.RoleId
 JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId WHERE s.Code<>'TENANT';
-- 4: Refresh tokens pointing to nonexistent sessions (FK should prevent this).
SELECT rt.RefreshTokenId FROM iam.RefreshTokens rt LEFT JOIN iam.AuthSessions s ON s.AuthSessionId=rt.AuthSessionId
 WHERE s.AuthSessionId IS NULL;
-- 5: audit and event volume summary only (not a pass/fail assertion).
SELECT 'AuditEvents' AS EventCategory,COUNT_BIG(*) AS Total FROM aud.AuditEvents
UNION ALL SELECT 'SecurityEvents',COUNT_BIG(*) FROM aud.SecurityEvents
UNION ALL SELECT 'BusinessEvents',COUNT_BIG(*) FROM aud.BusinessEvents;
