# Security review status — KLOP Platform Backend 1.4 DRAFT

This is a source review/status record, not a penetration test or production approval.

## Implemented controls

- SQL Server Stored Procedure-only persistence with named/typed Dapper parameters.
- PBKDF2-HMAC-SHA256 password hashes and cryptographically random, hashed verification/refresh tokens.
- RSA-SHA256 JWTs, active SQL session validation, refresh-token rotation/replay revocation, secure refresh cookie.
- SQL-driven tenant master/config lookup; database checks for current tenant membership, permissions, role scope, and last Owner.
- Key Vault secret references, SQL TLS validation, exact-origin CORS, per-IP auth rate limiting, request-size cap, HTTPS/HSTS, safe Problem Details.
- Redacted structured logging, OpenTelemetry instrumentation, SQL-authoritative audit/security events.
- Runtime grant templates avoid direct DML and broad database roles.

## Evidence obtained — 2026-11-21

- Follow-up SQL security review confirmed the actual Development API process identity maps to database principal `dbo` and is a SQL Server `sysadmin`. This is a critical runtime least-privilege blocker. No privilege was revoked or changed; the API must not be treated as least-privilege-ready.
- `KlopPlatformDB_TEST` does not exist. No login/user, database, schema, grant, migration, or fixture data was created. Guarded, unexecuted SQLCMD templates and a permission matrix are available in [SQL_RUNTIME_PERMISSION_MATRIX.md](SQL_RUNTIME_PERMISSION_MATRIX.md) and [database/testing/README.md](../database/testing/README.md).
- The integration fixture now rejects any target except `DEV-PC\SQLEXPRESS / KlopPlatformDB_TEST`, requires a non-empty approval ticket and explicit persistent-data opt-in, and validates the dedicated `KLOP_PLATFORM_TEST_RUNTIME` identity. It no longer reads application tables directly. The latest integration-project Release run built successfully; all three SQL mutation tests skipped because approval/target variables were absent.
- Baseline v1.3 and frozen checkpoint hashes matched their manifests before porting.
- `dotnet restore` completed.
- `dotnet build KLOP.Platform.sln --configuration Release` completed with 0 warnings and 0 errors; all projects target net10.0.
- `dotnet test KLOP.Platform.sln --configuration Release --no-build` completed with 17 unit tests passed; all 3 SQL integration tests were skipped without an explicitly approved disposable `_TEST` database and mutation opt-in.
- Read-only SQL checks confirmed 20/20 mapped procedures present, 9/9 auth/session signatures matching, 0/9 explicit auth/session EXECUTE grants to `klop_app_runtime`, and no role members. The current Integrated Security API caller is a member of `db_owner` and `db_ddladmin`; its effective procedure access does not prove least privilege.
- Development API health/readiness, OpenAPI, JWKS public-key shape, SQL-backed organization types, unauthenticated 401 denials, invalid login payload validation, refresh no-Origin 403, correlation-ID fallback, and CORS preflight policy were smoke-tested. The configured HTTPS SPA origin was allowed and an unapproved origin was not.
- Frontend production build, 14 unit tests, and 1 Playwright login-error test passed. The Playwright test stubs a 401 and does not exercise real credentials, session issuance, or authenticated API calls.
- Follow-up checks on the active HTTPS Development endpoints and a browser-origin public read passed. An unauthenticated `/tenants` navigation redirected to `/login`; this is not evidence of authenticated navigation or logout.
- A controlled `/health/live` request returned its supplied correlation GUID in the response and Serilog request event. No auth credentials, access/refresh tokens, or verification codes were used for log scanning; sensitive-log scanning remains NOT RUN.

## Open blockers

1. Auth/session procedure objects/signatures are present, but the runtime role is empty and only 1/20 mapped procedures is explicitly granted to it. The actual API process identity is `dbo`/`sysadmin`; authenticated success paths are not validated.
2. No approved isolated `_TEST` database is configured. No SQL functional, concurrency, cross-tenant, effective least-privilege, audit, or positive API integration test has run. Provisioning and grants require explicit approval.
3. The browser has not been run at the configured HTTPS SPA origin against the live API. API CORS preflight passed, but the default Vite server without TLS certificate environment variables is HTTP and cannot use the configured HTTPS Origin.
4. No sensitive-log scan with real auth/session operations or database audit-row verification was performed; no secret/token/password test values were sent to the live API.
5. Full OIDC/Entra SSO, signing-key rotation and overlap, distributed rate limiting, email outbox, SMTP delivery reconciliation, operational alerting/retention, and production penetration testing remain unimplemented.
6. SMTP uses the v1.3 `System.Net.Mail.SmtpClient` implementation and requires an explicit production review/replacement decision.

## Release status

**DRAFT / DEVELOPMENT READ-ONLY VALIDATED / INTEGRATION BLOCKED / NOT PRODUCTION READY.** Catalog signatures and non-mutating smoke checks do not prove authenticated behavior, least-privilege runtime security, tenant isolation, replay protection, audit outcomes, or concurrency. No Production or FROZEN approval is implied. See [TEST_PLAN.md](./TEST_PLAN.md), [SECURITY_DESIGN.md](./SECURITY_DESIGN.md), and [SQL_RUNTIME_PERMISSION_MATRIX.md](./SQL_RUNTIME_PERMISSION_MATRIX.md).
