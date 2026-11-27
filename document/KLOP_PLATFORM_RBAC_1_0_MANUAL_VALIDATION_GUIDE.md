# KLOP-PLATFORM-RBAC-1.0 Manual Validation Guide

## Do not start until prerequisites are met

1. Obtain explicit Development DBA approval and a change ticket. The workbook says no test database is available and no automatic deployment is permitted.
2. Take and verify a fresh full backup of `KlopPlatformDB`; preserve the current definitions of all authorization procedures replaced by script 003 and the existing role-permission index. No test/restore database is authorized.
3. Build and stage the latest API source before applying script 003. Do not start the new API until SQL post-deployment checks pass and its runtime identity is ready.
4. Provision a dedicated non-admin individual Windows/Entra API identity outside the SQL package. The runtime-principal/grants script requires its own separate security approval and ticket.
5. Apply only the exact scripts and order below. Do not seed proposed, conditional, or HOLD capabilities.
6. Acquire fresh sessions with existing, verified `SUPER_ADMIN`, `PLATFORM_SUPPORT`, and ORGANIZATION OWNER accounts. Use ADMIN only to verify its currently mapped permissions; it lacks `tenant.roles.assign`.

No positive live test was run during this task. Any write test against the shared Development database needs a separately approved disposable organization/member fixture; do not mutate the existing organization or real accounts merely to exercise a route.

## Exact SQL deployment order

The read-only v1.10 preflight was rerun on 2026-11-25 and passed. The permission row and mappings are still absent, `iam.usp_GetTenantPermissions` is still absent, and no database mutation has been performed. The package is **NOT READY** until the applicable DBA approvals and the separate runtime security approval are recorded.

| Order | Exact repository path | Execution and success criteria |
|---|---|---|
| 1 | `klop-next-platform-api/database/migrations/v1.10/001_rbac_preflight_READONLY.sql` | Run first in standard SSMS mode. It is read-only. Stop if it throws, if the six role records/tenant type policy differ, if there are multiple active OWNER assignments, or if expected objects are missing. |
| 2 | `klop-next-platform-api/database/migrations/v1.10/002_platform_registration_permissions_APPROVAL_TEMPLATE.sql` | Only after a DBA ticket explicitly approves the exact permission seed. In SSMS enable **Query > SQLCMD Mode**. Set the approved ticket and `KLOP_APPLY_CHANGES` to `APPROVED`. Expected final row: `PASS`; only `platform.registrations.read` is mapped to `SUPER_ADMIN` and `PLATFORM_SUPPORT`. Default settings intentionally return `DRY RUN - NO CHANGES`. |
| 3 | `klop-next-platform-api/database/migrations/v1.10/003_tenant_permission_policy_APPROVAL_TEMPLATE.sql` | This revised, not-yet-deployed template needs fresh DBA/policy approval. It extends the existing role-permission table for tenant type and concurrency, splits existing tenant mappings into PERSONAL/ORGANIZATION context, adds only matrix read/update permissions for SUPER_ADMIN, stores self-service policy rows outside the role-scope and permission-mapping catalogs, and defines three matrix procedures. Keep SQLCMD Mode enabled and supply the approved ticket/apply variable. Expected final row: `v1.10 tenant and unified RBAC matrix routines installed`. |
| 4 | `klop-next-platform-api/database/migrations/v1.10/004_rbac_postdeploy_validation_READONLY.sql` | Run in standard SSMS mode only after steps 2 and 3. It is read-only. Continue only if it ends with `POSTDEPLOY DATABASE CHECKS PASSED` and the outputs show exactly the two approved registration role mappings. |
| 5 | `klop-next-platform-api/database/security/v1.10_runtime_identity_and_grants_APPROVAL_TEMPLATE.sql` | Separate security approval required. Before execution, a DBA must provision the exact non-sysadmin individual Windows/Entra login and provide its approved login name/ticket. In SQLCMD Mode, update only those approved variables. Expected completion is `REVIEW REQUIRED`, followed by the instruction to validate the runtime principal. This grants exactly 38 object-level EXECUTE permissions; it does not create a server login or revoke anything. |
| 6 | `klop-next-platform-api/database/security/v1.10_runtime_identity_validation_READONLY.sql` | Run read-only from a connection using the exact Windows identity configured for the API, never `dbo`, `sysadmin`, or `EXECUTE AS`. Expected final row: `PASS`. The current API identity will fail this check. |

For read-only SQLCMD execution, these exact commands target only the reviewed server/database:

```powershell
sqlcmd -S "DEV-PC\SQLEXPRESS" -d "KlopPlatformDB" -E -b -i "D:\PROJECT\Smart\klop\klop-next-platform-api\database\migrations\v1.10\001_rbac_preflight_READONLY.sql"
sqlcmd -S "DEV-PC\SQLEXPRESS" -d "KlopPlatformDB" -E -b -i "D:\PROJECT\Smart\klop\klop-next-platform-api\database\migrations\v1.10\004_rbac_postdeploy_validation_READONLY.sql"
sqlcmd -S "DEV-PC\SQLEXPRESS" -d "KlopPlatformDB" -E -b -i "D:\PROJECT\Smart\klop\klop-next-platform-api\database\security\v1.10_runtime_identity_validation_READONLY.sql"
```

The second command is post-deployment only; do not use it as a substitute for the preflight. Run the third only from a shell opened as the exact API integrated-security principal; an elevated developer shell is not valid evidence. `001`, `004`, and `006` contain no SQLCMD directives; scripts `002`, `003`, and `005` contain `:setvar`/`:on error exit` and require SSMS SQLCMD Mode.

### SSMS execution and stop conditions

1. Connect to the Database Engine at `DEV-PC\SQLEXPRESS`, select `KlopPlatformDB`, and verify both values in the SSMS status bar before executing anything.
2. Open and execute `001` first. Save its output with the change ticket. Do not proceed if it throws or its state differs from the reviewed results below.
3. Open each approved template in a separate query window. For `002`, `003`, and `005`, enable **Query > SQLCMD Mode** and verify the displayed variables are the approved Development values. Do not change defaults without the relevant approval.
4. Execute one script at a time and inspect all result sets and messages before opening the next step. Do not select/run a subset of a template.
5. On any error, unexpected row count, wrong database/server, SQLCMD substitution failure, or result other than the stated success result: **stop**. Do not continue to a later script. For script 003, which holds a transaction across `GO` batches and has no outer TRY/CATCH, have the DBA inspect `@@TRANCOUNT`/`XACT_STATE()` in that same query session and resolve it before closing or retrying. Do not issue an unreviewed manual rollback.
6. Never run the runtime grants script as a way to repair a failed app permission check. Never add broader grants, delete unexpected mappings, or change roles to make a post-check pass.

No script contains `DELETE`, `TRUNCATE`, or `REVOKE`. Script 003 replaces the unique mapping index and stored-procedure/trigger definitions; retain the backup and old definitions for an approved recovery. No older/FROZEN migration file is to be edited, and Development has no migration ledger.

## Read-only platform checks

| Check | Expected |
|---|---|
| Anonymous registration summary/list/detail/timeline | 401 |
| Authenticated non-platform account | 403; no registration data |
| `SUPER_ADMIN` and `PLATFORM_SUPPORT` permission discovery | Includes `platform.registrations.read` only when the approved seed/mappings are active |
| Authorized summary for PERSONAL | Includes the current PERSONAL registration counts |
| Authorized PERSONAL listing | Includes the existing DRAFT with pending email verification; do not filter it out |
| Authorized ORGANIZATION listing | Empty until an organization registration exists; display a real empty state, not a fabricated count |
| Detail and timeline | Read-only; no password/token/hash; timeline contains persisted events only |
| Approval/rejection, resend, export, delete | Not enabled; no inferred permission or mutation route |

Current read-only Development data is one PERSONAL DRAFT with email pending and zero ORGANIZATION registrations. The live API is not updated, so do not treat its current 404/403 results as a positive test of the new source. The deployed registration summary, listing, detail, and timeline procedures all contain and call the canonical `platform.registrations.read` validator; script 002 supplies the currently missing permission row/mappings that cause the DB-side 403.

Use the source API paths after the new API is running:

- Permission discovery: `GET /api/v1/platform/registrations/permissions`
- PERSONAL summary/list: `GET /api/v1/platform/registrations/summary?registrationType=PERSONAL` and `GET /api/v1/platform/registrations?registrationType=PERSONAL`
- ORGANIZATION summary/list: use the same paths with `registrationType=ORGANIZATION`
- Detail/timeline: `GET /api/v1/platform/registrations/{registrationApplicationId}` and `GET /api/v1/platform/registrations/{registrationApplicationId}/timeline`
- Tenant effective permissions: `GET /api/v1/tenants/{tenantId}/permissions`

## Tenant permission and negative checks

1. Query tenant permissions for an active PERSONAL OWNER. The response must omit invite, member removal, and role assignment codes.
2. Query a tenant not actively joined by the caller, a suspended/terminated tenant, and an expired/revoked session. Each must fail closed with no permission list; the existing session validator allows eligible `ACTIVE`/`PENDING` tenants.
3. For an ORGANIZATION OWNER, verify effective membership permissions match the database and that self-assignment, OWNER duplication, PERSONAL role changes, and VIEWER assignment are denied.
4. OWNER assignment of ADMIN/MEMBER may be exercised only with a disposable approved target. ADMIN assignment of MEMBER must remain denied in current Development because ADMIN lacks `tenant.roles.assign`; do not add that mapping as part of this test.
5. Confirm ownership transfer remains unavailable and the last active OWNER cannot be revoked. Do not try these destructive operations on the existing Development organization.
6. Confirm the UI hides membership actions when the permission response omits the code, shows a meaningful denied state for Registration Center access, and does not present API errors as zero counts.

## Unified Role & Permission Matrix checks

1. Sign in as an existing verified `SUPER_ADMIN`. The matrix access response must return `canRead=true` and `canUpdate=true`; `PLATFORM_SUPPORT`, tenant roles, and anonymous users must not receive matrix access.
2. Confirm one matrix view contains PLATFORM, PERSONAL, ORGANIZATION, and read-only account-policy information. The visible role columns are `SUPER_ADMIN`, `PLATFORM_SUPPORT`, PERSONAL `OWNER`, and ORGANIZATION `OWNER`, `ADMIN`, `MEMBER`, `VIEWER`; no new role rows are created.
3. Confirm account self-service appears as informational policy with Public/Unverified/Verified values and no role assignment or editable grant cell. No `ACCOUNT` row exists in `mst.RoleScopes`, and policy identifiers do not exist in `mst.Permissions` or `mst.RolePermissions`.
4. Confirm configured grants, effective-allowed status, readiness, and restrictions are displayed separately. PERSONAL membership operations remain denied even if a tenant grant is configured; HOLD/PLANNED cells cannot be edited.
5. Submit a batch with a reason, validate it without changes, review the server validation response, then save only an approved disposable test change. A stale concurrency version must return 409 and require a reload. Verify successful saves and rejected save attempts are audited with actor, scope, reason, outcome, and correlation; validate-only calls do not write audit events.
6. Confirm direct API calls enforce database-backed permissions even when the UI is bypassed. No role other than SUPER_ADMIN may read, validate, save, or view the matrix history.

## Application restart commands

The backend launch profile is `KLOP.Platform.Dev` (`https://localhost:7041`, `http://localhost:5041`). At inspection time, PID `22468` was listening on both ports from this repository's `KLOP.Platform.Api.exe` in `bin\Debug\net10.0`; its database identity is elevated. Inspect again before stopping it. This guarded command stops only this repository's API process and refuses to stop an unrelated process occupying either port:

```powershell
$apiProjectRoot = 'D:\PROJECT\Smart\klop\klop-next-platform-api\src\KLOP.Platform.Api'
$ports = 5041, 7041
$listenerIds = @(Get-NetTCPConnection -State Listen -LocalPort $ports -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique)
foreach ($listenerId in $listenerIds) {
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerId"
  if (-not $process -or $process.Name -ne 'KLOP.Platform.Api.exe' -or
      $process.ExecutablePath -notlike "$apiProjectRoot\bin\*\net10.0\KLOP.Platform.Api.exe") {
    throw "Port listener PID $listenerId is not this repository's API; stop and inspect it manually."
  }
  Stop-Process -Id $listenerId
}
```

After step 1 passes, build and stage the latest API before applying script 003, as required by that template. Do not start it under the current elevated identity:

```powershell
Set-Location 'D:\PROJECT\Smart\klop\klop-next-platform-api'
dotnet build .\KLOP.Platform.sln --configuration Release
if ($LASTEXITCODE -ne 0) { throw 'Backend build failed; do not start the API.' }
```

After SQL steps 2–5 pass and the dedicated runtime identity has been approved/provisioned, open a PowerShell session as that API runtime identity (not the current elevated user) and start the built API:

```powershell
Set-Location 'D:\PROJECT\Smart\klop\klop-next-platform-api'
dotnet run --no-build --configuration Release --project .\src\KLOP.Platform.Api\KLOP.Platform.Api.csproj --launch-profile KLOP.Platform.Dev
```

After the backend is healthy, start/restart the HTTPS frontend from its repository root. This checked-in script stops only this project's Vite process on port 5173, trusts/exports the local development certificate, and starts the UI:

```powershell
Set-Location 'D:\PROJECT\Smart\klop\klop-next_ui'
.\start-ui.ps1
```

For each existing test role, sign out, close/reload the portal, and sign in normally to obtain a fresh authenticated session. Do not create accounts, bypass email verification, reuse stale tokens, or send email.

## Manual UI and API checklist

Run only after the backend/frontend restart and fresh sessions:

- [ ] Sign in with an existing verified `SUPER_ADMIN`; open Registration Center.
- [ ] `GET /api/v1/platform/registrations/permissions` returns `platform.registrations.read`.
- [ ] Registration summary/list for `PERSONAL` shows SQL-backed total `1`, pending verification `1`, status `DRAFT`.
- [ ] Registration summary/list for `ORGANIZATION` shows SQL-backed total `0` and a genuine empty state.
- [ ] Open the existing PERSONAL registration detail and persisted timeline; verify no secrets, credential hashes, or fabricated events are displayed.
- [ ] Sign in with an existing verified `PLATFORM_SUPPORT`; confirm its permission discovery and the same read-only Registration Center views.
- [ ] Anonymous registration read is rejected (401); an authenticated existing tenant account without a platform permission is rejected (403) and receives no registration data.
- [ ] For an existing active ORGANIZATION tenant, `GET /api/v1/tenants/{tenantId}/permissions` reflects the current role maps: OWNER has the mapped membership operations and `tenant.roles.assign`; ADMIN has mapped invite/remove but not `tenant.roles.assign`; MEMBER has none of those admin permissions. Do not perform writes against the existing tenant.
- [ ] Confirm no conditional/HOLD action appears or succeeds: approval/rejection, export, ownership transfer, role-permission administration, tenant provisioning, or tenant-business Support access.
- [ ] Confirm all displayed counts, statuses, permissions, detail fields, and timeline events come from SQL Server/API responses, not client-side defaults.

## Audit and runtime evidence

- Confirm a successful approved permission seed records the actor service, permission/role target, change-ticket RequestId, UTC timestamp, success result, and correlation ID.
- Confirm role assignment/revocation success records actor, target, tenant scope, UTC timestamp, result, and correlation ID.
- Verify denied calls have safe API security log results and correlation IDs; never capture credentials, access/refresh tokens, verification secrets, or raw user details.
- Run the runtime validator from the actual service connection and retain only sanitized pass/fail evidence for the 38 exact object EXECUTE grants, no DML/table access, no direct user grants, and no elevated role membership.

## Release decision

Current state: **NOT READY**. The preflight passed read-only, but `platform.registrations.read`, the tenant resolver, and the three matrix procedures are absent from Development; the revised SQL has not been deployed; the latest API is not deployed; the API runs as `dbo`/`sysadmin`; and no dedicated runtime identity or execution tickets exist. Do not claim runtime validation has passed or declare the RBAC baseline FROZEN until all listed checks pass with sanitized evidence and explicit owner approval.
