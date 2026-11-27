# Platform Registration Management Implementation Report

**Date:** 2026-11-25  
**Scope:** Development-only registration administration; no migration or permission grant was executed.

## Confirmed root cause

The live API log records authenticated `GET /api/v1/platform/registrations/summary` requests returning HTTP 403 (`FORBIDDEN`). Requests immediately beforehand refreshed successfully and `/api/v1/auth/me` returned 200, so the observed denial was authorization, not authentication. One sanitized request correlation ID is `b2e96a8a-ef28-414f-b875-f51db4ba53b2`.

The required and canonical permission is `platform.registrations.read`. The backend policy and both deployed SQL permission-procedure allowlists use that exact code. The actual `KlopPlatformDB` has **zero permission-master rows** with that code, so neither the `SUPER_ADMIN` nor `PLATFORM_SUPPORT` role can map it. An active `SUPER_ADMIN` session returned no effective platform permissions; direct read-only permission validation returned SQL error 52332, which the API permission handler converts to 403. This is the confirmed root cause.

The expected Problem Details body for the logged 403 is `title=FORBIDDEN`, `status=403`, `detail="Operation is not permitted."`, `error.code=FORBIDDEN`, with the request ID in `meta`. The compact API log does not retain response bodies, so the body shape is confirmed from the running API's `OnForbidden`/`ApiHelpers.Error` implementation rather than captured from that specific authorized response. An anonymous live request independently returned HTTP 401 with `error.code=UNAUTHORIZED` and request ID `16599977-b742-4ad3-9533-8f592fb86eef`.

Earlier 503 summary entries (`SERVICE_UNAVAILABLE`, 74-second duration) are distinct requests with compact `SQL_OPERATION_FAILED` logging and no SQL error number; they are not enough evidence to attribute those separate failures to authorization. The subsequent authenticated 403s and database permission denial establish the authorization root cause without conflating the 503s.

## Database checks

Read-only queries were run against `DEV-PC\SQLEXPRESS`, database `KlopPlatformDB`.

| Registration type | Total applications | Pending email verification | Email verified | Pending review |
|---|---:|---:|---:|---:|
| PERSONAL | 1 | 1 | 0 | 0 |
| ORGANIZATION | 0 | 0 | 0 | 0 |

Other verified facts:

- The PERSONAL application is `DRAFT`, current, and has no Tenant.
- One email-verification challenge exists; it is not consumed or invalidated. This does not establish that an email was delivered.
- Actual persisted timeline events for the registration are `REGISTRATION_ACCEPTED`, `EMAIL_PENDING`, and `TERMS_ENFORCEMENT_BYPASSED`.
- No PERSONAL or ORGANIZATION onboarding profile rows currently exist.
- All four administrative registration procedures are present in `reg`; the deployed `iam.usp_ValidatePlatformPermission` and `iam.usp_GetPlatformPermissions` definitions both include `platform.registrations.read`. The database has no migration-history table to attribute these objects to a particular script, but the procedure changes are present.
- The permission master has zero `platform.registrations.read` rows, and neither `SUPER_ADMIN` nor `PLATFORM_SUPPORT` has a mapping. The database has one user assigned to each platform role; 15 active SUPER_ADMIN sessions and no active PLATFORM_SUPPORT sessions were observed at inspection time. Effective registration permission is absent for the tested SUPER_ADMIN session.
- The `klop_app_runtime` role has zero members and zero EXECUTE grants for the four registration procedures. The running Development API process uses Integrated Security as `DEV-PC\rajaa`, which maps to database principal `dbo`; this elevated identity can execute procedures and is not the cause of the 403. It is not a suitable least-privilege runtime identity.
- No migration, permission assignment, or EXECUTE grant was applied.

## Implementation

### Registration Center

- Preserved the two PERSONAL and ORGANIZATION navigation cards and their routes.
- Updated the description to “Monitor and manage personal and organization account registrations.”
- Added backend-driven summary metrics: total applications, pending verification, verified email, and pending review.
- Summary errors are represented as errors/retry states rather than fabricated zeroes.

### PERSONAL and ORGANIZATION listings

- Replaced the unavailable placeholders with a shared server-backed listing.
- Added registration type filtering from the existing route, search by DisplayName/email/application ID, email-verification and application-status filters, server-side pagination, refresh, retry, and empty states.
- Application-status filter options come from `mst.OnboardingStatuses`, independent of the current page or selected filter.
- The list displays Full Name from `displayName`, email, email-verification state, application status, registration timestamp, and a detail action.
- The ORGANIZATION list uses the registering account's DisplayName and email; it does not invent an organization name.
- Removed onboarding placeholders from the listings. `PersonalIdentityForm` and `DocumentRequirements` remain available as reusable components and are not mounted on the listing pages.

### Detail and timeline

- Added a read-only detail view with return navigation that preserves listing state.
- The view shows user/account status, email verification timestamp, application state/timestamps, actual optional profile fields, latest challenge issue/expiry timestamps, and linked Tenant data where present.
- Profile completion remains unavailable (`null`) because no authoritative completion status exists.
- Timeline events are sourced only from persisted application history and associated registration/legal audit events; no delivery or other fictional events are generated.
- No password, credential hash, verification token, or token hash is returned.

### Backend and authorization

Source endpoints:

- `GET /api/v1/platform/registrations/summary`
- `GET /api/v1/platform/registrations`
- `GET /api/v1/platform/registrations/{registrationApplicationId}`
- `GET /api/v1/platform/registrations/{registrationApplicationId}/timeline`

The four data endpoints require an authenticated active session and the `platform.registrations.read` permission. Database procedures also validate that permission. Added an authenticated permission-discovery endpoint that returns only the caller's effective registration permission, resolved from the existing database permission procedure; it does not grant access. The API handler now preserves invalid-session error 52330 as HTTP 401 while permission denial 52332 remains HTTP 403.

Search/filter inputs and pagination bounds are validated; results use deterministic ordering and include every application regardless of verification, profile completion, Tenant, or `IsCurrent` state. The API source has no role-name bypass; both existing role codes receive access only through the approved database permission mapping.

The current Development DB already has the registration procedure and permission-allowlist code, but the permission seed is missing. The existing [v1.9 permission approval template](D:/PROJECT/Smart/klop/klop-next-platform-api/database/security/v1.9_platform_registration_permissions_APPROVAL_TEMPLATE.sql) is the exact seed correction: it creates the canonical permission when absent and idempotently maps only `SUPER_ADMIN` and `PLATFORM_SUPPORT`; it defaults to dry-run and requires explicit approval/ticket values to apply. The existing [v1.9 runtime grant template](D:/PROJECT/Smart/klop/klop-next-platform-api/database/security/v1.9_platform_registration_runtime_grants_TEMPLATE.sql) grants object-level EXECUTE only on the four registration procedures. It must not be run until a dedicated approved runtime principal is mapped to `klop_app_runtime` and the required existing runtime-permission-procedure grant is in place. Do not grant the local `dbo` identity additional permissions. Neither template was executed.

The frontend navigation and all registration routes now use the same database-resolved `platform.registrations.read` capability. Missing capability hides the navigation item and blocks the route; API authorization remains authoritative. Permissions are not embedded in access-token claims, so the server resolves them from the active session/database on requests. The UI rechecks on mount/window focus; a page reload after approved mapping is sufficient, with no logout/login required.

### OpenAPI

Added all four operations and response/query schemas to `klop-next_ui/openapi.yaml`. Regenerated `klop-next_ui/src/api/schema.d.ts` with `npm run api:types`; the registration API client now uses the generated response types.

## Validation results

| Validation | Result |
|---|---|
| Frontend typecheck | PASS |
| Frontend tests | PASS — 79 tests across 11 files |
| Frontend production build | PASS — only non-blocking dependency annotation warnings |
| OpenAPI type generation | PASS |
| Backend Release build | PASS — 0 warnings, 0 errors |
| Backend Release unit tests | PASS — 122 tests |
| Backend integration tests | 3 skipped — tests require database mutation/configuration; no test database was approved |
| Backend route and permission metadata tests | PASS |
| Current live API | PASS for direct anonymous check (401); authenticated summary 403 confirmed in API log; new permission-discovery source route is not in the currently running binary (anonymous route returned 404) |
| Database inspection | PASS — read-only; confirmed missing master permission/mappings, deployed procedure allowlist and registration procedures, and current SQL identities/grants |
| Platform Admin and Support positive UI/API tests | BLOCKED — missing seed/mappings; no active Support session; browser session expired during follow-up |
| Unauthorized regular-user test | BLOCKED — no separate regular-user session supplied; API policy is covered by route metadata/unit tests, and unpermissioned callers resolve no capability |
| Existing registration visibility | BLOCKED — summary and listing fail authorization until approved seed; current data is one PERSONAL DRAFT with pending email verification and zero ORGANIZATION records |
| SQL syntax/deployment | No SQL changed in this authorization correction; all database probes were read-only and no security script was executed |
| Git status | UNAVAILABLE — the supplied workspace root is not a Git worktree |
| Git status | UNAVAILABLE — the supplied workspace root is not a Git worktree |

Integration tests requiring database mutation were not run. No accounts were created, no email was sent, and login/registration behavior was not changed.

## Exact files changed

**Frontend**

- `klop-next_ui/src/app/App.tsx`
- `klop-next_ui/src/app/RegistrationPermissionGuard.tsx` — added
- `klop-next_ui/src/app/platformRegistrationPermissions.ts` — added
- `klop-next_ui/src/app/modules.ts`
- `klop-next_ui/src/components/AppShell.tsx`
- `klop-next_ui/src/features/registrations/RegistrationCenterPage.tsx`
- `klop-next_ui/src/features/registrations/PersonalRegistrationsPage.tsx`
- `klop-next_ui/src/features/registrations/OrganizationRegistrationsPage.tsx`
- `klop-next_ui/src/features/registrations/RegistrationListingPage.tsx` — added
- `klop-next_ui/src/features/registrations/RegistrationDetailPage.tsx` — added
- `klop-next_ui/src/features/registrations/api.ts` — added
- `klop-next_ui/openapi.yaml`
- `klop-next_ui/src/api/schema.d.ts` — generated
- `klop-next_ui/src/features/registrations/RegistrationQueue.tsx` — removed; replaced by the shared listing
- `klop-next_ui/src/features/registrations/PersonalIdentityForm.tsx` — retained/restored as a reusable component
- `klop-next_ui/src/features/registrations/DocumentRequirements.tsx` — retained/restored as a reusable component
- `klop-next_ui/openapi.yaml`
- `klop-next_ui/src/api/schema.d.ts` — generated
- `klop-next_ui/tests/RegistrationPages.test.tsx`
- `klop-next_ui/tests/RegistrationPermissionGuard.test.tsx` — added
- `klop-next_ui/tests/AppShell.test.tsx`
- `klop-next_ui/tests/modules.test.ts`

**Backend, SQL, and documentation**

- `klop-next-platform-api/src/KLOP.Platform.Application/Features/Registration/PlatformRegistrationsContracts.cs` — added
- `klop-next-platform-api/src/KLOP.Platform.Application/Features/Registration/PlatformRegistrationService.cs` — added
- `klop-next-platform-api/src/KLOP.Platform.Api/Endpoints/Registrations/PlatformRegistrationEndpoints.cs` — added
- `klop-next-platform-api/src/KLOP.Platform.Api/Endpoints/Registrations/PlatformRegistrationHandlers.cs` — added
- `klop-next-platform-api/src/KLOP.Platform.Api/Endpoints/PlatformEndpointMappings.cs`
- `klop-next-platform-api/src/KLOP.Platform.Api/Bootstrap/ServiceRegistration.cs`
- `klop-next-platform-api/src/KLOP.Platform.Api/Authorization/PlatformPermissionAuthorization.cs`
- `klop-next-platform-api/src/KLOP.Platform.Api/Extensions/ApiHelpers.cs`
- `klop-next-platform-api/src/KLOP.Platform.Infrastructure/DependencyInjection/InfrastructureRegistration.cs`
- `klop-next-platform-api/src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/KlopRepository.cs`
- `klop-next-platform-api/src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/Registration/KlopPlatformRegistrationRepository.cs` — added
- `klop-next-platform-api/tests/KLOP.Platform.UnitTests/ApiContracts/ApiRouteContractTests.cs`
- `klop-next-platform-api/tests/KLOP.Platform.UnitTests/Authorization/PlatformPermissionAuthorizationTests.cs`
- `klop-next-platform-api/tests/KLOP.Platform.UnitTests/ApiContracts/ApiRouteContractTests.cs`
- `klop-next-platform-api/tests/KLOP.Platform.UnitTests/Registration/PlatformRegistrationServiceTests.cs` — added
- `klop-next-platform-api/database/migrations/v1.9/001_registration_read_procedures.sql` — prepared, not executed
- `klop-next-platform-api/database/migrations/v1.9/002_registration_read_procedures_validation_READONLY.sql` — added
- `klop-next-platform-api/database/security/v1.9_platform_registration_permissions_APPROVAL_TEMPLATE.sql` — prepared, not executed
- `klop-next-platform-api/database/security/v1.9_platform_registration_runtime_grants_TEMPLATE.sql` — prepared, not executed
- `klop-next-platform-api/docs/API_ENDPOINTS.md`
- `PLATFORM_REGISTRATION_MANAGEMENT_IMPLEMENTATION_REPORT.md` — added

## Final status

**OVERALL: PARTIAL — implementation is present in source; Development deployment remains blocked.**  
**READY FOR MANUAL TEST: NO.**

The confirmed application authorization root cause is the missing permission master row and role mappings, not a backend policy string mismatch. The current Development API identity is overprivileged (`dbo`) while the intended least-privilege role is unmapped. Manual Admin/Support validation remains blocked until the permission seed is approved/deployed and the API is configured to use an approved least-privilege runtime identity with only the required procedure grants. The existing PERSONAL DRAFT/pending-verification record can then be checked without modifying it or bypassing email verification.
