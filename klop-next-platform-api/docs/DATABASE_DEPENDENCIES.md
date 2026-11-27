# Database dependency validation report

Validation initially ran 2026-11-20 and was rechecked read-only on 2026-11-21 after the user reported running the v1.5 SQL script. This session independently confirmed the configured target `DEV-PC\SQLEXPRESS / KlopPlatformDB`, all 20 mapped procedures, and all nine auth/session parameter signatures. It ran no migration, grant, or data write; the user's deployment execution log was not independently inspected.

### Latest read-only recheck — 2026-11-21

- The backend resolves to `DEV-PC\SQLEXPRESS / KlopPlatformDB` with Integrated Security. The read-only baseline dependency preflight returned zero missing-object rows. The target is the existing Development database, not an approved `_TEST` clone.
- The post-deployment verifier returned **PASS for all 9/9** auth/session procedures, including schema, parameter names, SQL types, sizes, scales, and output flags. All **20/20** mapped procedure objects are present. No missing or signature-incompatible procedure was observed.
- All 17 queried authentication/runtime configuration entries have the expected active type/storage metadata. All required settings were also loaded and validated during API startup; optional SMTP username/password reference and signing-key reference rows are empty, as permitted in this Development configuration. Configuration values were not selected or recorded.
- The current API identity has effective EXECUTE permission on all 20 mapped procedures only while belonging to `db_owner` and `db_ddladmin`. `klop_app_runtime` is present but has **0 members**; only **1/20** mapped procedures has an explicit grant to that role, and **0/9** new auth/session procedures do. This is a confirmed least-privilege blocker, not runtime-role readiness.
- Follow-up inspection of the live API process confirmed its effective login maps to `dbo` and is a SQL Server `sysadmin`; this is more privileged than the earlier database-role-only observation. No existing privileges were revoked or changed.
- `KlopPlatformDB_TEST` is absent. Guarded provisioning, versioned schema deployment, configuration seeding, runtime-principal, validation, and cleanup templates are prepared but were not executed. See [SQL_RUNTIME_PERMISSION_MATRIX.md](SQL_RUNTIME_PERMISSION_MATRIX.md) and [database/testing/README.md](../database/testing/README.md).
- The configured HTTPS API readiness probe succeeded. These checks do not prove Stored Procedure body behavior, authorization, write paths, or least-privilege access.

## Observed dependencies

| Dependency | API use | Current evidence | Status |
|---|---|---|---|
| `cfg.usp_Configuration_GetByKey` | Startup runtime settings and SQL readiness | Present in `sys.procedures`; application startup completed; `/health/ready` returned HTTP 200 | PASS for startup/readiness only |
| `mst.usp_OrganizationType_GetAll` | `GET /api/v1/master/organization-types` | Present; HTTP 200 success envelope with 7 SQL-backed rows | PASS for read path |
| `mst.usp_TenantType_GetAll` | Tenant creation validation | Present in catalog; create path not called | PRESENT; functional use NOT RUN |
| Eight v1.2.1 registration/tenant/membership/role procedures | Registration, verification, tenant creation, invitation, acceptance, removal, role assignment/revocation | All 8 names present in `sys.procedures`; write paths not called | PASS for object presence; behavior BLOCKED |
| Nine v1.3 auth/session procedures | Login candidate/failure, verification resend, session create/validate/rotate/revoke, profile, tenant list | All 9 names present in `iam`/`ten`; verifier reports 9/9 parameter signatures PASS | PASS for object/signature metadata; 0/9 explicit grants to `klop_app_runtime`; functional behavior BLOCKED |

The nine targets are `iam.usp_GetLocalLoginCandidate`, `iam.usp_RecordLocalLoginFailure`, `iam.usp_IssueEmailVerificationChallenge`, `iam.usp_CreateAuthSession`, `iam.usp_ValidateSessionAccess`, `iam.usp_RotateRefreshToken`, `iam.usp_RevokeAuthSession`, `iam.usp_GetUserProfile`, and `ten.usp_ListMyTenants`. The user reports applying the v1.5 standalone script; the Development catalog corroborates all nine objects and signatures are present. This does not prove stored procedure body equivalence, runtime permissions, or successful endpoint behavior. `iam.usp_ValidateSessionAccess` remains unusable by the API until runtime grants are reconciled.

Read-only `sys.parameters` metadata was collected for the nine auth/session procedures and compared with the checked-in verifier's expected Dapper/source signatures: all 9 passed, including output flags and lengths. A separate read-only check found all 20 mapped procedures present and effective EXECUTE permission for the current Integrated Security caller. That caller is in `db_owner` and `db_ddladmin`, not `klop_app_runtime`; this elevated access is not acceptable evidence of least-privilege runtime readiness. The full source mapping is in [DATABASE_INTEGRATION.md](DATABASE_INTEGRATION.md).

## Additive migration proposal

They are alternatives: execute exactly one after DBA review. The user reports the standalone script was run; its effects are present in the configured catalog. Do not rerun it: it fails closed if any target exists. Production remains prohibited.

## v1.5 readiness review

On 2026-11-21 the read-only preflight was rerun against the backend-configured `DEV-PC\SQLEXPRESS / KlopPlatformDB` target: 139 findings, zero DDL blockers, SQLCMD exit code 0. A further post-deployment check confirmed all nine signatures; each explicit runtime-role grant check failed and `klop_app_runtime` has no members. This does not establish that `KlopPlatformDB` is an isolated/recoverable test target.

The live read-only Development catalog evidence supports **technical schema compatibility**: SQL Server 16.0.1000.6/compatibility 160; all five referenced schemas and 22 source-referenced tables/columns were present; relevant foreign keys/check constraints were enabled/trusted; the required user/challenge/session/token unique indexes, including the filtered unique refresh-token predecessor index, were present; and required security/audit/verification master codes plus configuration metadata were valid. All five schemas are owned by `dbo`. After the reported deployment, all nine auth/session procedures are present and their parameter signatures match the expected source contracts (9/9 PASS).

**DDL artifact status: READY FOR DEVELOPMENT DEPLOYMENT, conditional on explicit DBA approval and confirmation of an isolated Development target plus verified backup/recovery.** Runtime/application readiness remains **BLOCKED**. The observed Integrated Security SQL caller is in `db_owner` and `db_ddladmin`, is not a member of `klop_app_runtime`, and that runtime role has zero members and only one relevant explicit procedure grant. The existing grant template does not cover all 20 mapped API Stored Procedures. Do not treat the elevated inspection identity as the runtime identity or apply broad roles/table DML. Establish and verify the actual least-privilege API identity and complete approved EXECUTE set before enabling API auth/session traffic.

`database/validation/v1.5_001_auth_session_postdeploy_READONLY.sql` was run read-only after the reported deployment: all nine parameter signatures PASS; all nine explicit role EXECUTE grant checks FAIL; runtime role membership is empty. The verifier exits 0 when signatures pass, even if its grant result rows are FAIL, so inspect those result sets. Earlier catalog permission inspection showed no GRANT-state table DML rights for the runtime role/member set. The current API caller has effective EXECUTE for all 20 mapped objects only while holding broad `db_owner`/`db_ddladmin` membership. These metadata checks cannot validate procedure behavior. Rollback rehearsal and end-to-end/concurrency tests are **NOT RUN**; authentication is not operationally validated.

The current SQL-backed authentication/runtime configuration check found all 17 required/optional keys present with the expected value/storage types. The Development signing-key reference is empty (`KEYVAULT_REFERENCE`), and no Key Vault URI or SMTP username is configured; the Development API therefore uses its supported ephemeral signing key path. No configuration values or secrets were recorded. The configured SPA origin is `https://localhost:5173`.

## Data-safety boundary

- This validation session ran only read-only catalog/signature queries; it did not execute DDL, grants, or write procedures. The user-reported migration is corroborated by the current procedure objects/signatures.
- No business data rows were changed by this validation session.
- No registration, login failure, email verification, refresh, logout, tenant, membership, or role write was attempted.
- The persistent-write integration fixture was invoked through `dotnet test`; its current Release build passed and all 3 test cases were skipped because explicit approval, the exact `KlopPlatformDB_TEST` target, and the dedicated runtime identity were not provided.

## Still-required verification

On an explicitly approved disposable Development clone, establish and verify the actual least-privilege runtime identity and complete EXECUTE grants, then run guarded integration tests. Capture Stored Procedure outputs/errors, transaction and audit evidence, Owner-concurrency results, command-timeout behavior, and relevant configuration presence/type without recording secret values. Rehearse cleanup and follow the DBA/change-approval process in [DATABASE_INTEGRATION.md](DATABASE_INTEGRATION.md). Do not revoke privileges from existing users without explicit approval.
