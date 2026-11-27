# Unified Role & Permission Matrix — Implementation Report

## Status

**Implemented in source; SQL prepared but not deployed.** The existing frozen baselines and six role records are preserved. No Development data, schema, role assignment, permission mapping, runtime principal, or SQL grant was changed. The RBAC baseline remains APPROVED / NOT FROZEN.

## Unified design

- One Platform Setup Center page reads a backend-generated matrix; no separate authorization-context permission pages were added.
- The database read model derives eligible columns from the existing role/scope and tenant-type masters: `SUPER_ADMIN`, `PLATFORM_SUPPORT`, PERSONAL `OWNER`, ORGANIZATION `OWNER`, `ADMIN`, `MEMBER`, and `VIEWER`.
- `OWNER` is still one role record (RoleId 3), shown in each eligible tenant-type context. No role IDs/codes/scopes/`IsAssignable` values were changed.
- `mst.RolePermissions` remains the only grant mapping. The prepared migration adds nullable `TenantTypeId` and a `ROWVERSION` token to support tenant-type-scoped cells and optimistic concurrency.
- Configured grants, effective allowed status, readiness, editability, restrictions, and concurrency versions are separate fields. Missing mappings deny by default; PERSONAL member/role-management permissions remain effectively denied.
- Matrix read, update, and history use the existing database authorization and audit infrastructure. Only the existing `SUPER_ADMIN` receives the two matrix control permissions in the prepared template.
- Account Self-Service values are presented as read-only policy data from `mst.AccountSelfServicePolicies`. They are not added to `mst.RoleScopes`, `mst.Permissions`, or `mst.RolePermissions`; their matrix rows have no permission ID or role cells.
- The migration seeds no proposed Dashboard, Tenant, or Platform Setup permissions. It keeps existing permission-master codes and role records unchanged.

## API and UI

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/v1/platform/role-permissions/access` | Return the caller's effective matrix read/update capabilities |
| GET | `/api/v1/platform/role-permissions/matrix` | Return the unified matrix read model |
| GET | `/api/v1/platform/role-permissions/history` | Return paged matrix audit history |
| POST | `/api/v1/platform/role-permissions/changes/validate` | Validate a batch without applying it |
| POST | `/api/v1/platform/role-permissions/changes` | Atomically save a validated batch |

The Setup Center entry and direct page are hidden/disabled without database-backed read access. The backend independently enforces read/update permissions. The UI distinguishes grants from effective authorization, presents policy rows without artificial role cells, supports reasoned review/validation/save, shows restrictions, refreshes the matrix after save, and displays audit history.

## SQL and deployment package

- Revised `003_tenant_permission_policy_APPROVAL_TEMPLATE.sql` extends the authoritative mapping, seeds only the two matrix control permissions, creates the separate account-policy table, adds matrix readiness metadata, updates tenant-context authorization resolution, and defines matrix read, batch save/validate, and history procedures.
- The read-only post-deployment checks validate matrix procedures, policy/master separation, scope/tenant-type mapping consistency, and SUPER_ADMIN-only matrix permissions.
- Both approval-gated runtime grant/validation scripts now allow exactly 38 procedures, including the three new matrix procedures.
- The prior v1.10 SQL package is unpublished. The revised template needs fresh DBA review and explicit approval; SQL parsing is not deployment approval.

## Reconciliation and source caveats

- The Development database was inspected read-only: six roles, two active role scopes (`PLATFORM`, `TENANT`), 16 active permission codes, and 28 configured role-permission mappings.
- The prepared matrix has seven eligible role/context columns. Existing tenant mappings are context-split by the migration; role/permission semantics are preserved subject to the PERSONAL single-member restrictions.
- Sixteen account policy rows were copied from the existing row-reconciliation CSV, including Public/Unverified/Verified policy states. The original workbook is absent from this workspace; these values and codes must be checked against the approved workbook before deployment.
- The [matrix reconciliation CSV](KLOP_UNIFIED_ROLE_PERMISSION_MATRIX_RECONCILIATION.csv) separates observed database state, prepared grants, role columns, and read-only account-policy entries.

## Validation

| Check | Result |
|---|---|
| Backend Release unit tests | PASS — 126 tests |
| Frontend OpenAPI type generation | PASS |
| Frontend TypeScript typecheck | PASS |
| Frontend production build | PASS; existing third-party Rollup annotation warnings only |
| Frontend unit/component suite | PASS — 83 tests across 12 files |
| SQL Server `PARSEONLY` | PASS — all six v1.10 SQL scripts; syntax-only, not executed |
| Development deployment or live authorization tests | NOT RUN; SQL and API are not deployed and the current API identity is elevated |

SQLCMD `PARSEONLY` validates syntax only; it does not execute migrations or prove live procedure behavior. No baseline freeze is claimed.
