# API endpoints

All route definitions are under `/api/v1`. Successful responses keep the v1.3 envelope `{ success, data, error, meta }`. Error responses use RFC 9457 Problem Details (`application/problem+json`) and retain `success`, `error`, and `meta` as extension members for contract continuity. Validation errors include a safe `errors` extension without submitted values.

The inventory below reflects source and OpenAPI inspection, read-only Development SQL catalog/signature checks, and non-mutating API probes recorded in [the test report](TEST_PLAN.md). `PASS` applies only to the behavior named; it does not imply a successful state-changing workflow. The 20 baseline procedures and the registration/onboarding procedures are present. Positive authenticated and mutation workflows remain BLOCKED: `klop_app_runtime` has no members and only eight explicit object EXECUTE grants, the local Integrated Security caller is elevated, and no explicitly approved isolated `_TEST` database is configured.

## Latest live verification — 2026-11-21

The configured Development API at `https://localhost:7041` passed health/readiness, Swagger/OpenAPI, SQL-backed organization-type reads (7 rows), expected unauthenticated denials, invalid-login validation, refresh-origin rejection, and exact-origin CORS checks. OpenAPI exposed 15 `/api/v1` operations. A real browser page at `https://localhost:5173` loaded over HTTPS and fetched the public organization-type endpoint with credentials enabled (HTTP 200, 7 rows); visiting `/tenants` without a session redirected to `/login`.

These are read-only or expected-denial checks. No registration, verification, valid login, session creation, refresh rotation, logout, authenticated profile/tenant listing, tenant mutation, or cross-tenant authorization attempt was made. Those positive workflows remain BLOCKED pending a least-privilege runtime identity and an explicitly approved isolated `_TEST` database.

| Method | Route | Authentication | Required permission | Stored Procedure dependency | Implementation | Test result |
|---|---|---|---|---|---|---|
| POST | `/api/v1/auth/register` | Anonymous; rate-limited | None | `iam.usp_RegisterLocalUser` (present) | Implemented | PASS: invalid payload returned 400; successful write BLOCKED (no approved `_TEST` database) |
| POST | `/api/v1/auth/resend-verification` | Anonymous; rate-limited | None | `iam.usp_IssueEmailVerificationChallenge` (present; signature PASS) | Implemented | PASS: invalid payload returned 400; successful write BLOCKED (runtime grant/test database gate) |
| POST | `/api/v1/auth/verify-email` | Anonymous; rate-limited | None | `iam.usp_ConfirmEmail` (present) | Implemented | PASS: invalid payload returned 400; successful write BLOCKED (no approved `_TEST` database) |
| POST | `/api/v1/auth/login` | Anonymous; rate-limited | None | `iam.usp_GetLocalLoginCandidate`, `iam.usp_RecordLocalLoginFailure`, `iam.usp_CreateAuthSession` (present; signatures PASS) | Implemented | PASS: invalid payload returned 400; successful login BLOCKED (runtime grant/test database gate) |
| POST | `/api/v1/auth/refresh` | Refresh cookie + exact configured Origin; rate-limited | None | `iam.usp_RotateRefreshToken` (present; signature PASS) | Implemented | PASS: no-Origin request returned 403; configured-origin CORS preflight PASS; rotation BLOCKED (no test session/runtime identity) |
| POST | `/api/v1/auth/logout` | JWT + active database session | None | `iam.usp_ValidateSessionAccess`, `iam.usp_RevokeAuthSession` (present; signatures PASS) | Implemented | PASS: anonymous request returned 401; successful revocation BLOCKED (runtime grant/test database gate) |
| GET | `/api/v1/auth/me` | JWT + active database session | None | `iam.usp_ValidateSessionAccess`, `iam.usp_GetUserProfile` (present; signatures PASS) | Implemented | PASS: anonymous request returned 401; authenticated profile BLOCKED (runtime grant/test database gate) |
| GET | `/api/v1/master/organization-types` | Public, safe DTO | None | `mst.usp_OrganizationType_GetAll` (present) | Implemented | PASS: HTTP 200 envelope; 7 SQL-backed rows |
| GET | `/api/v1/tenants/mine` | JWT + active database session | None | `iam.usp_ValidateSessionAccess`, `ten.usp_ListMyTenants` (present; signatures PASS) | Implemented | PASS: anonymous request returned 401; authenticated listing BLOCKED (runtime grant/test database gate) |
| GET | `/api/v1/tenants/{tenantId}/permissions` | JWT + active database session and active membership in an eligible selected tenant | None; returns effective tenant permissions only | `iam.usp_GetTenantPermissions` (prepared in v1.10) | Implemented; protected route contract test | BLOCKED until v1.10 SQL, least-privilege runtime, latest API deployment, and a valid session |
| POST | `/api/v1/tenants/` | JWT + active database session; owner ID from claim | None | `iam.usp_ValidateSessionAccess` (present; signature PASS), `mst.usp_TenantType_GetAll`, `cfg.usp_Configuration_GetByKey`, `ten.usp_CreateTenantWithOwner` (present) | Implemented | PASS: anonymous JSON request returned 401; successful write BLOCKED (runtime grant/test database gate) |
| POST | `/api/v1/tenants/{tenantId}/invitations` | JWT + active database session | `tenant.members.invite` | `iam.usp_ValidateSessionAccess`, `ten.usp_InviteExistingUser` (present) | Implemented | PASS: anonymous JSON request returned 401; authorized flow BLOCKED (runtime grant/test database gate) |
| POST | `/api/v1/tenants/memberships/{membershipId}/accept` | JWT + active database session; invitee checked by SQL | None | `iam.usp_ValidateSessionAccess`, `ten.usp_AcceptMembership` (present) | Implemented | PASS: anonymous request returned 401; authorized flow BLOCKED (runtime grant/test database gate) |
| DELETE | `/api/v1/tenants/{tenantId}/memberships/{membershipId}` | JWT + active database session | `tenant.members.remove` | `iam.usp_ValidateSessionAccess`, `ten.usp_RemoveTenantMember` (present) | Implemented | PASS: anonymous request returned 401; authorized flow BLOCKED (runtime grant/test database gate) |
| POST | `/api/v1/tenants/{tenantId}/memberships/{membershipId}/roles` | JWT + active database session | `tenant.roles.assign` | `iam.usp_ValidateSessionAccess`, `iam.usp_AssignTenantRole` (present) | Implemented | PASS: anonymous JSON request returned 401; authorized flow BLOCKED (runtime grant/test database gate) |
| DELETE | `/api/v1/tenants/{tenantId}/memberships/{membershipId}/roles/{roleCode}` | JWT + active database session | `tenant.roles.assign` | `iam.usp_ValidateSessionAccess`, `iam.usp_RevokeTenantRole` (present) | Implemented | PASS: anonymous request returned 401; authorized flow BLOCKED (runtime grant/test database gate) |

The Registration Management endpoints below are the first published PLATFORM permission-protected API group. The earlier tenant endpoint tests above do not grant or simulate a tenant permission.

## Registration management source implementation — 2026-11-25

The source defines four read-only Platform registration operations plus an authenticated permission-discovery endpoint. The current Development catalog contains the four registration procedures and the permission allowlist entries, but the canonical permission row and role mappings are missing. Thus administrative reads remain denied until the separate permission seed receives approval and is applied.

| Method | Route | Authentication | Required permission | Stored Procedure dependency | Source/test status | Development runtime |
|---|---|---|---|---|---|---|
| GET | `/api/v1/platform/registrations/permissions` | JWT + active database session | None; returns only the caller's effective registration permission | `iam.usp_GetPlatformPermissions` | Implemented; authenticated route contract test | Current running binary predates this source route (404); source deployment not performed |
| GET | `/api/v1/platform/registrations/summary?registrationType=PERSONAL` | JWT + active database session | `platform.registrations.read` | `reg.usp_GetPlatformRegistrationSummary` | Implemented; protected route contract test | BLOCKED: 403 because no active permission master row/mapping |
| GET | `/api/v1/platform/registrations?registrationType=PERSONAL` | JWT + active database session | `platform.registrations.read` | `reg.usp_ListPlatformRegistrations` | Implemented; protected route contract test | BLOCKED: same missing permission assignment |
| GET | `/api/v1/platform/registrations/{registrationApplicationId}` | JWT + active database session | `platform.registrations.read` | `reg.usp_GetPlatformRegistration` | Implemented; protected route contract test | BLOCKED: same missing permission assignment |
| GET | `/api/v1/platform/registrations/{registrationApplicationId}/timeline` | JWT + active database session | `platform.registrations.read` | `reg.usp_GetPlatformRegistrationTimeline` | Implemented; protected route contract test | BLOCKED: same missing permission assignment |

Development read-only verification found all four registration procedures and both IAM permission procedures in the catalog; both IAM procedure definitions include `platform.registrations.read`. The permission master contains zero rows for that code, so neither `SUPER_ADMIN` nor `PLATFORM_SUPPORT` has a mapping and the active SUPER_ADMIN permission resolver returns no registration permission. The v1.9 migration ledger is not present, so the catalog proves equivalent procedure code is deployed but cannot identify which deployment artifact installed it. No permission seed or grant template was executed.

The Development API uses Integrated Security as `DEV-PC\rajaa`, mapped to database principal `dbo`; the registered `klop_app_runtime` role has no members and no EXECUTE grants for the four registration-administration procedures. The current dbo mapping makes those grants irrelevant to the observed 403, which is raised by application-permission validation before data queries. A current catalog recheck found eight explicit role grants: `iam.usp_RegisterLocalUser`, `mst.usp_TenantType_GetAll`, and the six registration-onboarding procedures. The elevated local identity is not a suitable least-privilege runtime identity. See the [v1.10 runtime permission matrix](SQL_RUNTIME_PERMISSION_MATRIX.md) and [RBAC reconciliation report](../../KLOP_PLATFORM_RBAC_1_0_RECONCILIATION_REPORT.md) for the revised, approval-gated 38-procedure allowlist.

The live API log records authenticated `GET /api/v1/platform/registrations/summary` requests returning 403 (`FORBIDDEN`); the database permission procedure independently returned SQL error 52332 for an active SUPER_ADMIN session. A later anonymous request returned 401 (`UNAUTHORIZED`). No current Support session was available for an authenticated positive test. No registration data was changed.

## RBAC v1.0 source readiness — not deployed

The source now includes tenant-scoped effective-permission discovery for membership UI gating. Its stored procedure is prepared in `database/migrations/v1.10/003_tenant_permission_policy_APPROVAL_TEMPLATE.sql`; the current Development catalog does not yet contain `iam.usp_GetTenantPermissions`. The same approval-gated template tightens tenant scope/status and permission-scope checks and denies membership-role operations for single-member PERSONAL tenants. The role assignment path preserves exactly one active OWNER, respects `IsAssignable`, permits only the approved MEMBER/ADMIN targets, and keeps ownership transfer on HOLD.

The v1.10 API route returns effective permissions only for the authenticated user and selected eligible tenant; it does not grant capabilities. Current permission rows give `tenant.roles.assign` to OWNER, but not ADMIN. Therefore the workbook's approved Admin-assign-MEMBER capability remains denied and is explicitly not added by this release. `VIEWER` remains unassignable. Registration permission seeding is limited to `platform.registrations.read` for `SUPER_ADMIN` and `PLATFORM_SUPPORT`; proposed, conditional, and HOLD codes remain inactive.

Current Development verification found all six role IDs/codes/scopes/active/system/assignable flags aligned with the workbook. It also found the four existing platform permission codes mapped only to `SUPER_ADMIN`, no registration permission row/mapping, the expected `PERSONAL`/`ORGANIZATION` multi-member policy, one active ORGANIZATION OWNER, no tenant with multiple active owners, and no migration ledger table. These were read-only checks; the workbook remains APPROVED but not FROZEN, and no database mutation, grant, or deployment was performed. API/UI source tests pass; live Admin/Support validation remains blocked until DBA approval, runtime identity remediation, deployment, restart, and valid sessions.

## Unified Role & Permission Matrix source — prepared, not deployed

The API source exposes one matrix under Platform Setup; there are no separate Platform/PERSONAL/ORGANIZATION permission-management pages. Database-backed access remains SUPER_ADMIN-only through the explicit `platform.role_permissions.read` and `platform.role_permissions.update` permissions. The `/access` endpoint reports these capabilities to the frontend, but every matrix operation is independently authorized by the backend and SQL.

| Method | Route | Permission / behavior | Stored procedure |
|---|---|---|---|
| GET | `/api/v1/platform/role-permissions/access` | Authenticated discovery of read/update capabilities | `iam.usp_GetPlatformPermissions` |
| GET | `/api/v1/platform/role-permissions/matrix` | `platform.role_permissions.read`; unified database read model | `iam.usp_GetUnifiedRolePermissionMatrix` |
| GET | `/api/v1/platform/role-permissions/history` | `platform.role_permissions.read`; paged audit history | `iam.usp_GetRolePermissionChangeHistory` |
| POST | `/api/v1/platform/role-permissions/changes/validate` | `platform.role_permissions.update`; validate-only batch | `iam.usp_SaveRolePermissionBatch` |
| POST | `/api/v1/platform/role-permissions/changes` | `platform.role_permissions.update`; atomic, audited save | `iam.usp_SaveRolePermissionBatch` |

The matrix distinguishes configured grants from effective allowed status, and returns readiness, restrictions, editability, tenant-type context, and per-mapping rowversion tokens. Its role columns are derived from existing role/scope and tenant-type eligibility: `SUPER_ADMIN`, `PLATFORM_SUPPORT`, PERSONAL `OWNER`, and ORGANIZATION `OWNER`, `ADMIN`, `MEMBER`, `VIEWER`. Existing role IDs, codes, scopes, and assignability are preserved. `mst.RolePermissions` remains the single grant mapping; the v1.10 schema extension adds tenant type to its key rather than introducing a second grant table.

Account self-service is displayed from the separate read-only `mst.AccountSelfServicePolicies` catalog. Those identifiers are not inserted into `mst.Permissions`, no `ACCOUNT` role scope is added, and no account role/grant cells are generated. The account policy values are reconciled from the existing row-level CSV; the original workbook is not available in this workspace and must be checked against the approved source before DBA deployment.

The revised SQL templates have not been deployed. Development runtime validation is blocked by the elevated API identity and missing dedicated runtime principal. The v1.10 allowlist is now 38 exact stored procedures; see [the runtime permission matrix](SQL_RUNTIME_PERMISSION_MATRIX.md), [implementation report](../../KLOP_UNIFIED_RBAC_MATRIX_IMPLEMENTATION_REPORT.md), and [manual validation guide](../../KLOP_PLATFORM_RBAC_1_0_MANUAL_VALIDATION_GUIDE.md).

Infrastructure endpoints:

| Method | Route | Behavior | Smoke result |
|---|---|---|---|
| GET | `/health/live` | Process liveness only; independent of SQL | PASS: HTTP 200 |
| GET | `/health/ready` | SQL readiness; response does not expose dependency details | PASS: HTTP 200 from live Development API |
| GET | `/.well-known/jwks.json` | Public RSA signing key parameters only | PASS: HTTP 200; no private parameters |
| GET | `/openapi/v1.json` | Development only | PASS: HTTP 200; 15 API operations |
| GET | `/swagger` | Development-only Swagger UI | PASS: HTTP 200 |

The Development launch profile opens Swagger automatically at the application's configured HTTPS URL (currently `https://localhost:7041/swagger`). The UI reads the built-in OpenAPI v1 document and supports **Authorize** with a JWT access token; protected operations still require an active SQL session and any applicable tenant permissions. Refresh uses its cookie and configured Origin, not a bearer token. The live configured Origin `https://localhost:5173` passed an API CORS preflight and an unapproved origin received no allow-origin header; a browser session against the portal's HTTPS origin was NOT RUN. Swagger and OpenAPI are not mapped in Production.

## Authentication and tenancy rules

- Passwords use PBKDF2-HMAC-SHA256 with a random 32-byte salt and versioned encoding. The stored credential is never logged.
- Email verification and refresh secrets are cryptographically random; only SHA-256 digests are passed to SQL.
- Access tokens are RSA-signed and short-lived. Every authenticated request revalidates the session in SQL.
- Refresh tokens are only returned through an HttpOnly, Secure, SameSite=Strict cookie. Refresh requires the configured Origin.
- Tenant and membership IDs from routes are not authority. The database validates the current membership and permission. Actor/owner IDs come from the validated JWT.
- Tenant creation looks up tenant type and its registration setting from SQL; the write SP remains authoritative for supported type-specific fields.
- SQL error codes map to safe API responses. SQL text, parameter values, object names, and infrastructure details are not returned.

## Request examples

Register: `{"email":"dev@example.com","fullName":"Developer","password":"UseADisposableStrongPassphrase!"}`

For compatibility, registration also accepts the existing `displayName` field as a fallback alias when `fullName` is omitted. If both are supplied, `fullName` is canonical and takes precedence. Verification email links point to the configured frontend origin at `/verify-email#userId=...&token=...`; the fragment keeps the one-time token out of HTTP request and referrer headers. The frontend page should parse the fragment and pass those values to `POST /api/v1/auth/verify-email`.

Verify: `{"userId":123,"token":"<verification-code>"}`

Create tenant: `{"tenantCode":"DEV-001","tenantTypeCode":"PERSONAL","displayName":"Development Workspace","organizationTypeId":null,"registeredName":null}`

Invite: `{"inviteeUserId":124}`

Assign role: `{"roleCode":"MEMBER"}`
