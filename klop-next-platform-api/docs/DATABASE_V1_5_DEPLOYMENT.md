# v1.5 auth/session SQL migration readiness

**Deployment evidence: user-reported execution, catalog-confirmed objects/signatures.** Read-only verification on `DEV-PC\SQLEXPRESS / KlopPlatformDB` found all nine procedures present and all nine parameter signatures matching. The SQL execution log was not independently reviewed. **API auth/session status: BLOCKED** because the verifier reports 0/9 EXECUTE grants to `klop_app_runtime` and the role has no members. No successful auth/session integration test was run; do not enable auth/session traffic yet.

## Follow-up runtime identity and isolated-test gate

The actual Development API process identity was subsequently verified read-only: its effective SQL login maps to `dbo` and has SQL Server `sysadmin` privileges. `klop_app_runtime` still has no members and only 1/20 mapped procedure EXECUTE grants. This is a critical least-privilege blocker. No existing privileges were revoked, and no login, user, role membership, grant, or other database change was made.

`KlopPlatformDB_TEST` does not exist. Guarded provisioning/schema/seed/cleanup templates, an actual-runtime identity validator, and a 20-procedure permission matrix have been prepared but not executed. See [SQL_RUNTIME_PERMISSION_MATRIX.md](SQL_RUNTIME_PERMISSION_MATRIX.md) and [database/testing/README.md](../database/testing/README.md). Database creation, grants, schema deployment, seed writes, and mutation tests require explicit approval. The integration project builds; its three mutation tests skip when approval is absent.

## Evidence and status

| Check | Result | Evidence / boundary |
|---|---|---|
| Development SQL engine/target | PASS (observed) | SQL Server 16.0.1000.6, compatibility level 160, online. Reconfirm target immediately before any change. |
| Source procedure dependencies | PASS (metadata) | All five referenced schemas, the 22 source-referenced tables, and required columns were present. Existing relevant foreign keys/check constraints were enabled/trusted. |
| Constraints and indexes | PASS (metadata) | Required unique keys were present, including the filtered unique `RefreshTokens.PreviousTokenId` index used to constrain token successors. |
| Required master/configuration rows | PASS (metadata) | Required active security/audit/verification codes and valid configuration metadata were present. Values were not printed. |
| Mapped procedure catalog and signatures | PASS (metadata only) | All 20 mapped procedures are present. The nine auth/session signatures match the expected names, SQL types, sizes, scales, and output flags. Catalog metadata does not prove execution behavior. |
| Schema ownership | PASS (metadata) | The five referenced schemas are owned by `dbo`, supporting the expected ownership chain. |
| Migration execution | USER REPORTED / CATALOG CONFIRMED | User reports running the standalone migration; the nine target procedures now exist with matching signatures. No migration execution log was independently reviewed. |
| Post-deployment signatures | PASS | Read-only verifier: 9/9 procedure signatures PASS on the configured Development target. |
| Runtime least privilege | BLOCKED | Read-only verifier: 0/9 explicit EXECUTE grants for the new procedures to `klop_app_runtime`; role has zero members. The observed Integrated Security caller is a member of `db_owner` and `db_ddladmin`, not a substitute for the API runtime identity. |
| Application table DML grants | PASS (catalog metadata) | No GRANT-state table DML permissions were found for the runtime role/member set. The catalog has DENY entries on internal `sys` schema objects; these are not application-table grants. |
| Functional/security/concurrency tests | BLOCKED | No explicitly opted-in disposable `_TEST` clone was available. No login, refresh/replay, logout, tenant-isolation, audit-atomicity, or Owner-concurrency success test was run. |
| Latest backend-target preflight (2026-11-21) | PASS (DDL prerequisites only) | Read-only `sqlcmd` run against `DEV-PC\SQLEXPRESS / KlopPlatformDB`: 139 findings, 0 DDL blockers. Runtime gate remains BLOCKED because `klop_app_runtime` has no members. |
| Latest post-deployment verification (2026-11-21) | PARTIAL PASS | Nine procedures present and 9/9 parameter signatures PASS. Runtime grants are 0/9 and the role is empty. The current Integrated Security caller has effective EXECUTE for all 20 objects but is in `db_owner` and `db_ddladmin`; this is not least-privilege evidence. The verifier exits 0 based on signatures even though grant rows say FAIL. |

## Migration and dependencies

`database/migrations/v1.5/001_auth_session_procedures.sql` is a SQLCMD-only wrapper. It includes the read-only preflight, obtains a transaction-owned exclusive application lock, rechecks all nine target names, includes the unchanged `sql/100_auth_session_delta.sql`, verifies all nine procedures exist, and commits the DDL transaction. It fails if any target name already exists; investigate such an object rather than overwriting it.

The nine objects are:

- `iam.usp_GetLocalLoginCandidate`
- `iam.usp_RecordLocalLoginFailure`
- `iam.usp_IssueEmailVerificationChallenge`
- `iam.usp_CreateAuthSession`
- `iam.usp_ValidateSessionAccess`
- `iam.usp_RotateRefreshToken`
- `iam.usp_RevokeAuthSession`
- `iam.usp_GetUserProfile`
- `ten.usp_ListMyTenants`

### Procedure parameter and behavior review

| Procedure | Source parameters (SQL types) | Main dependency and review result |
|---|---|---|
| `iam.usp_GetLocalLoginCandidate` | `@NormalizedEmail NVARCHAR(320)` | Reads Users and UserCredentials; returns login candidate fields, including hash and lockout metadata. API mapping matches. |
| `iam.usp_RecordLocalLoginFailure` | `@UserId BIGINT`, `@CorrelationId UNIQUEIDENTIFIER = NULL` | Locks credential row; reads SQL lockout settings; increments/reset counts and writes security event in one transaction. API mapping matches. |
| `iam.usp_IssueEmailVerificationChallenge` | `@Email NVARCHAR(320)`, `@TokenHash BINARY(32)`, `@ExpiresAtUtc DATETIME2(3)`, `@RequestId VARCHAR(100)=NULL`, `@CorrelationId UNIQUEIDENTIFIER=NULL`, `@UserId BIGINT OUTPUT` | Invalidates prior unconsumed challenge, inserts hash-only challenge and audit record transactionally. API mapping/output matches. |
| `iam.usp_CreateAuthSession` | `@UserId BIGINT`, `@SessionExpiresAtUtc DATETIME2(3)`, `@RefreshTokenHash BINARY(32)`, `@RefreshExpiresAtUtc DATETIME2(3)`, `@RequestId VARCHAR(100)=NULL`, `@CorrelationId UNIQUEIDENTIFIER=NULL`, `@PublicSessionId UNIQUEIDENTIFIER OUTPUT` | Requires active verified/unlocked user; creates session/token and success audit in one transaction. API mapping/output matches; SQL bounds session lifetime to 30 days and refresh to session expiry. |
| `iam.usp_ValidateSessionAccess` | `@UserId BIGINT`, `@PublicSessionId UNIQUEIDENTIFIER`, `@TenantId BIGINT=NULL`, `@PermissionCode VARCHAR(120)=NULL` | Binds user to active session; if tenant is supplied, requires active membership and tenant-scoped active role/permission. API mapping matches. It permits tenant status ACTIVE or PENDING; product owner should confirm this is intended. |
| `iam.usp_RotateRefreshToken` | `@PublicSessionId UNIQUEIDENTIFIER`, `@OldTokenHash BINARY(32)`, `@NewTokenHash BINARY(32)`, `@NewExpiresAtUtc DATETIME2(3)`, `@CorrelationId UNIQUEIDENTIFIER=NULL`, `@UserId BIGINT OUTPUT` | Locks session and token; marks prior token used and inserts successor. Reuse revokes session/family and commits a critical security event before raising replay error. API mapping/output matches. |
| `iam.usp_RevokeAuthSession` | `@UserId BIGINT`, `@PublicSessionId UNIQUEIDENTIFIER`, `@CorrelationId UNIQUEIDENTIFIER=NULL` | User-bound session lookup; revokes session/tokens and writes security + audit events transactionally. API mapping matches. |
| `iam.usp_GetUserProfile` | `@UserId BIGINT` | Reads active user's profile. API mapping matches; caller must pass the user ID derived from validated claims, not request-controlled input. |
| `ten.usp_ListMyTenants` | `@UserId BIGINT` | Lists tenants only for active memberships. API mapping matches; caller must pass the authenticated claim subject. |

The API Dapper calls in `src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/Identity/KlopIdentityRepository.cs` and the shared repository helpers were reviewed against these source signatures, including all three output parameters (`UserId` for challenge issue, `PublicSessionId` for session creation, `UserId` for refresh rotation). The live Development catalog verifier matches all nine deployed signatures to those expected Dapper/source contracts. This metadata match does not prove procedure execution behavior.

### Transaction, security, and audit findings

- **Transaction safety — PASS by source review:** mutating procedures reject ambient transactions, enable `XACT_ABORT`, and use `TRY/CATCH` rollback/rethrow. Login failure, challenge issue, session creation, refresh rotation, and logout keep their intended row and audit updates atomic. Replay revocation deliberately commits before raising its replay error so revocation is preserved.
- **Refresh rotation/replay — PASS by source/catalog review:** session/token rows use update/hold locks; token hashes are `BINARY(32)`; the Development catalog has a unique token-hash key and filtered unique predecessor key, preventing duplicate hashes and multiple successors. Concurrency behavior remains **NOT RUN**.
- **Tenant isolation — PASS by source review with caller-boundary condition:** access validation joins authenticated user ID to session, tenant membership to the requested tenant, and permission through active TENANT-scope role mappings. The API must source user IDs from validated claims; DDL/EXECUTE permissions alone cannot prevent a trusted SQL caller from supplying another user ID to profile/list routines. PLATFORM permission semantics and cross-tenant functional tests remain **NOT RUN**.
- **Audit/security events — PASS by source review, NOT functionally verified:** successful session/challenge/logout operations write transaction-level audit/security rows; login failures and replay write security events. The procedures do not log raw tokens/passwords (they accept token hashes). Audit rollback/constraint-failure behavior is untested.
- **Migration artifact — PASS by artifact review:** the v1.5 script targets only the nine auth/session procedures and fails if target names already exist. The user reports it was applied and the catalog confirms the objects/signatures; this validation did not run it. Do not rerun either migration artifact against this catalog. Frozen SQL sources remain unchanged.
- **Open business rule:** session validation permits an ACTIVE membership in a PENDING tenant. Confirm product intent before enabling authenticated tenant traffic; no migration-time schema change is required to deploy the reviewed definitions.

Creation order follows the original source: login lookup/failure handling, challenge issue, session create/validate, refresh rotation, revoke, profile, tenant list. The procedures depend on the existing user/credential, challenge/session/token, tenant/membership/role, master/configuration, and audit objects described in [DATABASE_DEPENDENCIES.md](DATABASE_DEPENDENCIES.md). The preflight checks their existence, referenced columns, key index/constraint health, required master/configuration metadata, server version, and target absence. The post-deployment script checks all nine parameter signatures and reports runtime grants separately.

The source DDL uses SQL Server 2016 SP1+ `CREATE OR ALTER`; the observed SQL Server 16 engine meets the syntax version prerequisite. ScriptDom parsing is a static syntax check only; it is not equivalent to executing the migration. SQLCMD includes are relative to the repository root. Do not run these SQLCMD scripts through SSMS as plain T-SQL without resolving the includes and preserving the intended batch/transaction behavior.

## Pre-deployment checklist — DBA approval required

1. Confirm the change ticket, owner, and explicit **isolated Development clone**. Verify server and database identity in the session; do not rely on a connection alias alone. Production is prohibited.
2. Confirm a current approved backup/recovery point and that the restore procedure is known and authorized. A backup timestamp alone is not evidence of recoverability; use the organization's restore-verification policy.
3. Quiesce API instances/jobs that may depend on the affected auth/session contracts. Establish an exclusive schema-change window and prevent every other schema writer from running until commit/rollback; the SQL application lock is cooperative and does not serialize arbitrary DDL.
4. Review the frozen baseline pointer and verify `sql/100_auth_session_delta.sql` and all frozen artifacts are unchanged. Review source definitions and the v1.5 wrapper as a complete change.
5. Run `database/validation/v1.5_001_auth_session_preflight_READONLY.sql` using a DBA read-only/metadata-capable identity against the approved target. Resolve every `BLOCKER`; preserve the result with server/database/time and reviewer. The script reveals no configuration values.
6. Review object dependencies and any target-name collision. If any target exists, stop; do not use `CREATE OR ALTER` to replace it.
7. Reconcile the complete least-privilege EXECUTE set for all 20 mapped API procedures. Create/authorize the `klop_app_runtime` role membership only for the actual API identity. Do not grant table DML, `db_owner`, or `db_ddladmin`. The current `sql/200_grants_TEMPLATE.sql` is incomplete for the full mapped API surface and is not an approval to apply grants wholesale.
8. Confirm the application connection identity, JWT issuer/audience source, approved signing-secret provider, and API maintenance/rollback owner without disclosing secrets in evidence.
9. Obtain DBA/change-owner approval before executing the wrapper. Keep the migration execution log and exact artifact checksums with the ticket.

## Apply and post-deployment checklist

1. From the repository root, use SQLCMD against the approved isolated Development database only. The wrapper has `:on error exit`; do not suppress SQL errors or continue after a failed batch.
2. Confirm successful completion and the wrapper's nine-procedure verification. If any error occurs, stop and inspect transaction state/catalog; do not blindly rerun.
3. Run `database/validation/v1.5_001_auth_session_postdeploy_READONLY.sql`. Require all nine object/signature rows to PASS. Reconcile expected EXECUTE grants, runtime role membership, and absence of direct table-DML grants; also inspect broader database/schema grants and inherited roles.
4. Connect separately as the actual API runtime identity and prove only approved Stored Procedure EXECUTE access and required configuration/master read behavior. Metadata checks under a DBA identity do not establish effective runtime permissions.
5. Run only the guarded integration/security/concurrency suite against the disposable `_TEST` clone. Test registration/verification, login/JWT, refresh rotation and replay revocation, logout/revocation, tenant boundaries, last-Owner races, error/rollback audit behavior, and sensitive-log exclusion. Preserve actual runner output and sanitized SQL evidence.
6. Re-run read-only API readiness and endpoint smoke checks, then restore service. Authentication remains **NOT VALIDATED** until successful end-to-end integration evidence is reviewed.

## SSMS execution sequence after approval

Use only after the change owner confirms the isolated Development target and recoverability. Never execute against Production or the unconfirmed `KlopPlatformDB` target merely because it was used for preflight.

1. In SSMS, connect to the specifically approved Development clone. In a new query, run the following and verify the returned server/database match the approved change ticket:

   ```sql
   SELECT @@SERVERNAME AS ServerName, DB_NAME() AS DatabaseName,
		  CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')) AS ProductVersion;
   GO
   ```

2. Open `database\validation\v1.5_001_auth_session_preflight_READONLY.sql` and execute it as ordinary T-SQL. Proceed only if it returns zero `BLOCKER` rows and ends without error. Preserve the output.
3. This deployment is reported complete and its target objects/signatures are catalog-confirmed; **do not rerun either migration**. A future deployment requires a new reviewed change and an approved isolated target. The standalone script fails if target names already exist.
4. The latest run showed nine signature rows PASS. Review all grant rows separately: currently all nine new-procedure grants FAIL and the role is empty. The verifier throws on a missing/mismatched signature, but a zero exit code does not mean grant readiness. Metadata output does not prove effective permissions.
5. Before enabling API traffic, have the DBA validate effective permissions as the actual runtime identity and resolve the empty `klop_app_runtime` role. Then run functional/concurrency tests only on the approved disposable `_TEST` clone.

The standalone script is not plain T-SQL because `:on error exit` requires SQLCMD Mode. The legacy wrapper additionally uses `:r` includes; if using it instead, run from the verified repository root. Do not run either file with SQLCMD Mode disabled.

## Rollback and recovery

The proposed migration creates only Stored Procedures and does not insert or update business rows or change grants. A successful DDL commit is not rolled back by disconnecting. If deployment is partially failed, the wrapper's explicit transaction should roll back when SQL Server aborts the session; DBA must inspect `@@TRANCOUNT`, `XACT_STATE()`, and the catalog before action.

For an intentional post-commit rollback:

1. Put the API in maintenance mode or otherwise stop callers, obtain approval, and confirm the exact isolated Development database.
2. Verify each of the nine procedure definitions matches the v1.5 deployment record/checksum and that no later release or other application owns or depends on it. If ownership/change history is ambiguous, **do not drop**; use the approved database restore/recovery process instead.
3. Remove only EXECUTE grants introduced specifically for these nine objects, if any, after recording their prior state. Do not revoke pre-existing grants indiscriminately.
4. In a separately reviewed DBA script/transaction, drop only the nine exact v1.5 procedures listed above, using `DROP PROCEDURE` guarded by schema/name and the change record. Do not drop schemas/tables/indexes, delete rows, truncate data, or alter frozen SQL artifacts.
5. Verify the nine objects are absent, other mapped objects/data are intact, and API callers are safely disabled or restored to the prior supported state. If any unexpected data/object changes occurred, stop and invoke the approved backup/restore incident procedure; never restore a whole database without explicit owner approval.
6. Record rollback execution, validation output, and any reason for rollback. Re-test only in the isolated clone before proposing another deployment.

No rollback SQL is supplied for automatic execution: drop operations are intentionally a manually reviewed DBA action.

## Risks and open gates

- **BLOCKED:** Actual runtime identity is not least-privilege-ready. The observed identity is elevated and the runtime role is empty.
- **BLOCKED:** Existing grant template does not by itself cover every procedure used by the API; reconcile all 20 mapped objects and inherited privileges before integration.
- **PASS (read-only metadata only):** all nine post-deployment signatures match. **NOT RUN:** SQLCMD wrapper execution by this validation session and deployment rollback rehearsal.
- **NOT RUN:** End-to-end auth/session, tenant isolation, replay, audit, and concurrency tests. Procedure presence/signatures cannot prove behavior.
- **DO NOT RE-RUN:** The user-reported deployment is corroborated by all nine current objects/signatures. The migration script itself was not executed by this validation session; any future deployment requires a new approval and target review.
- **BLOCKED (runtime/application readiness):** Actual least-privilege runtime identity and full EXECUTE set remain unresolved; the current runtime role is empty.
- **PASS (catalog compatibility only):** Observed Development schema, referenced columns, constraints/indexes, and required master/configuration metadata are compatible with the reviewed source dependencies.

See [DATABASE_INTEGRATION.md](DATABASE_INTEGRATION.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md), and [TEST_PLAN.md](TEST_PLAN.md) for related API and test status.
