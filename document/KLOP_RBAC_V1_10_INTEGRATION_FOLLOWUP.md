# RBAC v1.10 full-stack integration follow-up — Issue #5

Status: **Source changes proposed; validation pending.** This is not a frozen release or deployment approval. The frozen review checkpoint in PR #4 remains unchanged.

## Implementation
- Existing matrix routes and generated contracts are retained. UI review is tied to the exact batch and reason returned by the validate endpoint; edits and save controls are locked while work is pending. Stale validation/save conflicts require an explicit server reload with discarded local changes. Failed saves require a fresh review.
- Platform Setup and matrix page require a successful, fresh access discovery before exposing controls. Tenant membership controls fail closed during unsuccessful or pending permission lookups; PERSONAL membership administration is not exposed even if an inconsistent response contains grants. Backend authorization is authoritative.
- Matrix save invalidates matrix, history, effective tenant permission and platform registration permission queries. History timestamps use UTC; unknown effective status is shown as not evaluated.
- Backend returns the agreed context order (PLATFORM, PERSONAL, ORGANIZATION), rejects null change entries before calling the repository, and reports update access only in conjunction with read access. Existing role IDs, grants, API paths, and SQL schema are not changed.
- Added regression cases for unauthorized UI, in-flight validation, reason changes, stale save/reload, PERSONAL membership, invalid batch entries, and column order.

## Database: owner-manual only
No SQL was changed or executed in this follow-up. The existing unpublished package remains the candidate, not an approved deployment. Static checks inspected the matrix service, route mappings and existing concurrency handling in script 003, not a complete independent SQL dependency or grants audit.
Refer to `document/KLOP_PLATFORM_RBAC_1_0_MANUAL_VALIDATION_GUIDE.md` for approval gates, backup/recovery and exact sequence:
1. `klop-next-platform-api/database/migrations/v1.10/001_rbac_preflight_READONLY.sql`
2. `klop-next-platform-api/database/migrations/v1.10/002_platform_registration_permissions_APPROVAL_TEMPLATE.sql`
3. `klop-next-platform-api/database/migrations/v1.10/003_tenant_permission_policy_APPROVAL_TEMPLATE.sql`
4. `klop-next-platform-api/database/migrations/v1.10/004_rbac_postdeploy_validation_READONLY.sql`
5. `klop-next-platform-api/database/security/v1.10_runtime_identity_and_grants_APPROVAL_TEMPLATE.sql`
6. `klop-next-platform-api/database/security/v1.10_runtime_identity_validation_READONLY.sql`

Before steps 2–5, reconcile account policy rows against the approved original workbook, verify the exact 38-procedure runtime allowlist against the actual dependencies, obtain DBA/security approval, verify a backup, and provision the approved non-admin runtime identity. Stop on any mismatch. Existing manual guide is authoritative for SQLCMD settings and execution prerequisites. No test database or automated migration is authorized.

## Validation
Static source and API contract inspection only. New tests are supplied but were not executed in the connected editing environment; no SQL execution, PARSEONLY, live API call or deployment occurred.
Run on the feature branch in an approved development environment, with live integration/mutation suites disabled:
- Backend: `dotnet test tests/KLOP.Platform.UnitTests/KLOP.Platform.UnitTests.csproj --configuration Release` from klop-next-platform-api.
- UI: `npm ci`, `npm run api:types`, `npm test`, `npm run typecheck`, `npm run build` from klop-next_ui (inspect generated changes against the committed schema).
- After owner-manual SQL approval and deployment, verify matrix access by role, scope columns, validate-only no-write, approved disposable change save + audit, stale conflict reload, registration read access, PERSONAL denial and ORGANIZATION effective permissions. Never mutate real membership just for testing.

## Remaining gates
Full workbook/SQL reconciliation, actual build/test results, least-privilege runtime identity, existing Development end-to-end tests, and owner PR approval. Keep PR draft until these are resolved or owner explicitly accepts the remaining scope. Do not merge, deploy or declare production readiness automatically.
