# KLOP Platform Backend Architecture & API Audit

**Audit mode:** Read-only; no source, database, seed, grant, deployment, or route changes were made.  
**Workspace:** `klop-next-platform-api`  
**Audit date:** 2026-11-22  
**Assessment:** Current code is the KLOP Platform backend, not KLOP CORE. Git branch/commit identity could not be verified because this workspace has no Git metadata.

## 1. Executive Summary

The solution is a .NET 10 layered backend with API, Application, Domain, and Infrastructure projects. Runtime persistence is Dapper/SqlClient through a repository port and named stored procedures; the inspected production source has no EF Core, inline application SQL, or direct table DML. Minimal APIs are used consistently and are architecturally valid here: business use cases are mostly delegated to Application services, and no controller rewrite is required merely because the endpoints are Minimal APIs.

The main structure concern is concentration: all HTTP route definitions and handler lambdas are in the 633-line `Program.cs`, mixed with bootstrapping, dependency registration, auth configuration, middleware, and OpenAPI setup. Extracting endpoint mapping into small feature modules is a low-risk maintainability improvement, not a prerequisite architecture replacement.

Two blockers matter more than broad restructuring:

1. **Login is incompatible with the supplied existing credential encoding.** `PasswordCodec.Verify` accepts only `pbkdf2-sha256$rounds$salt$digest`; the reported Development credential format is period-delimited (`rounds.salt.digest`). Given the supplied account/hash metadata, verification returns `false` at the format gate. `AuthenticationService.Login` then returns no session and records a failed attempt for an existing candidate; `/api/v1/auth/login` maps that result to HTTP 401 `INVALID_CREDENTIALS`. This is a source-level diagnosis conditioned on the supplied database evidence; this audit did not query the database or make a login request.
2. **The checked-in Development validation record describes an unsafe SQL runtime identity.** `docs/DATABASE_DEPENDENCIES.md` reports the API Integrated Security principal as `dbo`/SQL Server `sysadmin`, while `klop_app_runtime` has no members and missing auth/session grants. Those are prior repository-recorded live findings, not re-queried in this audit. Do not use that evidence as least-privilege readiness.

**Recommendation:** Do not start manual login testing with the affected Development accounts yet. First reconcile the legacy hash format from an authoritative source and add deterministic verifier tests; avoid repeated real login attempts because the code records failures and may trigger lockout. Also resolve the Development runtime-identity issue before enabling or exercising successful auth/session operations. A wholesale backend restructure is **not** needed before those focused fixes, and should not be used to obscure the login diagnosis.

## 2. Repository and Solution Inventory

### Identity and boundary

- Root solution: `KLOP.Platform.sln`.
- Product identity is supported by `README.md`, `STATUS_README.md`, `VERSION_MANIFEST.json` (`KLOP-PLATFORM-BACKEND-1.4-DRAFT`), project names/namespaces, and Development settings targeting the Platform database.
- The Development appsettings file names `KlopPlatformDB`; the repository's 2026-11-21 validation record names the configured Development SQL target and reports catalog checks. This audit did not open a SQL connection, inspect the current process identity, or verify those live observations again.
- **Git branch, commit, and cleanliness: NOT VERIFIED.** `git rev-parse --show-toplevel` failed because no `.git` metadata is present in the workspace.
- The current solution contains no KLOP CORE project or CORE namespaces. This establishes that the opened workspace is the Platform backend by local solution evidence; it does not independently establish a remote branch or deployment identity.

### Projects and dependency graph

| Project | Responsibility | References / notable dependencies |
|---|---|---|
| `src/KLOP.Platform.Api` | ASP.NET Core host, routes, authentication, authorization, middleware, OpenAPI | References Infrastructure in its project file; uses Application and Domain types in `Program.cs` through transitive project references |
| `src/KLOP.Platform.Application` | Use-case services, contracts, ports, validators, password/token primitives | References Domain; FluentValidation and logging abstractions |
| `src/KLOP.Platform.Domain` | Data/model types (`Models.cs`) | No project/package dependencies |
| `src/KLOP.Platform.Infrastructure` | Dapper repository, SQL connection factory, SQL-loaded runtime settings | References Application; Dapper, Microsoft.Data.SqlClient, Azure Identity/Key Vault |
| `tests/KLOP.Platform.UnitTests` | xUnit security/validation/OpenAPI tests | References API and Application |
| `tests/KLOP.Platform.IntegrationTests` | SQL workflow tests with persistent-write guard | References Infrastructure; tests require an explicitly approved disposable database |

### Repository folders

```text
KLOP.Platform.sln / Directory.Build.props / README.md / VERSION_MANIFEST.json
src/                         four production projects (API, Application, Domain, Infrastructure)
tests/                       unit and SQL integration projects
database/                    migrations, security templates, test templates, read-only validation scripts
sql/                          versioned/reference SQL and deployment/validation artifacts
docs/                         architecture, API, database, security, operations, test evidence
deploy/                       local supporting service configuration
scripts/                      build/static validation helpers
session-state/                local session artifacts (not production source)
.vs/, bin/, obj/              Visual Studio/build artifacts; excluded from architecture inventory
```

`Directory.Build.props` sets `net10.0`, nullable references, implicit usings, latest language version, and warnings-as-errors. The API project is an ASP.NET Core Web SDK project. No Entity Framework package/context was found in the inspected `src` or test project files.

## 3. Current Architecture Diagram

```text
HTTP clients / SPA
		|
		v
KLOP.Platform.Api (Program.cs: bootstrap, middleware, 15 /api/v1 route handlers)
		|                     |
		|                     +--> Authentication / authorization / validation / token / cookie services
		v
KLOP.Platform.Application (AuthenticationService, TenantManagementService, ports, validators)
		|                         |
		|                         +--> KLOP.Platform.Domain (simple data models)
		v
IPlatformRepository
		|
		v
KLOP.Platform.Infrastructure (KlopRepository + Dapper + SqlConnectionFactory)
		|
		v
SQL Server stored procedures (IAM / TEN / MST / CFG; procedure-owned transactions and audit)
		|
		+--> SQL-backed configuration, account/session/tenant/permission/audit data
```

The concrete API composition root wires Infrastructure to Application ports. Application does not reference SQL Server or Infrastructure. Runtime SQL configuration is loaded at startup by `RuntimeSettings.Load`; SQL secrets are represented by Key Vault references in the configuration design. The existing architecture documentation says the procedures own write transactions; the audit did not execute or inspect live stored procedure bodies.

## 4. `Program.cs` Audit

`src/KLOP.Platform.Api/Program.cs` contains 633 lines and all route mappings. Classification:

| Concern | Present? | Evidence / assessment |
|---|---|---|
| Application bootstrap and environment validation | Yes | Lines 22–30; permits only Development/Production and validates AllowedHosts |
| SQL-backed startup configuration and key loading | Yes | Lines 62–74; reads runtime settings and signing material before building the app |
| Service registration / DI | Yes | Lines 76–107, 109–183; repositories, use cases, validators, key material, health, auth, telemetry, limiter |
| Middleware pipeline | Yes | Lines 185–297; correlation/log context, exception mapping, status pages, headers, HTTPS, CORS, limiter, auth |
| Authentication / authorization setup | Yes | Lines 129–183; JWT issuer/audience/signature/lifetime/algorithm; session validated against SQL; tenant permission handler registered |
| Swagger/OpenAPI setup | Yes | Document/operation transformers lines 42–47; OpenAPI and Swagger UI mapped only in Development, lines 292–296 |
| Endpoint mapping | Yes | Health/JWKS lines 298–324; all `/api/v1` routes lines 326–629 |
| Business logic in handlers | Limited, but some orchestration is inline | Handlers extract identity, apply route-level guards, call services/repository. Permission and request-flow orchestration remains in the route lambdas; use-case rules are mostly in Application/SQL procedures |
| Database query or stored-procedure execution in handlers | No | Program injects repository/services; Dapper and procedure dispatch are in Infrastructure |
| Request validation | Yes | `ValidationFilter` is attached to `/api/v1`; validators are registered from the Application assembly. Route IDs/role code also have manual guards |
| Exception handling | Yes | Lines 208–249 map known SQL/business failures and return generic safe errors; request cancellation is rethrown |
| Secret/configuration handling | Yes, with environment-specific behavior | Bootstrap settings in appsettings/env; SQL runtime values loaded from CFG; production key references resolved using Key Vault; values/secrets not included in this report |
| Development bootstrap/seeding | No seeding found | No seed or database mutation is invoked by Program. Development has Development-only Swagger and may use the documented ephemeral signing key path |

### Minimal API judgment

The current Minimal APIs are not inherently an architectural defect. The majority are short adapters: bind input, obtain identity, call an Application service/repository, and shape the response. Group filters, authorization metadata, validation, summaries, tags, and response metadata are used. Retain the Minimal API contract and extract only the mapping/handlers into named endpoint modules when improving `Program.cs` separation. Controllers are an option if a feature becomes large or team conventions require them, but converting every endpoint to controllers would add churn without correcting the observed authentication blocker.

## 5. Endpoint Inventory

See [ENDPOINT_INVENTORY.md](ENDPOINT_INVENTORY.md) for all 15 `/api/v1` operations and three infrastructure routes, including authentication, handler/service, validation, stored procedure dependencies, and source-status caveats.

No duplicate route mapping was found in the current `Program.cs`. All API routes are grouped under `/api/v1`; auth and tenant groups use tags and summaries. The route set contains no password-reset endpoint. No route is removed, renamed, or proposed for replacement in this audit. The latest checked-in API report states 15 OpenAPI operations were observed on 2026-11-21; OpenAPI was not regenerated by this audit.

## 6. Architecture Assessment and Deviations

### Conforms

- API use cases are generally routed through Application services; API handlers do not execute SQL.
- Application depends inward on Domain and ports; Infrastructure implements the repository port.
- `KlopRepository` uses typed Dapper parameters and `CommandType.StoredProcedure`; repository methods name versioned procedures.
- The inspected API source has no EF Core usage or inline direct SQL/table DML. There is no reason to migrate to EF Core; stored-procedure mapping remains the persistence design.
- Tenant permission checks are re-evaluated in SQL; actor/user identity is read from the validated JWT rather than the request body.
- Infrastructure creates encrypted SQL connections and restricts certificate-trust bypass to Development. Runtime values have type/range validation.

### Deviations / maintainability observations

1. **Composition-root concentration (medium).** Endpoint declarations and route-specific orchestration occupy Program.cs lines 298–629 alongside host setup. This makes endpoint-specific testing and review harder as routes grow. The separation issue can be fixed without changing routes by moving route groups to endpoint modules.
2. **Implicit project dependency (low/medium).** `KLOP.Platform.Api.csproj` explicitly references Infrastructure only (line 3), while Program imports API, Application, Domain, and Infrastructure namespaces. SDK project-reference transitivity makes this build, but obscures the API's direct compile-time dependency on Application. Add an explicit Application reference only as a small dependency-graph clarification in a later approved change.
3. **Thin Domain layer (low).** Domain currently contains mutable DTO/data models, with no explicit entities/value objects/business rules. This is not a reason to create empty layers; keep policy in current Application/SQL contracts unless genuine domain invariants justify richer domain types.
4. **No measured coverage evidence in this audit.** Current tests are concentrated in password/token/validation and OpenAPI metadata; no ApplicationService login-flow or endpoint contract tests were found. No coverage report was generated, so percent coverage is **NOT VERIFIED**.
5. **Email delivery follows committed registration (medium reliability).** `AuthenticationService.SendVerificationSafely` logs and suppresses delivery exceptions after the database operation commits (`PlatformServices.cs:89–103`). Resend exists, but an accepted registration can lack delivered email without synchronous failure; the existing architecture docs also identify the lack of an outbox/reconciliation flow.

No business policy was found in SQL-free API controller classes because the solution has no controllers. Minimal route handlers do contain HTTP orchestration and permission checks; this is a separation boundary to improve selectively, not a finding that every endpoint must be moved to MVC.

## 7. Authentication and Login Diagnosis

### Source trace

```text
POST /api/v1/auth/login                       Program.cs:386–404
  -> AuthenticationService.Login             PlatformServices.cs:49–71
	 -> IPlatformRepository.GetLoginCandidate(normalized email)
		-> KlopRepository.GetLoginCandidate   KlopRepository.cs:65–66
		   -> iam.usp_GetLocalLoginCandidate  sql/100_auth_session_delta.sql:6–14
	 -> PasswordCodec.Verify                 Security.cs:22–39
	 -> if candidate exists but password mismatch:
		RecordLoginFailure                    PlatformServices.cs:59–63
		-> iam.usp_RecordLocalLoginFailure
	 -> if allowed:
		CreateSession + SQL audit             PlatformServices.cs:66–70
		-> iam.usp_CreateAuthSession
  -> null session -> HTTP 401 INVALID_CREDENTIALS   Program.cs:392–398
```

The SQL login-candidate procedure selects the stored `PasswordHash` and account state; the source does not normalize/re-encode the hash in SQL. Verification is in the Application layer.

### Root-cause diagnosis for the reported Development account

- The user-supplied DB observation is that the two active, verified accounts have a 76-character hash in `100000.saltBase64.hashBase64` form. This user-supplied database observation was not independently queried during this audit.
- `PasswordCodec.Verify` splits only on `$` and requires exactly four components with component 0 equal to `pbkdf2-sha256` (`Security.cs:27–30`). It therefore rejects the reported period-delimited representation before deriving/comparing a digest.
- `AuthenticationService.Login` interprets that false result as a password mismatch. With a non-null candidate, it calls `RecordLoginFailure`, then returns `null` (`PlatformServices.cs:53–63`). The route returns the observed `INVALID_CREDENTIALS` 401 (`Program.cs:392–395`).
- The exact user-specific failure is established **if** `usp_GetLocalLoginCandidate` returns the reported existing value. The account flags/roles/hash length and exact observed HTTP response come from the case evidence supplied in the request, not from this audit's own database/network test.
- The format prefix alone does not establish the old derivation algorithm, digest size, or exact byte encoding. Do not assume it is compatible with the new PBKDF2-SHA256 encoding, and do not hardcode a password or bypass the verifier.
- Login does not load or authorize roles before password verification. The supplied `SUPER_ADMIN` / `PLATFORM_SUPPORT` roles do not correct the hash-format mismatch. This API currently exposes no platform-scoped permission endpoint; tenant permissions are checked from current database state.
- Repeating real failed login attempts can increment the database failure counter and potentially lock an account. Do not use the affected accounts as a format-probing mechanism.

### Other auth surfaces

Registration uses the current PBKDF2-SHA256 writer; email verification and refresh secrets are random and only hashes are passed to SQL. Access JWTs use RSA-SHA256, include subject/session/JTI claims, and every authenticated request validates the SQL session. Refresh rotation/replay and logout are repository/SP paths; refresh uses an HttpOnly/Secure/SameSite Strict cookie and checks configured Origin. Lockout state is consulted in Application and failure counting is delegated to SQL. Authentication/authorization services and the repository are registered in DI.

Role/permission truth is not embedded in JWT role claims; the tenant permission handler checks the current database permission through `iam.usp_ValidateSessionAccess`. The current exposed API set is tenant-scoped only; platform-scope operations and platform role authorization are not exposed in this solution. Register/verification, refresh, session lifecycle, and role logic are source-present, but successful end-to-end operation is not established by this audit.

## 8. Database Integration Review

### Source-code evidence

- Development bootstrap settings are in `src/KLOP.Platform.Api/appsettings.Development.json`; its database name is `KlopPlatformDB` and authentication is Integrated Security. The report intentionally omits connection-secret values; no password/connection string secret is needed for this identity mode.
- `SqlConnectionFactory` requires encryption and restricts `TrustServerCertificate=true` to Development (`SqlConnectionFactory.cs:6–31`). The Development file enables the explicitly Development-only bypass; Production defaults it off.
- `RuntimeSettings.Load` reads SQL-backed settings through `cfg.usp_Configuration_GetByKey`, validates types/ranges/HTTPS origins, and holds values in a singleton for the process lifetime (`RuntimeSettings.cs:34–132`).
- `KlopRepository` maps repository methods to stored procedures with typed parameters and command timeout; no direct SQL, table DML, EF Core, or inline dynamic SQL was found in the application source. Transactions and audit writes are designed to live within stored procedures.
- API business-data repository coverage includes auth/session, tenant/membership/role, master-data, and configuration reads. Runtime database access includes stored-procedure invocation rather than direct table access.

### Database facts vs unverified facts

- **Source verified:** local Development configuration targets `KlopPlatformDB`; repository and settings use procedure contracts; no database was created or modified by this audit.
- **Recorded in checked-in reports, not re-queried now:** the 2026-11-21 repository validation reports 20 mapped procedures present, 9/9 auth/session signatures matching, SQL readiness and master-data read passing, and the Development API caller as `dbo`/SQL Server `sysadmin`. It also reports `klop_app_runtime` has no members and missing explicit grants for auth/session operations. See `docs/DATABASE_DEPENDENCIES.md:7–13, 35–43` and `docs/KNOWN_ISSUES.md:7–17`.
- **Not verified in this audit:** current live catalog, procedure bodies, effective permissions, current process identity, database rows/roles, audit rows, or positive login/session behavior.
- **No mutations:** no DDL, seed, grant, user/password/role change, login attempt, integration fixture, database test, or Production operation was performed.

Stored procedures remain the correct persistence mechanism for this solution's frozen database contract. Do not migrate operations to EF Core or change the `KLOP-PLATFORM-DB-FOUNDATION-1.1 FROZEN` baseline as part of this audit.

## 9. Security Findings and Configuration Review

A dedicated source/config security-review agent reported **no exploitable source/config vulnerabilities** in the reviewed backend. This is a code review result, not a penetration test. The separate Development runtime-identity concern below is reported from existing dated repository validation evidence and is not re-verified by that review or this audit.

### Controls observed in source

- JWT bearer validates issuer, audience, signing key, lifetime, and RS256; `MapInboundClaims=false`; only short subject/session/JTI claims are issued.
- SQL session validation runs for bearer requests; tenant permission checks are database-backed.
- CORS is restricted to the configured origin, methods, and headers; credentials are enabled only with that origin. Auth routes have a per-IP fixed-window limit; configured proxy headers are trusted only from configured proxies.
- HTTPS redirection and request-size limits are configured; HSTS is Production-only. Swagger/OpenAPI UI is Development-only.
- SQL requires encryption; Production rejects `TrustServerCertificate=true`. Production requires explicit AllowedHosts, Key Vault signing-key reference, and TLS SMTP.
- Logs omit request/response bodies and SQL parameter values; errors return generic safe details. Readiness output omits dependency details.

### Security and operational risk

| ID | Severity | Evidence | Impact | Recommendation |
|---|---|---|---|---|
| SEC-01 | P0 — Critical/blocker | Development app uses Integrated Security (`appsettings.Development.json:2–6`); the checked-in 2026-11-21 report says the live API principal mapped to `dbo`/`sysadmin`, and `klop_app_runtime` was empty (`docs/DATABASE_DEPENDENCIES.md:10–12`, `docs/KNOWN_ISSUES.md:15–17`) | If that recorded state remains current, API database calls execute under excessive privilege and least-privilege runtime readiness is false. Positive auth/DB flows may appear to work under the elevated caller but are not proof of the intended runtime grants. | DBA/security-owner verify current identity and replace with the approved least-privilege runtime principal and full minimum EXECUTE grants. Do not change grants or identity without approval; no DB check/change was made here. |
| SEC-02 | P1 — High (availability / auth correctness) | Current verifier format gate (`Security.cs:22–35`) vs user-supplied credential-format evidence; auth failure handling (`PlatformServices.cs:53–63`) | Existing eligible credentials in the reported format are rejected; each candidate mismatch records a failed login and may cause account lockout. | Establish legacy derivation details from approved source/data contract; add deterministic verifier compatibility tests before real login retry. Do not bypass auth or modify credentials. |
| SEC-03 | P2 — Medium (production readiness) | Rate limiter is in-process fixed-window by remote address (`Program.cs:109–127`); docs list distributed limiting as open (`SECURITY_DESIGN.md:39`) | In a multi-instance deployment, limits are not shared across instances. | If production scales out, decide on a shared limiter or enforce equivalent edge throttling; retain per-IP policy and trusted proxy configuration. |
| SEC-04 | P2 — Medium (operational reliability) | Email sender failure is logged and suppressed after the database operation (`PlatformServices.cs:89–103`); no outbox is in scope | A user may receive an accepted response without email delivery; delivery can require manual resend. | For a future reliability increment, add an approved outbox/reconciliation approach or operational alerting without changing the existing response/privacy contract. |

The source-config review found controls implemented but did not prove Production identity, key retrieval/rotation, effective permissions, SMTP delivery, or deployed proxy configuration. No secrets, hashes, tokens, or connection-string secrets are included in these deliverables.

## 10. Proposed Target Architecture

Keep the four current projects and current API contract. Extract only feature-specific endpoint mapping and shared host setup; do not introduce a mediator, ORM, new database abstraction, or extra project without a concrete requirement.

```text
KLOP.Platform.sln
|
+-- src/
|   +-- KLOP.Platform.Api/
|   |   +-- Endpoints/                 # AuthEndpoints, TenantEndpoints, MasterDataEndpoints
|   |   +-- Middleware/                # shared error/correlation middleware if extracted
|   |   +-- Extensions/                # service/middleware/OpenAPI registration
|   |   +-- Program.cs                 # bootstrap + composition root + endpoint module registration
|   +-- KLOP.Platform.Application/
|   |   +-- Authentication/            # existing AuthenticationService/contracts/validators
|   |   +-- Tenants/                    # existing TenantManagementService/contracts/validators
|   |   +-- Ports/                      # IPlatformRepository and external service ports
|   +-- KLOP.Platform.Domain/           # keep existing models; add rules/value objects only when justified
|   +-- KLOP.Platform.Infrastructure/
|       +-- Persistence/                # KlopRepository, SqlConnectionFactory, RuntimeSettings
|       +-- Security/                   # Key Vault/keys if ownership is later moved
|       +-- Services/                   # SMTP adapter
|
+-- tests/
	+-- KLOP.Platform.UnitTests/        # codec legacy-format, auth service, endpoint/contract tests
	+-- KLOP.Platform.IntegrationTests/ # guarded tests only against approved disposable _TEST DB
```

These are logical grouping suggestions, not a required file move. A future mapping-module extraction must preserve all existing paths, methods, JSON envelopes, status/error codes, cookies, JWT claims, permission checks, SQL parameters, and stored procedure calls.

## 11. Refactoring Plan

Detailed ordered actions and compatibility gates are in [REFACTORING_PLAN.md](REFACTORING_PLAN.md). Recommended order:

1. Resolve the legacy hash specification and add verifier fixtures/unit tests; no database mutation or login retry.
2. Approve and verify the Development least-privilege SQL runtime identity and grants outside this read-only audit; only then plan isolated positive login/session testing.
3. Add unit tests around authentication service failure/success orchestration with fakes, then API contract tests that do not access SQL.
4. Extract route definitions into endpoint modules mechanically, preserving every route and endpoint metadata; no controller conversion requirement.
5. Add only justified Application test seams/validators and improve docs/coverage evidence; avoid database baseline changes.
6. Only under DBA/security approval, execute persistent SQL workflows against a disposable `_TEST` clone and record audit/permission/session behavior. Never point them at Development or Production.

Risk and rollback notes are in the separate plan. This audit itself performs none of these changes.

## 12. Build and Test Evidence

| Check performed in this audit | Result | Scope / caveat |
|---|---|---|
| `dotnet restore KLOP.Platform.sln` | PASS | All projects reported up-to-date; no project/source manifests changed |
| Visual Studio solution build (`run_build`) | PASS | Build successful; no database connection or deployment |
| Unit test discovery | 17 found | `KLOP.Platform.UnitTests` |
| Unit tests (`run_tests`, UnitTests project) | PASS: 17 passed, 0 failed | Security/validation and OpenAPI transformer tests only; does not validate real login/session/database behavior |
| SQL integration tests | NOT RUN | Three tests are persistent-write SQL workflows. The explicit test opt-in/target variables were absent; they were not run to honor the no-data-mutation constraint |
| API runtime/OpenAPI/database smoke test | NOT RUN in this audit | Starting the API reads environment SQL configuration; prior smoke evidence is recorded in repository docs dated 2026-11-21, not repeated here |
| Line/branch coverage | NOT VERIFIED | No coverage collection/report was run or inspected in this audit |
| API contract compatibility | Source inventory only | Current code maps 15 versioned API operations; prior docs report 15 OpenAPI operations. No route was changed and no current live OpenAPI document was generated |

Before this audit's SQL/test checks, mutation opt-in environment variables were checked by name only and were absent. No connection to `KlopPlatformDB` or any `_TEST` database was made.

## 13. Risk Register

| ID | Priority / severity | File and lines | Evidence | Impact | Recommendation | Change risk |
|---|---|---|---|---|---|---|
| KLOP-AUD-01 | P0 — Critical/blocker | `appsettings.Development.json:2–6`; dated evidence `docs/DATABASE_DEPENDENCIES.md:10–12` | Integrated Security config; prior live report says API caller was `dbo`/`sysadmin`, runtime role had no members/missing grants. Not rechecked now. | Excessive privilege; cannot establish runtime least privilege; successful behavior under this identity is misleading. | Verify current Development identity and complete approved minimum EXECUTE grants before enabling successful auth workflows. | Medium/high: operational DBA/security change; do not alter baseline or grants without approval. |
| KLOP-AUD-02 | P1 — High | `Security.cs:22–35`; `PlatformServices.cs:49–63`; `KlopRepository.cs:65–68`; `Program.cs:386–398` | Verifier accepts only the new `$`-delimited encoding; supplied existing-data evidence uses a different dotted format; mismatch returns the observed 401 path and records failure. | Existing accounts cannot log in; repeated attempts can lock them. | Confirm old KDF from authoritative source, implement explicit version compatibility with fixtures, and preserve secure constant-time comparison. | Medium: authentication-sensitive; unit test vectors first, no DB rewrite. |
| KLOP-AUD-03 | P1 — High / validation gap | `tests/KLOP.Platform.IntegrationTests/DatabaseWorkflowTests.cs:11–60,72–140`; `docs/KNOWN_ISSUES.md:7–13` | Three SQL workflow tests persist writes and are guarded; successful auth/session and effective runtime-grant behavior are not verified. | No proof of login/session success, tenant isolation, audit, concurrency, or least-privilege runtime behavior. | After identity approval, use only a disposable `_TEST` database and approved runner; never use the live Development DB for mutation tests. | High: persistent data/permission operations; tightly gated. |
| KLOP-AUD-04 | P2 — Medium | `Program.cs:298–629` | All health, master, auth, and tenant endpoint declarations are in the 633-line composition root. | Endpoint-level review/testing and future changes become harder; host concerns and feature mappings grow together. | Move route maps to small auth/tenant/master endpoint modules without altering route metadata or contracts. | Low/medium: mechanical move with route/OpenAPI snapshot regression tests. |
| KLOP-AUD-05 | P2 — Medium | `PlatformServices.cs:89–103`; `docs/SECURITY_DESIGN.md:37–40` | Email send failures after database commit are logged and suppressed; no outbox/reconciliation is present. | Verification email may not arrive despite accepted registration; operational recovery depends on resend. | Future reliability improvement with alert/reconciliation/outbox, preserving privacy and current response contract. | Medium: workflow and delivery semantics. |
| KLOP-AUD-06 | P2 — Medium | `tests/KLOP.Platform.UnitTests` (17 tests); `tests/KLOP.Platform.IntegrationTests` | Unit suite has no AuthenticationService login-flow test; there is no measured coverage report in this audit. | Regressions in candidate/hash/failure/session orchestration may escape unit tests. | Add fake-repository/service tests for absent candidate, legacy/current hash, lockout, failure recording, and successful session; add API contract tests without SQL. | Low/medium: test-only initially. |
| KLOP-AUD-07 | P3 — Low | `KLOP.Platform.Api.csproj:3`; `Program.cs:4–8` | API directly names Application and Domain types but has only an explicit Infrastructure project reference. | Compile-time dependency intent is hidden behind transitive references. | Add explicit Application project reference as part of a controlled dependency cleanup; retain Infrastructure reference for composition. | Low: project-file-only, build/test afterward. |

## 14. Final Recommendation

The architecture is a credible layered foundation and does **not** need broad restructuring before Login testing. It does need a focused login compatibility correction and verification, plus resolution of the documented Development SQL identity/grant risk. Until then, defer manual attempts against the affected users: source explains the `INVALID_CREDENTIALS` result, and failed attempts can modify lockout/audit state. Keep any later refactor incremental and contract-preserving. Do not change routes, request/response contracts, the frozen database foundation, or user credentials as part of this audit.

**Overall status:** Structure — **usable with targeted modularity improvements**; Login compatibility — **BLOCKED by format mismatch evidence**; Development SQL least privilege — **BLOCKED per dated checked-in runtime evidence, current state NOT independently reverified**; build/unit tests — **PASS in this audit**; positive database integration — **NOT VERIFIED**; Production — **not approved by this audit**.