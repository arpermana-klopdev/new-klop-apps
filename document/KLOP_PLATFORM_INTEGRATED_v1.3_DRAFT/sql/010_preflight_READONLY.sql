-- Read-only prerequisite verification. Should return no rows.
SELECT need.Name AS MissingObject FROM (VALUES
 ('cfg.SystemConfigurations'),('cfg.usp_Configuration_GetByKey'),
 ('iam.Users'),('iam.UserCredentials'),('iam.AuthSessions'),('iam.RefreshTokens'),
 ('ten.Tenants'),('ten.TenantMemberships'),('aud.AuditEvents'),('aud.SecurityEvents'),
 ('iam.usp_RegisterLocalUser'),('iam.usp_ConfirmEmail'),('ten.usp_CreateTenantWithOwner'),
 ('ten.usp_InviteExistingUser'),('ten.usp_AcceptMembership'),('ten.usp_RemoveTenantMember'),
 ('iam.usp_AssignTenantRole'),('iam.usp_RevokeTenantRole')) need(Name)
 WHERE OBJECT_ID(need.Name) IS NULL;
SELECT DB_NAME() AS DatabaseName, @@SERVERNAME AS ServerName, SYSDATETIMEOFFSET() AS ExecutionTime;
