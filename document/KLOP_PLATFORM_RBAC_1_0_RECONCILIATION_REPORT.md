# KLOP-PLATFORM-RBAC-1.0 Reconciliation Report

## Status and scope

The supplied 18-sheet workbook is **APPROVED, not FROZEN**. Its immediate activation is limited to the already implemented read-only permission `platform.registrations.read` for the existing `SUPER_ADMIN` and `PLATFORM_SUPPORT` roles. `ALLOW` in the workbook is design eligibility, not an automatic database grant. Proposed, conditional, and HOLD capabilities remain inactive.

The complete row-level workbook comparison is in [KLOP_PLATFORM_RBAC_1_0_ROW_RECONCILIATION.csv](KLOP_PLATFORM_RBAC_1_0_ROW_RECONCILIATION.csv): 292 non-header workbook rows across all 18 sheets, with the original cell values, disposition, and evidence.

No Development database mutation, migration, permission seed, role assignment, runtime principal mapping, grant, deployment, account creation, email send, or freeze was performed.

## Development evidence (read-only)

The preflight ran against `DEV-PC\SQLEXPRESS` / `KlopPlatformDB` and verified:

| Area | Observed state | Workbook reconciliation |
|---|---|---|
| Role master | Role IDs 1–6, codes, PLATFORM/TENANT scope IDs, active/system flags, and `VIEWER IsAssignable=0` match | MATCH |
| Active permission master | 16 active permission codes; four PLATFORM codes are mapped only to `SUPER_ADMIN`; `PLATFORM_SUPPORT` has no platform permission mappings | Existing grants preserved; no new non-priority codes |
| Registration permission | `platform.registrations.read` has zero permission rows and zero role mappings | Missing; only this permission is prepared for seeding |
| Tenant type policy | `PERSONAL AllowMultipleMembers=0`; `ORGANIZATION AllowMultipleMembers=1` | MATCH; v1.10 procedure enforces the boundary |
| Owner invariant | One active ORGANIZATION OWNER; no tenant with multiple active OWNER assignments | Current data satisfies the exactly-one invariant |
| Registration records | One PERSONAL DRAFT with email pending; no ORGANIZATION registration | Read-only administration must include this DRAFT/unverified record |
| Runtime role | `klop_app_runtime` has zero members and eight explicit grants (tenant type lookup, user registration, six onboarding procedures) | Inadequate for the complete least-privilege runtime |
| API connection | Integrated Security resolves to an elevated `dbo`/`sysadmin` identity | BLOCKED for runtime validation |
| Procedures | Four registration administration procedures and both platform permission procedures exist; `iam.usp_GetTenantPermissions` is absent | Existing registration catalog is present; v1.10 tenant resolver is pending |
| Deployment history | No migration ledger table found | Procedure presence cannot identify which migration artifact deployed it |

Development has one active platform assignment each for `SUPER_ADMIN` and `PLATFORM_SUPPORT`. The current platform permission resolver can return the four already-mapped Super Admin permissions; it returns no registration permission because the canonical row/mapping is absent.

## Workbook-to-code decisions

| Workbook area | Reconciliation / implementation decision |
|---|---|
| Platform registration reads | Existing source endpoints cover summary, listing, details, and persisted timeline. They share `platform.registrations.read`; reads include pending verification and DRAFT records and do not mutate registration state. |
| Permission master/mappings | Prepare only `platform.registrations.read` at PLATFORM scope and map it to existing RoleId 1 and 2. Never create roles or map it to tenant roles. |
| Other platform capabilities | Existing platform codes and routes are preserved. Dashboard, tenant administration, directory, setup, audit, exports, resend, approval/rejection, and other proposed/conditional capabilities are not activated by this work. |
| Tenant/account scope | Keep PLATFORM, TENANT, and account self-service distinct. Effective tenant permissions require a valid session and active membership in the selected eligible tenant (`ACTIVE` or `PENDING`). |
| PERSONAL policy | PERSONAL remains single-member. Tenant permission discovery excludes invite/remove/role-assignment capabilities; the role assignment procedure rejects PERSONAL tenants. |
| ORGANIZATION policy | Preserve the existing permission matrix and active mappings. OWNER assignment of ADMIN/MEMBER is supported by the prepared procedure. ADMIN's approved Assign MEMBER capability is still missing `tenant.roles.assign` in Development; no role mapping is silently added. |
| VIEWER and ownership | `VIEWER` remains unassignable (`IsAssignable=0`). Additional OWNER assignment and ownership transfer remain denied/HOLD; role changes require exactly one current active OWNER. |
| Cross-scope/conditional access | No cross-tenant business access, Support access to tenant business data, approval delegation, sensitive export, or entitlement bypass is introduced. |
| UI | Registration navigation and routes remain permission-gated. Tenant membership controls are displayed only when effective permissions are returned; this is UX gating, not a server authorization boundary. |
| Audit | Permission seed records permission and role-permission changes in `aud.AuditEvents`. Existing tenant assignment/revocation procedures persist successful actor/target/scope/time/result/correlation events. Runtime receives no table DML or audit-table access. |

## Unified Role & Permission Matrix extension — prepared, not deployed

The approved matrix implementation is a single Platform Setup Center view and backend read model. It preserves the existing six role IDs/codes/scopes/`IsAssignable` values and uses `mst.RolePermissions` as the sole grant mapping. The unreleased v1.10 template adds tenant-type context and a rowversion concurrency token to that mapping, then evaluates PERSONAL and ORGANIZATION separately. Visible role columns are `SUPER_ADMIN`, `PLATFORM_SUPPORT`, PERSONAL `OWNER`, and ORGANIZATION `OWNER`, `ADMIN`, `MEMBER`, `VIEWER`; no contextual OWNER role records are created.

The matrix shows configured grants separately from effective allowed status, with readiness, editability, restrictions, context, and concurrency token. Updates are validated and saved in an atomic audited batch; reads, writes, and history are protected by database-backed permissions assigned only to existing `SUPER_ADMIN`.

Account Self-Service remains outside the role-scope hierarchy. Its 16 reconciled capabilities are displayed as read-only policy data in `mst.AccountSelfServicePolicies`, not as rows in `mst.Permissions` and never as `mst.RolePermissions` grants. The policy values and dispositions in [the unified matrix reconciliation artifact](KLOP_UNIFIED_ROLE_PERMISSION_MATRIX_RECONCILIATION.csv) are cross-reconciled to the existing row-level CSV. The original workbook is absent from the workspace; a DBA must verify these extracted policy rows against the approved workbook before deployment.

The revised migration seeds only the two matrix control permissions; it does not seed proposed dashboard, account, tenant, or Platform Setup permission codes. Existing permission master codes and role-master rows remain unchanged; existing tenant grants are carried into both eligible tenant-type contexts while PERSONAL membership-management operations remain effectively denied.

No SQL deployment or Development database mutation occurred. The revised v1.10 scripts passed SQL Server `PARSEONLY` only; no runtime procedure execution, permission write, positive API/UI test, or baseline freeze is claimed. Deployment requires fresh DBA/security approval because the prepared v1.10 SQL and 35-to-38 procedure allowlist were revised.

## Remaining gaps

1. The permission master/mappings are absent, so authorized Registration Center calls still receive 403 until the approved seed is applied.
2. The current live API is not the latest source and uses an elevated identity. Runtime validation is blocked until infrastructure provisions a dedicated non-admin identity and the API is restarted under it.
3. Admin Assign MEMBER is approved by the workbook but not mapped in the current database. The source/API remains fail-closed; a separate approved mapping change is required before that action can be exercised.
4. The workbook grants organization member viewing, but there is no reconciled member-list endpoint in this scope. Do not treat the UI controls as a member-list implementation.
5. No test database is approved or available; successful live Admin/Support and mutation tests remain blocked.

## Prepared implementation

- [API endpoint and OpenAPI documentation](klop-next-platform-api/docs/API_ENDPOINTS.md)
- [SQL runtime permission matrix](klop-next-platform-api/docs/SQL_RUNTIME_PERMISSION_MATRIX.md)
- [SQL deployment report](KLOP_PLATFORM_RBAC_1_0_SQL_DEPLOYMENT_REPORT.md)
- [API/UI implementation report](KLOP_PLATFORM_RBAC_1_0_API_UI_IMPLEMENTATION_REPORT.md)
- [Manual validation guide](KLOP_PLATFORM_RBAC_1_0_MANUAL_VALIDATION_GUIDE.md)

The baseline remains **APPROVED / NOT FROZEN** until the manual validation evidence is complete and the owner explicitly approves freezing it.
