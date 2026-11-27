# Development SQL Runtime Security Remediation Report

## Executive status

**Status: PREPARED; NOT APPLIED.** Current SQL-backed authentication/runtime access is not least-privilege-ready. Five DBA scripts are staged in `database/security/`. All have an exact Development server/database guard; mutating scripts are dry-run by default and require explicit SQLCMD approval plus a change ticket. No SQL mutation, login/user creation, role change, grant, database creation, or application deployment was performed for this package.

## 1. Actual runtime identity

Current Development configuration (`src/KLOP.Platform.Api/appsettings.Development.json`) targets `DEV-PC\SQLEXPRESS / KlopPlatformDB` with `IntegratedSecurity`. Read-only SQLCMD inspection on 2026-11-22 confirmed:

| Property | Observed value |
|---|---|
| SQL Server/database | `DEV-PC\SQLEXPRESS / KlopPlatformDB` |
| SQL connection `ORIGINAL_LOGIN()` | Microsoft-account-backed login (UPN redacted) |
| Effective SQL login | `DEV-PC\rajaa` |
| Database user | `dbo` |
| Server role | `sysadmin` |
| Database roles | `db_owner`, `db_ddladmin` |
| `klop_app_runtime` membership | No |
| API authentication | Integrated Security |

Windows identity for the verification shell was `DEV-PC\rajaa`. No API process was running at the time of this recheck, so its process owner could not be freshly queried in this turn. The prior read-only API-process inspection documented in `docs/DATABASE_DEPENDENCIES.md` / `docs/SQL_RUNTIME_PERMISSION_MATRIX.md` found the live API effective login mapped to `dbo` and `sysadmin`. The current SQLCMD connection is fresh SQL evidence for the same elevated login, not a claim that SQLCMD is the API process. Do not use the DBA/shell identity as proof of the future dedicated service identity.

## 2. Current SQL permissions

The fresh read-only connection can effectively execute all 20 mapped procedures, but only because it is `sysadmin`/`dbo`; this is not acceptable runtime validation. The role itself has one explicit object grant (`EXECUTE` on `mst.usp_TenantType_GetAll`), zero members, and no explicit grant on the other 19 mapped procedures. The query also displayed system-catalog `DENY` entries on internal `sys` objects; they are not app-table grants and do not compensate for runtime grants. `KlopPlatformDB_TEST` is absent.

The configured Development database target and procedure mapping are confirmed. No fresh API service process, post-remediation service principal, or direct runtime-identity connection was available. `database/security/01_runtime_identity_preflight.sql` and `04_runtime_permission_validation.sql` are the repeatable read-only procedures for DBA and actual-runtime sessions respectively.

## 3. Proposed least-privilege identity

Use a dedicated **individual Windows gMSA/service identity** for the Development API (for example, an infrastructure-approved `DOMAIN\\gmsa-klop-platform-api-dev$`; this is a naming example, not an existing principal). Grant it only the service logon rights needed to run the API. Provision its Windows login at the SQL Server instance through the organization's approved identity process; do not embed a password or use SQL authentication. The current connection factory supports Integrated Security without code changes.

The exact account must be chosen by the Windows/SQL administrators. It must not be `DEV-PC\\rajaa`, an administrator, a broadly privileged Windows group, or a member of SQL `sysadmin`. The scripts expect an existing enabled individual Windows login, map it to database user `KLOP_PLATFORM_API_DEV`, and add it to `klop_app_runtime`. Review Windows nested-group membership separately; SQL role checks alone are not a substitute for directory-group review.

No application user/credential, password hash, application role, schema, or frozen-baseline change is proposed. The only database-user change is the new SQL service-principal mapping described above, and that remains unexecuted pending DBA approval. The external Windows identity and SQL Server login must be provisioned separately. No SQL login password is requested or stored by these scripts.

## 4. Stored procedure grants matrix

The 20 individual object-level `EXECUTE` grants below are the complete source-mapped API surface, not a blanket schema/database grant. For an installation that intentionally disables API routes, the DBA/product owner should approve a narrower list before execution.

| Schema | Stored procedure | Application use |
|---|---|---|
| `cfg` | `usp_Configuration_GetByKey` | Runtime settings and readiness |
| `mst` | `usp_TenantType_GetAll` | Tenant-type validation |
| `mst` | `usp_OrganizationType_GetAll` | Organization-type lookup |
| `iam` | `usp_RegisterLocalUser` | Registration |
| `iam` | `usp_ConfirmEmail` | Email verification |
| `ten` | `usp_CreateTenantWithOwner` | Tenant creation |
| `ten` | `usp_InviteExistingUser` | Membership invitation |
| `ten` | `usp_AcceptMembership` | Invitation acceptance |
| `ten` | `usp_RemoveTenantMember` | Membership removal |
| `iam` | `usp_AssignTenantRole` | Role assignment |
| `iam` | `usp_RevokeTenantRole` | Role revocation |
| `iam` | `usp_GetLocalLoginCandidate` | Login candidate lookup |
| `iam` | `usp_RecordLocalLoginFailure` | Failed-login/lockout audit |
| `iam` | `usp_IssueEmailVerificationChallenge` | Verification resend |
| `iam` | `usp_CreateAuthSession` | Session creation |
| `iam` | `usp_ValidateSessionAccess` | Session and tenant authorization |
| `iam` | `usp_RotateRefreshToken` | Refresh rotation/replay handling |
| `iam` | `usp_RevokeAuthSession` | Logout/session revocation |
| `iam` | `usp_GetUserProfile` | `/api/v1/auth/me` |
| `ten` | `usp_ListMyTenants` | Current-user tenant listing |

Required baseline: database `CONNECT` (normally inherited from `public`) plus the 20 role-scoped object grants. Prohibited: `sysadmin`, `db_owner`, `db_ddladmin`, broad database roles, direct application-table `SELECT/INSERT/UPDATE/DELETE`, schema/database-wide `EXECUTE`, ownership, `CONTROL`, `ALTER`, `IMPERSONATE`, and grant options. No table DML is needed; procedures use the reviewed same-database `dbo` ownership chain.

## 5. DBA SQL scripts

Scripts are in `database/security/`:

1. `01_runtime_identity_preflight.sql` — read-only identity, mapping, role, procedure-catalog/grant, and environment inventory. It labels effective permissions of the executing connection as **not proof** of runtime permissions.
2. `02_runtime_identity_setup_DEV.sql` — guarded, idempotent setup of the `klop_app_runtime` role (if absent), mapped database user, and role membership only. It does not create a server login or grant procedure/table permissions.
3. `03_stored_procedure_grants_DEV.sql` — guarded, idempotent, explicit `GRANT EXECUTE ON OBJECT::...` statements for the reviewed 20-procedure allowlist. It preserves pre-existing allowlisted grants, emits a rollback manifest of only grants added by that execution, and fails on out-of-allowlist grants.
4. `04_runtime_permission_validation.sql` — read-only validation that must be run through a real connection made by the approved API runtime identity, not as DBA and not through `EXECUTE AS`. It checks actual identity, roles, mapped procedure execution, broad/table access, schema ownership/chaining, and calls the settings procedure while suppressing configuration values from output.
5. `05_runtime_security_rollback_DEV.sql` — approval-gated, scoped rollback of only the explicitly supplied comma-separated grants recorded as added by the change; optional removal of runtime-role membership. It leaves the external login, database user, role, pre-existing grants, and database data untouched.

Every file checks `KLOP_ENVIRONMENT=Development`, exact server `DEV-PC\\SQLEXPRESS`, and exact database `KlopPlatformDB`; no script targets Production or a test database. All mutating SQL files default to `KLOP_APPLY_CHANGES=NO` and `KLOP_APPROVAL_TICKET=UNSET`. They use transactions, fail-closed checks, `TRY/CATCH` rollback, and post-checks. The current pre-existing `mst.usp_TenantType_GetAll` grant is preserved; script 03's rollback manifest contains only grants added by that particular run. Use exactly that manifest for any approved rollback.

## 6. Read-only validation results

- Fresh SQLCMD query, 2026-11-22: server/database confirmed; current SQL session identity and server/database role memberships confirmed as listed above.
- `01_runtime_identity_preflight.sql` ran read-only against the configured Development target. It confirmed all 20 procedures exist, one explicit runtime-role grant, no runtime-role members, application schema ownership by `dbo`, and both cross-database chaining and `TRUSTWORTHY` disabled. Its current-connection effective `EXECUTE` output is explicitly marked as not runtime proof.
- A read-only call to `cfg.usp_Configuration_GetByKey` for `database.command_timeout_seconds` returned one valid INTEGER/PLAIN row; the setting value was not emitted.
- All five SQL files passed SQL Server `SET PARSEONLY` parsing. Setup, grants, and rollback scripts were each run with their default dry-run flags and returned `DRY RUN - NO CHANGES`; no mutation statement was executed.
- Effective current-session permission check: 20/20 mapped procedures available to the elevated `sysadmin`/`dbo` connection. This result does **not** validate the future runtime principal.
- Runtime role metadata: 0 members; 1/20 explicit object `EXECUTE` grants (`mst.usp_TenantType_GetAll`).
- API process enumeration: no running API process to inspect in this turn; prior dated process inspection is documented in the existing SQL runtime reports.
- `04_runtime_permission_validation.sql` was syntax-parsed but not run as a runtime login because the approved runtime identity does not yet exist. Running it as the current DBA would correctly fail the identity gate and would not establish runtime permissions.
- `KlopPlatformDB_TEST`: absent; no test database created.
- No mutation script was executed. Read-only report evidence was not generated from DBA-only effective grants to claim runtime success.

## 7. Approval requirements

Before any mutation, require all of the following:

1. DBA/security approval and change-ticket ID for the exact Development host/database and maintenance window.
2. An infrastructure-approved dedicated Windows gMSA/service identity, its service-logon configuration, pre-created enabled individual Windows SQL login, and directory review confirming no administrative group inheritance.
3. Review of `01_runtime_identity_preflight.sql` output, the allowlist, current role grants, schema ownership, and backup/recovery plan.
4. The application's actual hosting process configured to run as the approved identity. Do not keep the API under the current `dbo`/`sysadmin` identity.
5. DBA approval of any login/user/role/grant changes. This package itself does not constitute that approval.

## 8. Safe execution instructions

Run from the repository root with SQLCMD after reviewing each script and confirming the active target; never run multiple scripts by blindly copying a batch. Initially execute only script 01 and then script 02/03 with dry-run defaults. Use an approved ticket and substitute the actual approved identity. Dry-run example:

```powershell
sqlcmd -S "DEV-PC\SQLEXPRESS" -d "KlopPlatformDB" -E -b -i "database\security\01_runtime_identity_preflight.sql" -v KLOP_ENVIRONMENT="Development" KLOP_EXPECTED_DATABASE="KlopPlatformDB" KLOP_RUNTIME_LOGIN="DOMAIN\gmsa-klop-platform-api-dev$" KLOP_RUNTIME_USER="KLOP_PLATFORM_API_DEV"
```

Only after DBA approval, run setup then grants individually with `KLOP_APPLY_CHANGES="APPROVED"` and the real change ticket. Confirm every result set and save script-03's `ROLLBACK_MANIFEST` exactly; it includes only grants added by that run. Configure/restart the API under the approved service identity, then run script 04 from a connection made by that process identity. Do not use a DBA session, impersonation, or SQLCMD under an administrator for the runtime pass. Do not run registration/login/session mutation tests on `KlopPlatformDB`; none were performed here.

Approved execution shape (replace the sample service principal and ticket only after approval; execute each script separately):

```powershell
sqlcmd -S "DEV-PC\SQLEXPRESS" -d "KlopPlatformDB" -E -b -i "database\security\02_runtime_identity_setup_DEV.sql" -v KLOP_ENVIRONMENT="Development" KLOP_EXPECTED_DATABASE="KlopPlatformDB" KLOP_RUNTIME_LOGIN="DOMAIN\gmsa-klop-platform-api-dev$" KLOP_RUNTIME_USER="KLOP_PLATFORM_API_DEV" KLOP_APPROVAL_TICKET="CHG-APPROVED-ID" KLOP_APPLY_CHANGES="APPROVED"
sqlcmd -S "DEV-PC\SQLEXPRESS" -d "KlopPlatformDB" -E -b -i "database\security\03_stored_procedure_grants_DEV.sql" -v KLOP_ENVIRONMENT="Development" KLOP_EXPECTED_DATABASE="KlopPlatformDB" KLOP_RUNTIME_LOGIN="DOMAIN\gmsa-klop-platform-api-dev$" KLOP_RUNTIME_USER="KLOP_PLATFORM_API_DEV" KLOP_APPROVAL_TICKET="CHG-APPROVED-ID" KLOP_APPLY_CHANGES="APPROVED"
```

## 9. Rollback procedures

Rollback requires a separately approved ticket/change action. First use script 05 in dry-run mode. Supply `KLOP_REVOKE_OBJECTS` as only the exact `schema.procedure` entries recorded as newly granted by script 03; if the manifest is `<none>`, leave this variable `UNSET`. Set `KLOP_APPLY_CHANGES="APPROVED"` and provide the rollback ticket to revoke those explicit role grants transactionally. If the service identity must be detached, separately approve `KLOP_REMOVE_RUNTIME_MEMBERSHIP="YES"`; this removes only that database role membership. The script does not drop the external login, database user, runtime role, pre-existing `mst.usp_TenantType_GetAll` grant, schema, or database. Restore API host configuration to the pre-change state under change control. Validate the post-rollback state read-only. Never revoke unrelated administrator permissions or use broad database-role changes as rollback.

## 10. Authentication readiness

`PasswordCodec` in `src/KLOP.Platform.Application/Features/Security.cs` retains the 600,000-round current writer and strictly verifies the supported legacy vector with PBKDF2-HMAC-SHA256; the most recent unit run passed 34/34 non-mutating tests. This establishes local unit behavior only, not SQL-backed auth readiness.

**SQL-backed authentication readiness: BLOCKED** until the API runs under the approved non-admin identity, script 04 passes through that actual process identity, SQL settings load, all 20 procedures pass effective checks, and separately approved isolated Development integration checks establish audit/session behavior. Do not modify or use `super.admin@klop-test.example` or `platform.support@klop-test.example` in automatic tests. No automatic login was performed.

Manual testing may proceed only after DBA approval, runtime validation, and explicit product/security approval, using a separately approved non-production test account (not the two named accounts):

1. Manually `POST /api/v1/auth/login`; verify a successful access-token response and the expected HttpOnly refresh cookie. Do not log tokens or expect the refresh token in the response body.
2. Validate JWT issuer, audience, signature, expiry, subject, and session claims locally without recording the token.
3. Call `GET /api/v1/auth/me` with the bearer token; confirm the profile belongs to that test account.
4. Exercise refresh with the test session once; verify rotation and that the previous refresh token cannot be reused, using approved isolated test data only.
5. Logout; verify session revocation and that subsequent `/me`/refresh calls are rejected.
6. Platform-role authorization cannot currently be exercised: `docs/API_ENDPOINTS.md` documents that no PLATFORM-scoped permission-protected API is published. If such a route is later approved and published, test an authorized and unauthorized disposable principal without changing existing user role assignments.

## Remaining blockers

- Select/provision the dedicated Development Windows service identity and configure the API host to run as it.
- Obtain explicit DBA/security approval before executing scripts 02, 03, or 05.
- Re-run the actual-process identity and permission validation after the approved setup; current elevated-session rights are not runtime evidence.
- SQL-backed session/audit/authorization workflows remain untested; no TEST database or mutation test may be used absent separate approval.
