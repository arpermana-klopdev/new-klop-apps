# KLOP PLATFORM — Integrated Development v1.3 DRAFT

**Checkpoint source:** `KLOP-PLATFORM-DB-DEV-CHECKPOINT-1.2.1-FROZEN-20261118` (immutable).  
**Package:** `KLOP-PLATFORM-INTEGRATED-1.3-DRAFT`.  
**Status:** Source code and SQL DRAFT prepared; no deployment, .NET build, unit test, integration test, or SQL runtime validation has been performed in the user's environment.

This is **one consolidated delivery**, not staged releases. It contains SQL transaction/security tests, the complete reference ASP.NET Core backend skeleton, authentication + tenant APIs, session/refresh procedures and automated test code. The next steps are to review and validate the entire package together. The v1.1/v1.2/v1.2.1 source scripts and original frozen checkpoint are not edited or re-run.

## Contents

- `src/KLOP.Platform.Api` — minimal ASP.NET Core API routes; JWT with RSA/JWKS, runtime session validation, consistent response shape, rate limiting, SMTP verification emails, no hardcoded master IDs.
- `src/KLOP.Platform.Application` — request contracts, secure PBKDF2 password encoding, verification token hashing.
- `src/KLOP.Platform.Domain` — domain read models.
- `src/KLOP.Platform.Infrastructure` — Dapper/SqlClient Stored Procedure access; no raw table queries from API.
- `sql/` — preflight (read-only), additional audited SPs for auth/session, DBA grants template, postdeployment and invariant checks (read-only).
- `tests/` — unit tests and actual-SQL integration test harness (explicit opt-in; writes persistent disposable fixtures).
- `deploy/` — optional local Mailpit SMTP test sink (loopback only).
- `docs/API_ENDPOINTS.md`, `docs/TEST_PLAN.md`, `docs/SECURITY_REVIEW.md` and the Excel tracker.

## Running the combined package on a developer machine

1. **Keep FROZEN sources untouched.** Review `sql/010_preflight_READONLY.sql` and verify baseline objects in the existing Development database. Do **not** re-run any previous migration. Nonsecret runtime settings come from `cfg.SystemConfigurations`, not appsettings.
2. Review `sql/050_config_seed_DEVELOPMENT_REVIEW.sql`, `sql/100_auth_session_delta.sql`, and `sql/200_grants_TEMPLATE.sql`; a DBA may execute them in **Development only** after approval. The config script contains Development proposals only and **must never be run in Production**. The new procedures are additive but **not yet verified in SQL Server**.
3. Run `sql/300_postdeploy_READONLY.sql` and `sql/400_invariants_READONLY.sql`. Save all resultsets as evidence.
4. On a workstation with **.NET 8 SDK**, from package root run `dotnet restore KLOP.Platform.sln`, then `dotnet build KLOP.Platform.sln`, and `dotnet test tests/KLOP.Platform.UnitTests/KLOP.Platform.UnitTests.csproj`.
5. Configure `src/KLOP.Platform.Api/appsettings.Development.json` with the correct SQL Server and database bootstrap names; use Integrated Security or Entra identity. Review `docs/CONFIGURATION_CATALOG.md` to set `cfg.SystemConfigurations`. **No passwords, access tokens, business/runtime settings, connection-string credentials, or private keys in appsettings.**
6. Optional: `docker compose -f deploy/docker-compose.mailpit.yml up -d`, then read verification email in `http://127.0.0.1:8025`. Use HTTPS for the API and SPA.
7. Run API with `dotnet run --project src/KLOP.Platform.Api`. Review endpoints in `docs/API_ENDPOINTS.md`.
8. Use a **disposable cloned database ending in `_TEST`** for integration tests, with explicit environment opt-in shown in `docs/TEST_PLAN.md`. Never enable mutation tests against the normal Development database.
9. Save build/test logs, SQL results, and security review signoffs. Keep v1.3 DRAFT until successful review and freeze authorization.

**Note:** `Sql:Authentication=IntegratedSecurity` is appropriate only where an OS/domain identity can authenticate to SQL Server. For Azure SQL use Managed Identity/Entra. Verify TLS certificate trust for SQL (`TrustServerCertificate=false`).

## SQL ordering (for DBA review, Development only)

`010_preflight_READONLY.sql` → `050_config_seed_DEVELOPMENT_REVIEW.sql` → `100_auth_session_delta.sql` → `200_grants_TEMPLATE.sql` → `300_postdeploy_READONLY.sql` → `400_invariants_READONLY.sql`.

Each v1.3 procedure uses existing `iam`, `ten`, `aud`, `mst` tables; it does not create new tables or alter frozen schema definitions. SP definitions are CREATE OR ALTER and should not be deployed to Production without change review. App runtime access is via individually granted EXECUTE rights; deployment identity remains distinct.

## Explicit limits

- **Not an executable integration into an existing private repository**: this is a standalone reference solution intended to merge against the actual KLOP PLATFORM source after a repository-level comparison.
- OpenIddict, Microsoft Entra SSO, full OAuth/OIDC authorization-code flows, distributed session cache, email outbox/reconciliation, approval workflow, production JWKS rotation, and full frontend remain separately pending against the broader platform architecture baseline.
- There is **no SQL Server endpoint** or `dotnet` binary in this environment, so the package is not labelled PASS/production-ready.
