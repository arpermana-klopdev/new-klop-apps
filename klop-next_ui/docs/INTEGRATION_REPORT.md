# KLOP Platform Development Integration Report

**Run date:** 2026-11-21  
**Overall result:** **PARTIAL / BLOCKED** — the portal now calls the live Development API over trusted HTTPS, but authentication and protected business workflows cannot be positively verified until the SQL runtime identity and grants are approved.

## Latest integration recheck — 2026-11-21

- The active portal loaded at `https://localhost:5173`; its login page states that access is validated by the KLOP Platform API. The browser made a credentialed cross-origin request to `https://localhost:7041/api/v1/master/organization-types` and received HTTP 200 with 7 rows. The app attempted session restoration without a valid refresh session and received HTTP 401; `/tenants` redirected to `/login`.
- The active HTTPS API passed `/health/live`, `/health/ready`, `/swagger`, `/openapi/v1.json`, organization-type read, unauthenticated `/auth/me` and `/tenants/mine` denials, empty-login validation (400), refresh without Origin/cookie (403), and configured/unapproved CORS preflights. OpenAPI contained 15 API operations.
- Release build passed with 0 warnings/errors; backend unit tests passed 17 with all 3 database mutation tests skipped by the explicit `_TEST`/opt-in guard. Frontend build passed with two non-fatal dependency annotation warnings; 14 unit tests and 1 mocked-401 Playwright test passed.
- **Not verified:** valid registration, email verification, login/JWT, refresh rotation/replay, logout, authenticated profile/tenant listing, role enforcement, cross-tenant isolation, last-Owner protection, SQL audit rows, concurrency, or sensitive-log scanning. The SQL runtime-role gate is still blocked (empty role, 0/9 auth/session grants; current API identity is elevated). No DB mutations or grants were performed.

## Runtime and browser verification

| Check | Result | Evidence |
|---|---|---|
| Backend Development profile | PASS | Started from `KLOP.Platform.Dev`; runtime logs reported `https://localhost:7041` and `http://localhost:5041`. |
| Frontend Development server | PASS | Vite is reachable at `https://localhost:5173`; the configured localhost development certificate is trusted and valid. |
| API client configuration | PASS | `.env.development` sets `VITE_API_BASE_URL=https://localhost:7041/api/v1`; no credentials or secrets are exposed to Vite. |
| SQL readiness | PASS | `GET /health/ready` returned 200; `GET /health/live` returned 200. |
| OpenAPI | PASS | Live `/openapi/v1.json` returned 200 and publishes 15 `/api/v1` path templates, including the frontend authentication/profile routes. |
| Exact-origin CORS | PASS | `OPTIONS /api/v1/auth/refresh` from `https://localhost:5173` returned 204 with `Access-Control-Allow-Origin: https://localhost:5173` and credentials enabled. No wildcard origin was used. |
| Browser-to-API public read | PASS | The HTTPS browser fetched `GET /api/v1/master/organization-types` with credentials enabled; response was 200, `success: true`, with 7 rows. |
| Browser authorization denial | PASS | The same browser fetched `GET /api/v1/tenants/mine` without a session; response was 401 `UNAUTHORIZED`. |
| Refresh without a session | PASS (expected denial) | Browser preflight returned 204; `POST /api/v1/auth/refresh` returned 401 because no refresh cookie was present. This is not a successful refresh. |
| Correlation | PASS | Browser Axios sent `X-Correlation-Id: 3550fa38-d5cf-468e-8bf2-20aa481bc566`; the matching backend Serilog request entry included that `CorrelationId`. |
| Browser storage | PASS | The browser stored only the `klop-theme` appearance preference in local storage; no access or refresh token was stored there. |

The browser loaded the portal without TLS errors. The refresh preflight and public API read succeeded through the browser's CORS enforcement. No password, access token, refresh token, registration, or business-data mutation was sent.

## Frontend integration status

| Module | Result | Contract / limitation |
|---|---|---|
| Login, registration, email verification, refresh, logout | WIRED / POSITIVE FLOWS BLOCKED | Uses the live OpenAPI routes: `/auth/login`, `/auth/register`, `/auth/verify-email`, `/auth/resend-verification`, `/auth/refresh`, `/auth/logout`, and `/auth/me`. Login and write-capable flows were not attempted without an approved test identity/database and runtime grants. |
| Access-token handling | PASS (source/config) | Access token is held in memory; refresh is credentialed and uses the backend-managed secure HttpOnly cookie. Concurrent startup refreshes are coalesced, avoiding duplicate token rotation under React Strict Mode. |
| User profile | WIRED / BLOCKED | `GET /auth/me` is used after login; protected success requires an authorized SQL-backed session. |
| Dashboard | PARTIAL | Uses the authenticated profile and `GET /tenants/mine`; there is no aggregate dashboard/metrics endpoint. |
| Tenants | WIRED / BLOCKED | Tenant listing, creation, invitations, and organization-type lookup use the published endpoints. Only the public organization-type read was exercised; no tenant writes were made. |
| Memberships and roles | WIRED / BLOCKED | Accept/remove and role assign/revoke actions target published routes, but no member/invitation listing or role catalog endpoint exists. No mutations were attempted. |
| Permission-aware navigation | BLOCKED | The API does not publish permission discovery or role/permission listing. The UI does not hardcode business roles; backend authorization remains authoritative and a protected request was observed to return 401. |
| Master data | PARTIAL | Organization types work through `GET /master/organization-types`; no generic master-data endpoint exists. |
| Configuration | UNAVAILABLE | No portal configuration read/write endpoints are published. |
| User directory | UNAVAILABLE | No user search/list/detail/admin endpoints are published. |
| Audit/security information | UNAVAILABLE | No audit or security-event query endpoints are published. |

Unavailable areas remain explicitly unavailable in the UI; no production-path mock adapters or fabricated success responses were added. The missing endpoint inventory is also recorded in [API_DEPENDENCIES.md](./API_DEPENDENCIES.md).

## Error handling and logging

The frontend maps 400, 401, 403, 404, 409, 429, and 5xx responses to safe user-facing messages. Login rejection is distinct from an expired session; network/API-unavailable failures are handled without displaying response details, SQL errors, or stack traces. Correlation IDs are generated per Axios request and are visible in backend request logs. Backend log properties include correlation/trace identifiers and request metadata; no credentials or tokens are logged.

## Validation results

| Validation | Result |
|---|---|
| Frontend TypeScript check | PASS |
| Frontend production build | PASS (two non-fatal Rollup annotation warnings originate in Zod dependencies) |
| Frontend unit tests | PASS — 14 tests |
| Frontend Playwright | PASS — 1 test; intentionally stubs only the negative login response and does not prove authentication |
| Backend Release build | PASS — 0 warnings, 0 errors |
| Backend unit tests | PASS — 17 tests |
| Backend database integration tests | BLOCKED / SKIPPED — 3 tests require an explicitly approved disposable database ending `_TEST` |

## Authentication and SQL security blockers

**Real login: NOT RUN.** The Development database contains all 20 mapped stored procedures and the 9 auth/session procedure signatures, but `klop_app_runtime` has no members and none of the 9 required auth/session EXECUTE grants passed verification. A read-only check of all 20 mapped procedures found only `mst.usp_TenantType_GetAll` explicitly granted to the role; the other 19 grants are absent. The current Integrated Security caller is elevated (`db_owner` and `db_ddladmin`) and is not acceptable as proof of runtime least privilege. No SQL grants, schema changes, migrations, or business-data writes were made.

Before positive authentication/workflow tests, the database owner must designate a non-elevated API runtime principal, create/use its database user, and make that database user a member of `klop_app_runtime`. The runtime role needs explicit `EXECUTE` for the API's 20 mapped procedures:

- `cfg.usp_Configuration_GetByKey`
- `mst.usp_TenantType_GetAll`
- `mst.usp_OrganizationType_GetAll`
- `iam.usp_RegisterLocalUser`
- `iam.usp_ConfirmEmail`
- `ten.usp_CreateTenantWithOwner`
- `ten.usp_InviteExistingUser`
- `ten.usp_AcceptMembership`
- `ten.usp_RemoveTenantMember`
- `iam.usp_AssignTenantRole`
- `iam.usp_RevokeTenantRole`
- `iam.usp_GetLocalLoginCandidate`
- `iam.usp_RecordLocalLoginFailure`
- `iam.usp_IssueEmailVerificationChallenge`
- `iam.usp_CreateAuthSession`
- `iam.usp_ValidateSessionAccess`
- `iam.usp_RotateRefreshToken`
- `iam.usp_RevokeAuthSession`
- `iam.usp_GetUserProfile`
- `ten.usp_ListMyTenants`

The actual runtime principal is not separately configured: `Sql:Authentication=IntegratedSecurity` uses the API process identity. Do not grant `db_owner`, `db_ddladmin`, or direct application-table DML to substitute for the runtime role. Apply no grants until explicitly approved; use only an approved disposable `_TEST` database for write-capable integration tests.

## Changed files

- `.env.development`
- `vite.config.ts`
- `src/api/client.ts`
- `src/api/auth.ts`
- `tests/api-client.test.ts`
- `../klop-next-platform-api/src/KLOP.Platform.Api/Program.cs`
- `docs/API_DEPENDENCIES.md`
- `docs/INTEGRATION_VALIDATION.md` (marked as a superseded baseline)
- `docs/INTEGRATION_REPORT.md`
