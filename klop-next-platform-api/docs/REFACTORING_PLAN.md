# KLOP Platform Backend — Risk-Ordered Refactoring Plan

This plan follows the read-only audit in [BACKEND_ARCHITECTURE_AUDIT.md](BACKEND_ARCHITECTURE_AUDIT.md). It is a proposal only. No source, API contract, SQL object, database, user, role, or baseline was changed in the audit.

> **Execution update (2026-11-22):** The structural endpoint extraction, layer/file organization, explicit API project references, and offline route/DI regression tests have since been completed. The historical authentication-hash and SQL runtime-identity gates remain unresolved and were intentionally not changed. See [BACKEND_REFACTOR_REPORT.md](BACKEND_REFACTOR_REPORT.md).

## Goals and invariants

Preserve all existing route/method pairs, request/response JSON and envelope shape, status/error codes, cookies, JWT claims, session/role/permission behavior, SQL procedure names/parameters, database-owned transactions/audit behavior, and the frozen `KLOP-PLATFORM-DB-FOUNDATION-1.1 FROZEN` baseline. Do not create a Reset Password endpoint or use real accounts as format-probing fixtures.

## Ordered plan

### Step 0 — Stop unsafe diagnosis by repetition

- Do not repeat manual logins with the supplied Development accounts while verifier compatibility is unresolved; a candidate mismatch invokes failed-login recording and may lock the account.
- Do not run registration, login, refresh, logout, or tenant-write integration workflows against the current Development database.
- No deployment, seeding, database changes, identity/grant changes, or Production changes are part of this step.

**Gate:** Existing affected account(s) are not used in manual retries until the verifier format and safe test target are settled.

### Step 1 — Establish the credential contract and fix compatibility

- Locate the authoritative historical credential writer/specification for the reported period-delimited format. Confirm KDF, rounds, salt bytes, digest algorithm/length, Base64 rules, and whether format is versioned. Do not infer the KDF solely from string length or the `100000` field.
- Add non-secret deterministic fixture vectors to unit tests for each approved format: valid password, wrong password, malformed encoding, unsupported version/rounds, invalid salt/digest lengths. Never include a real user hash or password.
- Extend `PasswordCodec.Verify` with an explicit compatibility branch for only the verified historical format and constant-time digest comparison. Keep current writer format unchanged unless a separately approved migration requires otherwise.
- If successful verification should upgrade old hashes, design and approve that separately; this audit found no repository contract for atomically replacing a credential hash. Do not perform ad hoc DML or a seed/update.
- Add `AuthenticationService.Login` tests with fake dependencies covering candidate absent, inactive/unverified/locked, mismatch and failed-login recording, and success/session creation. These tests must not use a SQL connection.

**Gate:** Unit tests prove both old and current formats and the exact `INVALID_CREDENTIALS`/failure-record behavior. No database rows are changed.

**Risk:** Medium because password verification is authentication-critical. Change only after algorithm evidence; use test vectors, peer/security review, and compatibility tests before manual login.

### Step 2 — Resolve Development SQL identity and permissions

- Have the DBA/security owner re-check the live Development API identity and runtime-role grants. Current repository evidence (2026-11-21) says the Integrated Security caller was `dbo`/`sysadmin` and the nominal runtime role was empty/incompletely granted; current state is not reverified by the audit.
- Under explicit approval, establish the intended non-admin runtime identity and least-privilege EXECUTE permissions for the full mapped procedure set. Keep existing schemas, tables, procedures, and baseline intact; do not use broad `db_owner`/`sysadmin` as runtime authorization.
- Verify effective permissions under the actual API identity using read-only evidence before permitting auth/session success tests. Do not copy production credentials or print secret values.

**Gate:** Effective identity and complete necessary grants documented by the DBA/security owner; verified against the actual API process, not an administrator's connection.

**Risk:** High operational/database risk. This requires an approved DBA change. No SQL statements should be executed under this audit plan without explicit approval.

### Step 3 — Validate login/session end-to-end only on an approved disposable database

- Provision/use a disposable database ending `_TEST` only under explicit DBA approval; the current checked-in integration tests intentionally create persistent rows.
- Use the approved fixture runner, dedicated non-admin test identity, approval ticket, and required mutation opt-in. Never point it at `KlopPlatformDB` or Production.
- Exercise registration/verification/login/session/JWT claims/profile/tenant list/refresh rotation/replay/logout/lockout; verify SQL audit/security outcomes, effective permissions, and no secret-bearing logs. Retain evidence without storing plaintext credentials, hashes, or tokens in the report.
- Confirm whether the provided administrative roles are expected to grant any currently exposed endpoint permission; source currently has no platform-scoped protected routes.

**Gate:** Positive and negative endpoint workflows pass in isolated `_TEST`, including role/session revocation and recorded audit outcomes. Skipped tests remain NOT RUN, not PASS.

**Risk:** High because SP transactions commit; a test run writes persistent fixture data and requires explicit cleanup approval.

### Step 4 — Extract endpoint maps without changing API behavior

- Move the existing route groups from `Program.cs` into `AuthEndpoints`, `TenantEndpoints`, `MasterDataEndpoints`, and `HealthEndpoints` (or equivalent small modules), each mapping to the same route builder/prefix.
- Keep `Program.cs` as host bootstrap, configuration validation, DI/middleware, and one call per endpoint module.
- Preserve every endpoint filter, `RequireAuthorization`, permission call, summary/tag, response metadata, anonymous policy, rate-limit policy, cookie behavior, and ordering-sensitive setup.
- Do not convert to MVC controllers by default. Keep Minimal API mappings if their handlers remain small and testable.

**Gate:** Before/after route snapshot is identical for path, HTTP method, auth metadata, OpenAPI operation ID/response metadata, status codes, and JSON contract; build and tests pass.

**Risk:** Low/medium if mechanical and fully covered by endpoint metadata/contract regression tests. Avoid mixing this extraction with login or SQL changes.

### Step 5 — Clarify dependency and test boundaries

- Add an explicit `KLOP.Platform.Application` project reference to the API project if the team confirms direct API use of Application types is intended; keep Infrastructure reference for composition-root implementations.
- Add focused fake-based Application tests and API contract tests. Keep SQL integration tests separate and opt-in.
- Establish coverage collection as a separate approved CI/test change; report actual line/branch results rather than inferred coverage. Do not weaken existing mutation guards to improve coverage.
- Keep Domain types simple unless a concrete business invariant calls for an entity/value object. Do not add a generic mediator, EF Core, or additional projects solely to match a reference diagram.

**Gate:** Project dependency graph is explicit, unit tests pass offline, and all database-writing tests remain safely guarded.

**Risk:** Low for explicit project reference/test additions; low/medium if coverage infrastructure changes CI configuration.

### Step 6 — Address email delivery reliability only with a contract-preserving design

- Evaluate an outbox/reconciliation capability or operational alert/resend workflow because email sending occurs after registration commit and delivery errors are logged/suppressed.
- Preserve the anti-enumeration response contract and avoid exposing whether an account exists or delivery failed. Do not send a verification token to logs.

**Gate:** Product/security/DB review approves delivery state model and retries; tests cover delivery outage and resend without leaking account existence.

**Risk:** Medium; may require database/workflow changes and is not a prerequisite for the route-module extraction.

## Regression checklist

- [ ] All 15 `/api/v1` routes and three infrastructure routes remain mapped with identical method/path.
- [ ] API envelopes, Problem Details extensions, status codes, validation field errors, correlation IDs, and response headers remain stable.
- [ ] Public vs bearer/cookie endpoints are unchanged; authorization and tenant permission requirements remain unchanged.
- [ ] JWT issuer/audience/RS256/session checks, cookie flags, origin checks, refresh replay behavior, lockout and audit behavior are preserved.
- [ ] SP names, parameter types/lengths/output parameters, command timeouts, SQL connection policy, and procedure-owned transactions are unchanged.
- [ ] Unit tests pass without network/database; login compatibility has deterministic approved vectors.
- [ ] Integration tests run only on explicitly approved disposable `_TEST`; skipped tests are recorded as NOT RUN.
- [ ] OpenAPI contains all 15 API operations; Production still does not expose Swagger/OpenAPI.
- [ ] No changes to frozen DB foundation, Production config/resources, user data/passwords/roles, or cancelled Reset Password work.

## Audit recommendation

Proceed first with Step 1 evidence/tests and Step 2 identity verification—not a broad restructure. Do not continue manual Login testing against affected accounts until the compatibility vector is resolved and the test path is safe. Extract route modules later as a separately reviewed, low-risk structural change.