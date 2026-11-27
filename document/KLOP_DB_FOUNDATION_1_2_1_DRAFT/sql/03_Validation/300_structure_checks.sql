-- Read-only structural checks. Not an integration test; run in DEVELOPMENT after migration.
SET NOCOUNT ON;
GO
DECLARE @Expected TABLE (SchemaName SYSNAME, ProcName SYSNAME);
INSERT INTO @Expected (SchemaName,ProcName) VALUES
 ('iam','usp_RegisterLocalUser'),('iam','usp_ConfirmEmail'),('ten','usp_CreateTenantWithOwner'),
 ('ten','usp_InviteExistingUser'),('ten','usp_AcceptMembership'),('ten','usp_RemoveTenantMember'),
 ('iam','usp_AssignTenantRole'),('iam','usp_RevokeTenantRole');
IF EXISTS (
    SELECT 1 FROM @Expected e
    WHERE OBJECT_ID(QUOTENAME(e.SchemaName)+'.'+QUOTENAME(e.ProcName),N'P') IS NULL
) THROW 52200, 'One or more v1.2.1 procedures are missing.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id=OBJECT_ID(N'iam.usp_RegisterLocalUser') AND definition LIKE '%INSERT INTO aud.AuditEvents%')
 THROW 52201, 'Registration audit insert not found in module text.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id=OBJECT_ID(N'ten.usp_RemoveTenantMember') AND definition LIKE '%sp_getapplock%')
 THROW 52202, 'Member removal lock not found in module text.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id=OBJECT_ID(N'iam.usp_RevokeTenantRole') AND definition LIKE '%sp_getapplock%')
 THROW 52203, 'Role revocation lock not found in module text.', 1;
SELECT e.SchemaName, e.ProcName,
       CASE WHEN p.object_id IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS StructuralStatus,
       CASE WHEN p.object_id IS NULL THEN NULL ELSE p.modify_date END AS LastModifiedAt
FROM @Expected e
LEFT JOIN sys.procedures p ON p.object_id=OBJECT_ID(QUOTENAME(e.SchemaName)+'.'+QUOTENAME(e.ProcName),N'P')
ORDER BY e.SchemaName,e.ProcName;
PRINT 'v1.2.1 structural checks passed; transactional, concurrency, privilege and API tests are still required.';
GO
