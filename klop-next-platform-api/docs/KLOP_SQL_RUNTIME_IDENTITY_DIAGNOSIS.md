# KLOP Development SQL Runtime Identity Diagnosis

**Scope:** Read-only inspection of the Development API configuration and `DEV-PC\SQLEXPRESS` / `KlopPlatformDB`. No database, login, permission, connection-string, application-authentication, or Production changes were made. No secrets or passwords are included.

**Later catalog recheck (2026-11-23 11:45 +07:00):** Both `leg.usp_GetCurrentTerms` and `leg.usp_GetPublicTermsFile` are now present, and all 28 reviewed API procedures exist. The SQL Server default trace records their creation, together with the three legal triggers, through SSMS on `DEV-PC` under `DEV-PC\rajaa` at 11:43:35; it does not retain the submitted SQL text. This agent issued only read-only SQL and did not deploy them. The runtime role still has no members, the `KLOP_PLATFORM_API_DEV` database user is still absent, and only 8 of 28 procedures have explicit role `EXECUTE` grants. See `SQL_V16_DEPLOYMENT_CORRECTION_REPORT.md` for the current recheck and follow-up blockers.

## Findings

| Item | Finding |
|---|---|
| Configured SQL Server | `DEV-PC\SQLEXPRESS` |
| Configured database | `KlopPlatformDB` |
| Configured authentication | Windows Integrated Security (`Sql:Authentication = IntegratedSecurity`); not SQL username/password authentication |
| Effective API principal | **Not directly verifiable as a live API connection:** no `dotnet.exe` or `KLOP.Platform.Api.exe` process was running during inspection. The factory uses the Windows token of the API process. The Visual Studio Development launch profile does not select a separate run-as identity. |
| Current interactive SQL identity | The read-only SQL probe returned effective login `DEV-PC\rajaa`, database user `dbo`, `sysadmin = 1`, and `db_owner = 1`. This confirms the inspected interactive identity is privileged; it is not proof of an API process connection because no API process was running. If the API is launched under this same Windows identity, it will connect with that elevated identity and bypass the runtime role's intended boundary. |
| `klop_app_runtime` membership | Role exists; it has **no members**. Database principal `KLOP_PLATFORM_API_DEV` does not exist. |
| Existing explicit role grants | 8 object-level `EXECUTE` grants: `iam.usp_RegisterLocalUser`, `mst.usp_TenantType_GetAll`, and the six `reg` procedures listed below. The role also has 15 schema-level `DENY` entries (INSERT/UPDATE/DELETE across five schemas); the proposed template preserves these. |
| Procedures in current database | 26 of the API's 28 reviewed procedure requirements exist. Both `leg.usp_GetCurrentTerms` and `leg.usp_GetPublicTermsFile` are missing. Of the 26 present procedures, 8 have explicit `EXECUTE` on the role and 18 do not. |
| Elevated runtime status | No API process was running to measure. The interactive identity used for the SQL probe is elevated (`sysadmin` and `dbo`/`db_owner`) and must not be approved as the API runtime principal. |

### Configuration and effective sources

- `src/KLOP.Platform.Api/appsettings.Development.json` specifies `Sql:Server = DEV-PC\SQLEXPRESS`, `Sql:Database = KlopPlatformDB`, and `Sql:Authentication = IntegratedSecurity`.
- `src/KLOP.Platform.Api/Properties/launchSettings.json` selects the `KLOP.Platform.Dev` project profile and sets `ASPNETCORE_ENVIRONMENT=Development`; it does not set a SQL identity or SQL override.
- `Program.cs` uses `WebApplication.CreateBuilder(args)`. Its default configuration providers allow environment variables and command-line arguments to override JSON settings. No `appsettings.json`, `UserSecretsId`, custom configuration provider, or `Sql__*` variable in the inspecting shell was found. Because the API process was absent, its own launch-time environment/arguments could not be independently inspected.
- `InfrastructureRegistration` receives the `SqlConnectionFactory` constructed in `ServiceRegistration`. The factory reads `Sql:Server`, `Sql:Database`, `Sql:Authentication`, and `Sql:TrustServerCertificate`, then constructs a `SqlConnectionStringBuilder`. For Integrated Security it sets `IntegratedSecurity = true`; it does not set a SQL user or password. The factory enforces encryption and sets `ApplicationName=KLOP.Platform.API`.
- Production settings are separate and were not changed or used for this diagnosis.

## Why SQL error 51632 occurs

`database/security/v1.6_runtime_grants_TEMPLATE.sql` raises error **51632** when it finds no row in `sys.database_role_members` for `klop_app_runtime`. The Development database currently has that exact state: the role exists but has no members, and `KLOP_PLATFORM_API_DEV` is absent. This is a deliberate safety stop before the template applies grants; it is not a connection-authentication failure and does not indicate a wrong server or database.

The interactive identity's `dbo`/`sysadmin` access does not satisfy this guard: sysadmin access does not create a membership in the application role. It can also mask missing grants while the API is run under the developer account. Mapping a dedicated approved identity is required before role grants can be effective.

There is a second, independent deployment blocker: after resolving 51632, the current 28-procedure v1.6 grant list would fail its missing-object check (51633) because the two `leg` procedures are not present. The v1.6 migration preflight requires manual reconciliation when either the `reg` or `leg` schema already exists; `reg` is present in the current database. Do not blindly rerun migrations or apply grants until the database owner has reviewed the live-vs-migration state.

## Least-privilege mapping proposal

1. Select a dedicated Development Windows service identity for the API, separate from `DEV-PC\rajaa` and any developer/admin account. The SQL login for that identity must be provisioned and approved separately. It must be an individual Windows login, not a SQL login or a Windows group, and must have no SQL Server fixed-role membership (including indirect membership through Windows groups).
2. Run the API under that same approved identity. Integrated Security will then present that process token to SQL Server; there is no configured SQL username/password to change.
3. After the DBA reviews the live-vs-migration state and approves any required Development deployment of the missing legal-read objects, map the pre-existing login to database user `KLOP_PLATFORM_API_DEV` and add only that user to `klop_app_runtime`.
4. Grant `EXECUTE` only on the API's reviewed procedure allowlist below. Preserve existing grants and the role's existing DENY entries. Do not grant `sysadmin`, `db_owner`, table DML, broad schema rights, or broad database permissions. Do not create a server login automatically.

### Required procedure `EXECUTE` scope

This combines existing Authentication/tenant/configuration/master-data calls with the v1.6 Registration calls used by `KlopRepository`:

- **Authentication and tenant/configuration (20):**
  - `iam.usp_RegisterLocalUser`
  - `iam.usp_ConfirmEmail`
  - `iam.usp_IssueEmailVerificationChallenge`
  - `iam.usp_GetLocalLoginCandidate`
  - `iam.usp_RecordLocalLoginFailure`
  - `iam.usp_CreateAuthSession`
  - `iam.usp_ValidateSessionAccess`
  - `iam.usp_RotateRefreshToken`
  - `iam.usp_RevokeAuthSession`
  - `iam.usp_GetUserProfile`
  - `iam.usp_AssignTenantRole`
  - `iam.usp_RevokeTenantRole`
  - `ten.usp_ListMyTenants`
  - `ten.usp_CreateTenantWithOwner`
  - `ten.usp_InviteExistingUser`
  - `ten.usp_AcceptMembership`
  - `ten.usp_RemoveTenantMember`
  - `mst.usp_OrganizationType_GetAll`
  - `mst.usp_TenantType_GetAll`
  - `cfg.usp_Configuration_GetByKey`
- **v1.6 Registration/onboarding (6):** `reg.usp_GetMyApplication`, `reg.usp_GetApplicationForOwner`, `reg.usp_SavePersonalDraft`, `reg.usp_SaveOrganizationDraft`, `reg.usp_GetOrganizationRequirements`, `reg.usp_SubmitOnboarding`.
- **v1.6 legal-document reads called by Registration (2):** `leg.usp_GetCurrentTerms`, `leg.usp_GetPublicTermsFile`. These are part of the API call surface but are **missing from the current database** and cannot be granted until their reviewed deployment is resolved.

The 8 existing explicit grants (including all six existing `reg` procedures) should be preserved. The final approved grant set is 28 object-level `EXECUTE` permissions only, after all 28 objects exist and their schema ownership/ownership-chaining assumptions are reviewed.

## Approval-required SQL template

A separate guarded template is at:

`database/security/v1.6_runtime_identity_mapping_and_grants_APPROVAL_TEMPLATE.sql`

It is **not executed**. It defaults to `KLOP_APPLY_CHANGES=NO` and an unset approval ticket; it refuses to proceed unless explicitly approved, the target remains the exact Development server/database, the login is a pre-existing non-admin individual Windows login, and all 28 procedures and reviewed schema owners exist. It creates no SQL Server login or role. If approved and all preconditions pass, its transaction creates only the database-user mapping (if absent), adds the user to the existing role, and grants the reviewed object-level `EXECUTE` set. It does not grant table/data access or any server/database-wide privilege.

Do **not** substitute the current interactive identity for the template's login placeholder. The existing `v1.6_runtime_grants_TEMPLATE.sql` is not safe to run as-is for this state: it will stop on 51632, and its header's review-only wording is not itself an execution approval gate.

## Verification after separately approved execution

1. Have the DBA confirm the dedicated Windows login already exists and has no direct or Windows-group-derived server fixed-role memberships. Review the Development v1.6 migration state first; do not run a migration against the current schemas without reconciliation.
2. Set the approved login name, ticket, and `KLOP_APPLY_CHANGES=APPROVED` only in the reviewed SQLCMD invocation for the new template. Confirm it reports 28 reviewed object grants. Never target Production or a test database.
3. Run the API under that same Windows identity. As a DBA, inspect the active SQL session after an API DB call and confirm `program_name = KLOP.Platform.API`, `login_name`/`original_login_name` match the approved identity, and `database_name = KlopPlatformDB`. For example, a read-only DMV query is:

   ```sql
   SELECT session_id, host_name, program_name, login_name, original_login_name,
		  DB_NAME(database_id) AS database_name
   FROM sys.dm_exec_sessions
   WHERE is_user_process = 1
	 AND program_name = N'KLOP.Platform.API';
   ```

4. Using a SQL session authenticated as the approved runtime identity (not a DBA or `EXECUTE AS` simulation), verify `USER_NAME() = N'KLOP_PLATFORM_API_DEV'`, `IS_SRVROLEMEMBER(N'sysadmin') = 0`, `IS_ROLEMEMBER(N'db_owner') = 0`, and `IS_ROLEMEMBER(N'klop_app_runtime') = 1`. Check `HAS_PERMS_BY_NAME(..., N'OBJECT', N'EXECUTE') = 1` for all 28 listed procedures and confirm no effective INSERT/UPDATE/DELETE/SELECT on application tables. Existing `database/security/04_runtime_permission_validation.sql` covers the legacy 20-object baseline; extend/read alongside it for the eight v1.6 objects, because it does not validate the full 28-object set.
5. Exercise Authentication and Registration through the API and confirm they continue to work under the approved non-admin identity. Preserve the validation output and approval/change record. Do not weaken the role or use an elevated login to make a failing test pass.

## Evidence and limits

The configured Development target was verified by reading the checked-in Development configuration and by a read-only SQL Server query that returned `DEV-PC\SQLEXPRESS` and `KlopPlatformDB`. The role membership, role permission summary, database user, procedure catalog, and current SQL-session identity/elevation flags were inspected read-only. The API was not running; therefore its active process token and launch-time override values could not be proven. No SQL change, login creation, grant, role alteration, database creation, or Production operation was performed.
