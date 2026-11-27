# Backend validation report

Validation was executed on 2026-11-21 against the configured Development SQL database. Catalog/configuration queries were read-only; no migration, grant, or write endpoint was run. PASS below describes only the executed check; it is not evidence that an unexecuted success path works.

## Build and automated tests

| Check | Result | Evidence |
|---|---|---|
| `dotnet restore KLOP.Platform.sln` | PASS | All projects up to date; no dependency changes required |
| `dotnet build KLOP.Platform.sln --configuration Release` | PASS | .NET SDK 11.0.100; all projects target `net10.0`; 0 warnings, 0 errors |
| `dotnet test KLOP.Platform.sln --configuration Release --no-build` | PARTIAL | 17 unit tests passed; all 3 database tests were skipped by their `_TEST`/mutation opt-in guard; 0 failures |
| Database mutation/integration tests | BLOCKED | No test SQL environment variables or explicit mutation opt-in were configured; no isolated `_TEST` database was approved or used |
| Frontend locked dependency install (`npm ci --no-audit`) | PASS | Repaired incomplete existing `node_modules` from `package-lock.json`; no manifest changes |
| Frontend build (`npm run build`) | PASS | TypeScript and Vite production build passed; Vite reported two non-fatal Zod/Rollup annotation warnings |
| Frontend unit tests (`npm test`) | PASS | 14 tests passed in 2 files |
| Frontend Playwright (`npm run test:e2e`) | PASS (mocked denial only) | 1 test passed; it stubs an HTTP 401 login response and does not authenticate against SQL/API |
| SQL deployment/migration scripts | USER REPORTED / CATALOG CONFIRMED | User reports running the v1.5 standalone migration; this validation session did not execute DDL |
| Production, effective permission, and concurrency validation | NOT RUN | Requires approved isolated database/runtime identity and deployment setup |

The suite invocation passed for the tests that ran; the three skipped integration tests are not counted as passes. Unit tests cover password hashing/verification, random salts and tokens, malformed hashes, email and registration validation, tenant-field validation, and OpenAPI bearer metadata.

### SQL security/test-enablement follow-up

- The integration project Release build passed after strengthening the SQL fixture; all 3 SQL mutation cases were **SKIPPED**, not passed, because explicit approval variables were absent.
- Read-only inspection confirmed the Development API process identity is `dbo`/SQL Server `sysadmin`. `klop_app_runtime` has zero members and only 1/20 mapped procedure grants. No existing privilege was changed.
- `KlopPlatformDB_TEST` is not provisioned. The generated SQLCMD templates and permission matrix are **PREPARED / NOT EXECUTED**. Database creation, grants, schema deployment, seed writes, and mutation tests remain blocked pending explicit approval.
- The fixture requires the exact test server/database, a ticket, persistent-data opt-in, and the non-admin `KLOP_PLATFORM_TEST_RUNTIME` user. It uses procedure-only fixture setup, and test rows persist until the disposable test database is approved for cleanup.
- The concurrency test no longer uses direct application-table SELECT to count Owners. It relies on successful stored-procedure role assignment, the concurrent revoke outcome, and the final-owner protection error.

## v1.5 SQL readiness checks

The read-only v1.5 preflight script was executed against the configured Development SQL database: **PASS, 139 findings, 0 blockers**. It reported the separate runtime access gate as **BLOCKED** because `klop_app_runtime` has no members. The script did not execute DDL, grants, or data writes. Its result establishes only the pre-deployment metadata prerequisites it checks; it does not establish procedure behavior or permission effectiveness for the API identity.

On 2026-11-21, read-only checks against `DEV-PC\SQLEXPRESS / KlopPlatformDB` confirmed all 20 mapped Stored Procedures present and **9/9 auth/session parameter signatures PASS**. All nine explicit EXECUTE grants to `klop_app_runtime` FAIL and that role has no members. The current Integrated Security caller has effective EXECUTE on all 20 but is a member of both `db_owner` and `db_ddladmin`; this is not least-privilege readiness. All 17 queried SQL configuration rows had the expected types/storage metadata; optional Development key references were empty and no secret values were read. The verifier exits zero when signatures pass even when grant rows are FAIL. No grant, integration workflow, or rollback test was run. See [DATABASE_V1_5_DEPLOYMENT.md](DATABASE_V1_5_DEPLOYMENT.md) for the DBA checklist and recovery procedure.

## Development API smoke evidence

The API was started in Development on a temporary local HTTP port on 2026-11-21. SQL-backed startup settings loaded, readiness reported healthy, and the process was stopped after probes. The actual configured Development database is `DEV-PC\SQLEXPRESS / KlopPlatformDB`; the API process used the same Integrated Security identity verified below, which is elevated.

| Probe | Result | Evidence |
|---|---|---|
| `GET /health/live`, `GET /health/ready` | PASS | Both HTTP 200; ready completed the SQL-backed readiness check |
| `GET /swagger`, `GET /openapi/v1.json` | PASS | Both HTTP 200; OpenAPI contained 15 `/api/v1` operations |
| `GET /.well-known/jwks.json` | PASS | HTTP 200; one RSA public key; private parameters absent |
| `GET /api/v1/master/organization-types` | PASS | HTTP 200; success envelope; 7 SQL-backed rows |
| Read-only Stored Procedure catalog/signature/permission checks | PARTIAL | 20/20 mapped procedures present; 9/9 new signatures match; 0/9 new role grants; runtime role empty; API caller is `db_owner` and `db_ddladmin` |
| Unauthenticated `GET /api/v1/auth/me`, `/api/v1/tenants/mine` | PASS (denial only) | Both returned HTTP 401; no token or database mutation |
| Invalid JSON-object login payload | PASS (validation only) | HTTP 400 before login SQL workflow |
| Refresh without Origin | PASS (denial only) | HTTP 403; no token rotation was attempted |
| CORS preflight from configured `https://localhost:5173` | PASS (preflight only) | HTTP 204; exact allow-origin and credentials header returned |
| CORS preflight from unapproved origin | PASS (denial only) | HTTP 204 without an allow-origin header |
| Invalid correlation header | PASS (safe fallback) | Protected request returned 401 and response contained a parseable generated correlation GUID |

The latest follow-up also exercised the currently configured HTTPS listener (`https://localhost:7041`) and portal (`https://localhost:5173`). Health/readiness, Swagger/OpenAPI, organization-type read, the two unauthenticated protected reads (401), empty login validation (400), refresh without Origin/cookie (403), and allowed/disallowed CORS preflights matched expected results. A real browser-origin credentialed read returned 200 with 7 organization types; unauthenticated navigation to `/tenants` redirected to `/login`. OpenAPI contained 15 `/api/v1` operations. A correlation ID was returned unchanged and appeared in the Serilog request event. The JWKS response contained only public RSA fields.

Endpoint-by-endpoint access, permission, Stored Procedure, and result status is recorded in [API_ENDPOINTS.md](API_ENDPOINTS.md). A successful read of organization types and SQL readiness do not validate the other Stored Procedure contracts or writes.

## Blocked and unexecuted scenarios

The SQL fixture creates persistent records because the procedures commit independently. It therefore remained guarded and all three SQL tests were skipped. Use only a disposable Development clone explicitly named with `_TEST`; never point mutation tests to the existing Development database.

Every scenario in the original v1.3 matrix remains **NOT RUN** against an isolated test database:

| IDs | Scenario summary |
|---|---|
| T01–T04 | Registration atomicity/duplicate email, one-time verification, expiry |
| T05–T07 | Personal/organization creation, verification state, duplicate/invalid tenant |
| T08–T10 | Invitation, acceptance, foreign-tenant actor |
| T11–T14 | Scope/Owner elevation, last-Owner revoke/remove |
| T15–T18 | Concurrent Owner edits, member removal, audit rollback, direct-DML denial |
| T19–T22 | Spoofed actor, master validation, lifecycle restrictions, session validation |
| T23–T26 | Login lockout, JWT claims/expiry, refresh replay, logout |
| T27–T30 | SMTP outage/resend, stale membership, Key Vault, CSRF/cookie origin |
| T31–T32 | Production TLS/permission checks, complete API flow |

Positive registration/verification, successful login/JWT issuance, expired/revoked session behavior, refresh rotation/replay, logout/revocation, authenticated profile/tenant listing, tenant writes, cross-tenant isolation, permission enforcement, last-Owner/concurrency controls, SQL audit-row verification/rollback, effective least-privilege runtime grants, and sensitive-log scanning are not established. The browser verified only the public API read and unauthenticated navigation; no real browser authentication session was created. Procedure objects/signatures now exist, but successful auth/session traffic remains BLOCKED until a least-privilege runtime identity is established and tests are approved against an isolated `_TEST` database. The live Integrated Security identity is elevated and must not be used as evidence of production-style runtime permissions. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) and [DATABASE_DEPENDENCIES.md](DATABASE_DEPENDENCIES.md).

## Running SQL tests safely

Provision the isolated test database and least-privilege identity only under explicit DBA/security approval. Follow [database/testing/README.md](../database/testing/README.md); the reviewed runner sets the exact protected environment values and restores the current process environment afterward:

```powershell
.\database\testing\004_run_integration_tests_TEMPLATE.ps1 `
    -ApprovalTicket '<approved-ticket>' `
    -ApprovePersistentTestData
```

Tests create committed data because the Stored Procedures reject externally owned transactions. Record the test database identity, UTC time, test run ID, raw runner output, observed result, reviewer, and evidence location. Never run mutation tests on Production or the existing non-disposable Development database. Cleanup is limited to dropping the exact disposable `KlopPlatformDB_TEST` after connections stop and explicit approval is recorded.
