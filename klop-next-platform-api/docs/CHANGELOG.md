# Changelog

## SQL security and isolated-test enablement — 2026-11-21

- Confirmed by read-only inspection that the live Development API identity maps to `dbo` and is a SQL Server `sysadmin`; `klop_app_runtime` has zero members and only 1/20 mapped procedure grants. `KlopPlatformDB_TEST` is absent. No database, login, permission, migration, or data change was performed.
- Added a reviewed least-privilege permission matrix plus no-op-by-default SQLCMD templates for principal mapping, isolated database creation, versioned schema/configuration deployment, read-only validation, and explicit test-database cleanup. Added a guarded PowerShell integration-test runner; all write paths require explicit approval.
- Hardened SQL integration-test guards and removed a stale direct-table Owner-count helper. The Release integration project build passed; all 3 mutation tests skipped because approval and test-target variables were absent.
- Updated security, database dependency, test-plan, known-issue, and v1.5 deployment evidence. Production and FROZEN approval remain false; no existing privileges were revoked.

## Post-migration Development validation recheck — 2026-11-21

- Independently verified the actual API SQL target `DEV-PC\SQLEXPRESS / KlopPlatformDB`: all 20 mapped procedures are present; all nine auth/session signatures match the Dapper call contracts; the baseline read-only dependency preflight returned no missing objects.
- Confirmed 17 required/optional runtime configuration rows have expected type/storage metadata without reading values. The API starts and readiness succeeds.
- Reconfirmed the runtime security blocker: `klop_app_runtime` has no members, only 1/20 mapped procedures is explicitly granted to it (0/9 new auth/session procedures), and the Integrated Security API identity is in `db_owner` and `db_ddladmin`. No migration, grant, or data mutation was run.
- Release build passed (0 warnings/errors); 17 backend unit tests passed; 3 SQL mutation tests skipped. Frontend build passed with two non-fatal Rollup/Zod warnings, 14 unit tests passed, and the single Playwright test passed using a test-only mocked 401.
- Active HTTPS API health/readiness, OpenAPI (15 operations), JWKS public-only shape, SQL-backed organization types (7 rows), expected auth denials/validation, and CORS checks passed. Browser HTTPS login page, public cross-origin read, and unauthenticated protected-route redirect passed. Positive authentication, protected business flows, tenant isolation, mutation/audit, replay, and sensitive-log scans remain NOT RUN/BLOCKED.

## Post-migration Development validation — 2026-11-21

- Revalidated the actual Development target `DEV-PC\SQLEXPRESS / KlopPlatformDB` with read-only SQL: all 20 mapped Stored Procedures exist; all nine v1.5 auth/session signatures match; `klop_app_runtime` has no members and 0/9 required auth/session grants.
- Confirmed the current Integrated Security caller has effective EXECUTE on all 20 mapped procedures but is in `db_owner` and `db_ddladmin`; this remains a least-privilege blocker. No migration, grant, or data mutation was run.
- Re-ran Release backend build/tests (0 warnings/errors, 17 unit tests passed, 3 SQL tests skipped), restored frontend dependencies from the lockfile, and passed frontend build, 5 unit tests, and one mocked-denial Playwright test.
- Started Development API on a temporary local port and passed liveness/readiness, Swagger/OpenAPI, JWKS public-key shape, SQL-backed organization type read, CORS preflight, correlation fallback, invalid-payload validation, and unauthenticated denial probes.
- Updated endpoint, SQL dependency, security, and full-stack validation reports. Positive auth/session, tenant authorization, audit, concurrency, and browser HTTPS session tests remain blocked/not run; no Production/FROZEN approval is implied.

## v1.5 post-deployment catalog verification — 2026-11-21

- After the user reported running the standalone migration, read-only verification against `DEV-PC\SQLEXPRESS / KlopPlatformDB` found all nine procedures present and all nine parameter signatures matching.
- Runtime readiness remains blocked: 0/9 explicit EXECUTE grants to `klop_app_runtime` passed, and the role has no members. No grants or functional auth/session tests were run.
- Do not enable API auth/session traffic until least-privilege runtime identity/grants and guarded end-to-end testing are complete.

## v1.5 migration readiness recheck — 2026-11-21

- Re-ran the read-only preflight against the actual backend-configured Development target (`DEV-PC\SQLEXPRESS / KlopPlatformDB`): 139 findings, zero DDL blockers; the runtime-role gate remains blocked.
- Ran the read-only post-deployment verifier; it confirmed all nine procedures are still absent, with no DDL executed. Clarified its output to mark missing procedures separately from signature mismatches, while failing closed in either case.
- Added a standalone SQLCMD-mode migration containing the nine additive procedure definitions directly, with collision checks, transactional application lock, and final object verification. It has not been executed; use it instead of, never together with, the include-based wrapper.
- Classified the additive SQL artifact as conditionally ready for DBA-approved Development deployment; the target's isolation/backup status and runtime least-privilege setup remain unconfirmed, and the migration was not executed.

## Full-stack Development integration validation — 2026-11-20

- Re-ran restore, Release build, and tests: restore/build passed, 17 unit tests passed, and 3 guarded SQL integration tests were skipped.
- Rechecked the Development SQL catalog using a read-only query; all nine v1.3 auth/session procedures remain absent. No migration or write procedure was run.
- Started the Development API and verified readiness, the live OpenAPI inventory (15 operations), the SQL-backed organization-type read (7 rows), correlation response headers, and safe unauthenticated denials.
- Browser-origin verification found that the active Vite server uses HTTP while the SQL-configured API origin is HTTPS; credentialed browser API calls are blocked by CORS until the portal is served from the configured HTTPS origin.
- Refreshed the frontend OpenAPI artifact from the live backend contract and aligned the tenant-create request to its slashless route.
- Smoke-tested the frontend's HTTPS Vite configuration on an alternate local port with a temporary .NET development certificate; exact-origin browser CORS remains blocked by the existing HTTP server on the configured port.
- Recorded full-stack results, blockers, module mapping, and exact remediation in the frontend [integration validation report](../klop-next_ui/docs/INTEGRATION_VALIDATION.md).
- No Production deployment, database migration, or frozen-baseline change was performed.

## v1.5 auth/session SQL readiness review — 2026-11-20

- Reviewed the v1.5 SQLCMD wrapper against the unchanged v1.3 procedure source and observed Development catalog. The source dependencies are schema-compatible based on read-only metadata; all nine target procedures remain absent.
- Added read-only preflight and post-deployment signature/permission validation scripts plus DBA deployment, backup/recovery, and rollback instructions. The migration and grants were not executed.
- Recorded the runtime-identity blocker: the observed SQL inspection caller is elevated (`db_owner`/`db_ddladmin`), `klop_app_runtime` has no members, and the existing grant template is incomplete for the API's 20 mapped procedures.
- Authentication/session behavior, least-privilege runtime access, and integration/concurrency tests remain BLOCKED or NOT RUN; no operational-authentication claim is made. Frozen SQL artifacts remain unchanged.

## Development backend validation — 2026-11-20

- Restored, built, and tested the solution: Release build passed with 0 warnings/errors; 17 unit tests passed and 3 guarded SQL tests were skipped.
- Started the API using the Development launch profile; health/readiness, Swagger/OpenAPI, JWKS, and the SQL-backed organization-type read passed. OpenAPI reported all 15 API operations.
- Verified unauthenticated access denials and invalid-request handling without executing write workflows. Positive auth/session and tenant-write flows remain blocked pending an isolated `_TEST` database.
- Read-only SQL catalog checks found 11 of 20 mapped procedures present and all nine v1.3 auth/session procedures absent. Added a fail-closed v1.5 migration proposal that reuses the unchanged v1.3 DDL; it was not executed.
- Removed the unused `Sql:CommandTimeoutSeconds` Development setting; the command timeout is sourced from SQL configuration.
- Added endpoint results, database dependency evidence, and a known-issue register. No frozen/historical SQL baseline was modified.

## Development OpenAPI UI — 2026-11-20

- Added Development-only Swagger UI using the existing ASP.NET Core OpenAPI generator and the current launch profile.
- Documented JWT Bearer security per authorization metadata, endpoint response schemas and statuses, and SQL readiness without changing API or security behavior.
- Registered the existing runtime settings instance as `IPasswordPolicy` so the registration validator can be constructed at startup.

## KLOP-PLATFORM-BACKEND-1.4-DRAFT — 2026-11-20

- Ported the v1.3 four-project API reference to .NET 10 / `net10.0`.
- Added Application repository/runtime ports and use-case services; infrastructure uses explicit stored procedure mappings.
- Implemented FluentValidation endpoint filtering, tenant permission authorization handler, RFC 9457-compatible error responses, request correlation, and SQL-safe error mapping.
- Added Serilog structured console logging, HTTP/SqlClient OpenTelemetry instrumentation, SQL readiness checks, OpenAPI in Development, security headers, trusted proxy configuration, and Docker packaging.
- Moved tenant type and registration enablement lookup to SQL master/configuration procedures instead of API hardcoding.
- Added idempotent v1.4 Development-only proposals for SQL command timeout and per-IP auth rate limit configuration, plus a reviewed EXECUTE grant template for the existing tenant type read procedure.
- Added architecture, project structure, database, security, logging, testing, API, configuration, and deployment documentation.
- Verified original v1.3 and frozen checkpoint artifact checksums before porting. No historical or FROZEN source was changed.
- Revalidated .NET restore and Release build (0 warnings/errors), and ran unit tests (13 passed); all 3 SQL integration tests were skipped. SQL integration and migration execution remain NOT RUN.

## Source baseline: KLOP-PLATFORM-INTEGRATED-1.3-DRAFT

The original v1.3 package remains available under `document/KLOP_PLATFORM_INTEGRATED_v1.3_DRAFT` and is a DRAFT reference, not a deployed baseline.
