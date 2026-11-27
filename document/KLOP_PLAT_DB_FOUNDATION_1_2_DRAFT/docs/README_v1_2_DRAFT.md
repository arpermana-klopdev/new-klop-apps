# KLOP PLATFORM — Database Foundation KLOP-PLATFORM-DB-FOUNDATION-1.2 (DRAFT)

## Baseline lineage
- **Source:** KLOP-PLATFORM-DB-FOUNDATION-1.1, FROZEN, 2026-11-18
- Source workbook SHA-256: `6990f651b0ea6bccc718d0df35e1387db923aac17a7d983ab211bf33f12f50fd`
- Source SQL ZIP SHA-256: `9bf6bf00c874e01fbb27b35891dc43512fe0ddda3234804ec48d6f0b79edcdfb`
- **No v1.1 source file was modified.** This directory contains an additive v1.2 candidate only.
- **Approval status:** DRAFT, not frozen. **No SQL execution against a live SQL Server occurred.**

## Proposed scope
- 17 tables added: 3 new business/system catalog masters (`mst`) and 14 runtime tables (`iam`, `ten`, `aud`).
- No changes to the 15 `mst` tables and 1 `cfg` table in v1.1.
- 39 proposed FK constraints, 30 indexes, 10 check constraints.
- Global users, local password credentials, external identity links, verification challenges, sessions,
  refresh-token rotation lineage, personal/organization tenants, many-to-many memberships,
  platform/tenant role assignments, and append-only audit/security/business event stores.
- Application diagnostic logs remain structured Serilog events forwarded to an approved operations
  sink (not SQL table by default). Configuration and secrets rules from v1.1 remain unchanged.

## Migration order (Development only)
Prerequisite: review/execute/test the original v1.1 draft in a separate **Development** database.
Then review these new scripts, in order:
1. `sql/00_Preflight/000_v1_1_prerequisites.sql`
2. `sql/01_Tables/010_new_masters.sql`
3. `sql/01_Tables/020_iam_tenant.sql`
4. `sql/01_Tables/030_audit_events.sql`
5. `sql/02_Constraints/040_foreign_keys_indexes_checks.sql`
6. `sql/03_Seed/050_new_master_seed.sql`
7. `sql/04_Validation/090_smoke_checks.sql`

Do **not** run in Production. These scripts provide additive DDL + starter reference seed + structural
smoke checks only. They are not proven repeatable migrations or a production deployment recipe.

## Non-negotiable controls (pending implementation)
- No direct INSERT/UPDATE/DELETE grants on these tables to runtime API identities.
- Cross-scope role assignments and user↔tenant isolation MUST be validated in audited, transactional
  stored procedures. DB foreign keys alone do not prove correct scope.
- PERSONAL tenant: exactly one active OWNER; ORGANIZATION tenant: never remove the last active OWNER.
  Use isolation/locks to prevent concurrent last-owner races.
- Password hashes, challenge hashes and refresh token hashes only; never log or persist raw secrets.
  Verify external OIDC issuer/subject and allowlists in an approved security layer.
- Insert relevant `aud.AuditEvents` in the **same** transaction as critical state mutation.
- `aud.*` event tables are append-only under runtime permissions; define archive/retention separately.
- `aud.BusinessEvents` is an audit history, **not** an outbox for reliable event publication.
- Audit context, correlation, redaction, tenant isolation and least-privilege execution required.
- `cfg.SystemConfigurations` sensitive edits/approvals remain gated by future audited SPs.
- Legal requirements and organization document verification need compliance review.

## SQL Server validation still required
1. SQL Server parse/compile, UTF-8 script encoding, index key limits, FK/check enablement.
2. Seed idempotency under concurrency and incremental migration replay checks.
3. Test identity + tenant scope isolation and role escalation prevention.
4. Test concurrent owner deletion/suspension and concurrent session refresh/replay.
5. Ensure transactional rollbacks also handle required audit events correctly.
6. Test restore/rollback plan, growth, logging volume, and operational retention.
7. Review collation and case normalization of `NormalizedEmail` and `TenantCode`.
8. Define effective DB roles/permissions and protect all write operations.

## Governance conflict requiring ACR
An older frozen architecture document (ARCH-04, v1.0) limits a tenant user to one tenant.
The newer frozen DB v1.1 explicitly approves global users and many-to-many tenant memberships
(B03). v1.2 follows **v1.1** for DB modeling, but this cross-baseline conflict is recorded
as an **OPEN** Architecture Change Request, not treated as approved resolution.

## Approval / freeze workflow
- Review `KLOP_Platform_Baseline_v1.2_DRAFT.xlsx` (sheets prefixed `v1.2`).
- Resolve critical open decisions; implement/test audited write SPs.
- Obtain explicit project-owner approval before marking v1.2 FROZEN.
- Preserve original v1.1 workbook/zip and their hashes as immutable historical snapshots.
