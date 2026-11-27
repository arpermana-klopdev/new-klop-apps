# KLOP-PLATFORM-RBAC-1.0 API/UI Implementation Report

## Implemented in source

### Backend

- Added authenticated `GET /api/v1/tenants/{tenantId}/permissions`, returning distinct effective permission codes for the current authenticated session and selected tenant.
- Added the tenant permission repository/service/handler path and dependency-injection registrations.
- Added route contract coverage for the new authenticated endpoint.
- Extended SQL error translation so policy denial (52191) returns 403 and tenant-state conflict (52192) returns 409.
- Added unit cases for effective permission normalization and discovery.

### Frontend

- Added typed tenant permission retrieval and permission-code constants.
- Updated membership actions to render only when the selected tenant's API response includes the corresponding permission. The API remains authoritative for all actions.
- Updated the Registration Center guard to show an explicit denied state instead of silently navigating home.
- Added the tenant-permissions operation and response schema to OpenAPI, then regenerated the frontend API types and exported the generated response contract.

### Documentation

- Updated the API endpoint inventory and SQL runtime permission matrix with current Development findings, the new route, runtime blockers, and the 38-procedure allowlist.

## Source validation

| Check | Result |
|---|---|
| Backend Release unit/route contract tests | PASS — 125 tests |
| OpenAPI TypeScript generation | PASS |
| Frontend unit/component tests | Original tenant/registration suite: 82 tests across 12 files; final unified-matrix rerun is tracked in the matrix implementation report |
| Frontend TypeScript typecheck | PASS |
| Frontend production build | PASS; only existing dependency annotation warnings |

## Unified Role & Permission Matrix source

The source now includes a single Platform Setup Center matrix page and API for PLATFORM, PERSONAL, ORGANIZATION, and read-only account-policy information. The API exposes access discovery, matrix read, history, validate-only batch, and atomic save routes. The two matrix control capabilities are database-backed and mapped only to existing `SUPER_ADMIN` in the unpublished v1.10 SQL template.

The generated read model keeps configured grants distinct from effective authorization and returns readiness, restrictions, context eligibility, editability, and concurrency versions. The single existing role-permission mapping is extended with tenant type; no role-specific BIT columns or extra role records are introduced. Account policy values are separated into a read-only catalog outside the role/permission hierarchy. See the [unified matrix implementation report](KLOP_UNIFIED_RBAC_MATRIX_IMPLEMENTATION_REPORT.md) and [reconciliation artifact](KLOP_UNIFIED_ROLE_PERMISSION_MATRIX_RECONCILIATION.csv).

The revised 003 migration, post-deployment checks, and runtime identity allowlist remain un-deployed and need fresh DBA/security approval. The existing workbook is not in the workspace; the extracted account policy data must be checked against the approved source before deployment.

## Runtime limitations

The new source is not deployed to the Development API. The database procedure `iam.usp_GetTenantPermissions` is prepared but not deployed. The platform registration read permission is still absent from the Development permission master/mappings. The API runtime is still mapped to `dbo`/`sysadmin`, and `klop_app_runtime` has no members. Consequently, no live positive Admin/Support permission test or authenticated UI test was performed.

The workbook's Admin Assign MEMBER permission is not mapped in Development. The UI therefore cannot grant that capability; the server also denies it unless the active database mapping provides `tenant.roles.assign`. Registration approval/rejection, email resend, exports, ownership transfer, and other conditional/HOLD actions remain unavailable.

See the [reconciliation report](KLOP_PLATFORM_RBAC_1_0_RECONCILIATION_REPORT.md), [SQL deployment report](KLOP_PLATFORM_RBAC_1_0_SQL_DEPLOYMENT_REPORT.md), and [manual validation guide](KLOP_PLATFORM_RBAC_1_0_MANUAL_VALIDATION_GUIDE.md).
