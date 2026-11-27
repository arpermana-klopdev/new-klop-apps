SET NOCOUNT ON;
GO
-- v1.1 is frozen; do not edit or overwrite it.
-- This preflight checks structural dependencies only, not full v1.1 data quality.
IF OBJECT_ID(N'mst.TenantTypes', N'U') IS NULL OR
   OBJECT_ID(N'mst.TenantStatuses', N'U') IS NULL OR
   OBJECT_ID(N'mst.OrganizationTypes', N'U') IS NULL OR
   OBJECT_ID(N'mst.MembershipStatuses', N'U') IS NULL OR
   OBJECT_ID(N'mst.RoleScopes', N'U') IS NULL OR
   OBJECT_ID(N'mst.Roles', N'U') IS NULL OR
   OBJECT_ID(N'mst.VerificationStatuses', N'U') IS NULL OR
   OBJECT_ID(N'mst.AuditActionTypes', N'U') IS NULL OR
   OBJECT_ID(N'mst.AuditResultTypes', N'U') IS NULL OR
   OBJECT_ID(N'mst.SecurityEventTypes', N'U') IS NULL OR
   OBJECT_ID(N'cfg.SystemConfigurations', N'U') IS NULL
   THROW 51000, 'KLOP v1.1 prerequisite tables are missing. Stop.', 1;
GO
IF SCHEMA_ID(N'iam') IS NULL OR SCHEMA_ID(N'ten') IS NULL OR SCHEMA_ID(N'aud') IS NULL
   THROW 51001, 'Required v1.1 reserved schemas are missing. Stop.', 1;
GO
