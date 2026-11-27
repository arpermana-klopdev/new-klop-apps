# API Contract Verification

## Result summary

- **Mapped route count:** 15 `/api/v1` operations and 3 infrastructure routes before; 15 and 3 after (18 total).
- **Route/method verification:** PASS for the 18 mapped route patterns and methods represented by endpoint metadata. The readiness health-check route uses `MapHealthChecks` and carries no explicit HTTP-method metadata (`ALL`); this was already true before extraction and is preserved.
- **Authorization/rate-limit metadata:** PASS by automated unit test. Tenant-group authorization, bearer-only `logout` and `me`, and the `auth` rate-limit policy on register, resend, verify, login, and refresh are retained.
- **Endpoint summaries:** PASS for all auth operations in the route metadata test. Existing summaries/descriptions and `.Produces` annotations were copied with each route.
- **OpenAPI operation generation:** PASS for the build-generated OpenAPI document: it contains 18 operations (15 `/api/v1` plus 3 system routes) and its SHA-256 exactly matches the pre-refactor recovery snapshot. Serving/fetching OpenAPI from a running API is NOT VERIFIED because startup loads SQL-backed runtime configuration; no database was accessed for this structural refactor. Existing OpenAPI security-transformer unit tests pass.
- **Request/response compatibility:** Structural handlers and DTO declarations were retained; no request fields, response envelopes, status/error codes, cookie format/flags, or JSON serialization settings were intentionally changed. No live consumer E2E was run.

## Route inventory

| Method | Route | Authentication / policy |
|---|---|---|
| GET | `/api/v1/master/organization-types` | Public; validation filter inherited from API group |
| POST | `/api/v1/auth/register` | Anonymous; `auth` rate limit |
| POST | `/api/v1/auth/resend-verification` | Anonymous; `auth` rate limit |
| POST | `/api/v1/auth/verify-email` | Anonymous; `auth` rate limit |
| POST | `/api/v1/auth/login` | Anonymous; `auth` rate limit |
| POST | `/api/v1/auth/refresh` | Refresh cookie + origin check; `auth` rate limit |
| POST | `/api/v1/auth/logout` | Bearer authentication + active session |
| GET | `/api/v1/auth/me` | Bearer authentication + active session |
| GET | `/api/v1/tenants/mine` | Authorized tenant route group |
| POST | `/api/v1/tenants/` | Authorized tenant route group |
| POST | `/api/v1/tenants/{tenantId:long}/invitations` | Authorized tenant group + `tenant.members.invite` |
| POST | `/api/v1/tenants/memberships/{membershipId:long}/accept` | Authorized tenant route group; stored procedure validates actor |
| DELETE | `/api/v1/tenants/{tenantId:long}/memberships/{membershipId:long}` | Authorized tenant group + `tenant.members.remove` |
| POST | `/api/v1/tenants/{tenantId:long}/memberships/{membershipId:long}/roles` | Authorized tenant group + `tenant.roles.assign` |
| DELETE | `/api/v1/tenants/{tenantId:long}/memberships/{membershipId:long}/roles/{roleCode}` | Authorized tenant group + `tenant.roles.assign` |
| GET | `/health/live` | Anonymous |
| ALL* | `/health/ready` | Anonymous; health-check middleware |
| GET | `/.well-known/jwks.json` | Anonymous |

\* `MapHealthChecks` has no explicit method constraint; its original mapping and framework behavior were left intact.

## Regression evidence

`ApiRouteContractTests.EndpointModulesPreserveRouteMethodsAndSecurityMetadata` constructs the endpoint modules without starting the API or connecting to SQL Server. It checks all 18 route patterns, explicit methods, auth summaries, tenant authorization metadata, auth-rate-limit metadata, and auth-only authorization. `RefreshCookieTests` checks the existing refresh-cookie name/payload and `HttpOnly`, `Secure`, `SameSite=Strict`, and `Path=/` attributes. These tests do not establish end-to-end authentication or runtime-generated OpenAPI output.