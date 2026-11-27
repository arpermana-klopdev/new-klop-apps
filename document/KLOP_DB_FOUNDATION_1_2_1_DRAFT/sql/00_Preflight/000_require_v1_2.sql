-- KLOP 1.2.1 DRAFT -- additive to v1.2 DRAFT; never alter v1.1 FROZEN.
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'mst.VerificationPurposes', N'U') IS NULL
 OR OBJECT_ID(N'mst.BusinessEventTypes', N'U') IS NULL
 OR OBJECT_ID(N'mst.RoleScopes', N'U') IS NULL
 OR OBJECT_ID(N'mst.Roles', N'U') IS NULL
 OR OBJECT_ID(N'mst.RolePermissions', N'U') IS NULL
 OR OBJECT_ID(N'mst.Permissions', N'U') IS NULL
 OR OBJECT_ID(N'mst.TenantTypes', N'U') IS NULL
 OR OBJECT_ID(N'mst.TenantStatuses', N'U') IS NULL
 OR OBJECT_ID(N'mst.MembershipStatuses', N'U') IS NULL
 OR OBJECT_ID(N'mst.OrganizationTypes', N'U') IS NULL
 OR OBJECT_ID(N'mst.VerificationStatuses', N'U') IS NULL
 OR OBJECT_ID(N'mst.AuditActionTypes', N'U') IS NULL
 OR OBJECT_ID(N'mst.AuditResultTypes', N'U') IS NULL
 OR OBJECT_ID(N'iam.Users', N'U') IS NULL
 OR OBJECT_ID(N'iam.UserCredentials', N'U') IS NULL
 OR OBJECT_ID(N'iam.VerificationChallenges', N'U') IS NULL
 OR OBJECT_ID(N'ten.Tenants', N'U') IS NULL
 OR OBJECT_ID(N'ten.Organizations', N'U') IS NULL
 OR OBJECT_ID(N'ten.TenantMemberships', N'U') IS NULL
 OR OBJECT_ID(N'iam.TenantRoleAssignments', N'U') IS NULL
 OR OBJECT_ID(N'aud.AuditEvents', N'U') IS NULL
 OR OBJECT_ID(N'aud.BusinessEvents', N'U') IS NULL
 THROW 52100, 'KLOP v1.2 operational tables missing. Stop migration.', 1;
GO
IF NOT EXISTS (SELECT 1 FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId WHERE s.Code='TENANT' AND r.Code='OWNER' AND r.IsActive=1)
 OR NOT EXISTS (SELECT 1 FROM mst.Roles r JOIN mst.RoleScopes s ON s.RoleScopeId=r.RoleScopeId WHERE s.Code='TENANT' AND r.Code='MEMBER' AND r.IsActive=1)
 OR NOT EXISTS (SELECT 1 FROM mst.Permissions WHERE Code='tenant.roles.assign' AND IsActive=1)
 OR NOT EXISTS (SELECT 1 FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1)
 OR NOT EXISTS (SELECT 1 FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1)
 THROW 52101, 'Master seeds/role policies incomplete. Stop migration.', 1;
GO
PRINT 'v1.2.1 prerequisite objects and essential seed rows found; this is not an integration test.';
GO
