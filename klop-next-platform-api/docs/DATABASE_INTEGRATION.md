# Database integration

## Authority and status

The database remains the source of truth. The API repository calls stored procedures only; it performs no direct table DML and contains no dynamic SQL. Procedure transactions and SQL audit writes are owned by the procedures.

The frozen checkpoint records v1.1 frozen and v1.2/v1.2.1 Development execution/read-only validation as **owner-reported**. A live read-only catalog check on 2026-11-21 confirmed all 20 mapped procedures, including all 9 v1.3 auth/session procedures, and the nine auth/session parameter signatures. The Development API loaded and validated SQL-backed runtime settings, passed SQL readiness, and read 7 organization types. No deployment/migration script, grant, or write Stored Procedure was executed. See [the measured dependency results](DATABASE_DEPENDENCIES.md).

## Procedure mapping

| Procedure | Source version | Endpoint/use |
|---|---|---|
| `cfg.usp_Configuration_GetByKey` | v1.1 | Startup and dynamic registration settings; readiness |
| `mst.usp_TenantType_GetAll` | v1.1 | Resolve active tenant type from database |
| `mst.usp_OrganizationType_GetAll` | v1.1 | `GET /master/organization-types` |
| `iam.usp_RegisterLocalUser` | v1.2.1 | `POST /auth/register` |
| `iam.usp_ConfirmEmail` | v1.2.1 | `POST /auth/verify-email` |
| `ten.usp_CreateTenantWithOwner` | v1.2.1 | `POST /tenants/` |
| `ten.usp_InviteExistingUser` | v1.2.1 | Tenant invitation |
| `ten.usp_AcceptMembership` | v1.2.1 | Membership acceptance |
| `ten.usp_RemoveTenantMember` | v1.2.1 | Membership removal |
| `iam.usp_AssignTenantRole` | v1.2.1 | Tenant role assignment |
| `iam.usp_RevokeTenantRole` | v1.2.1 | Tenant role revocation |
| `iam.usp_GetLocalLoginCandidate` | v1.3 DRAFT | Local login candidate lookup |
| `iam.usp_RecordLocalLoginFailure` | v1.3 DRAFT | Failed login recording |
| `iam.usp_IssueEmailVerificationChallenge` | v1.3 DRAFT | Verification resend |
| `iam.usp_CreateAuthSession` | v1.3 DRAFT | Login session creation |
| `iam.usp_ValidateSessionAccess` | v1.3 DRAFT | Bearer/session and tenant permission checks |
| `iam.usp_RotateRefreshToken` | v1.3 DRAFT | Refresh rotation and replay revocation |
| `iam.usp_RevokeAuthSession` | v1.3 DRAFT | Logout/session revocation |
| `iam.usp_GetUserProfile` | v1.3 DRAFT | `GET /auth/me` |
| `ten.usp_ListMyTenants` | v1.3 DRAFT | `GET /tenants/mine` |

Read-only `sys.parameters` metadata for the nine v1.3 auth/session procedures matched the expected parameter names, SQL types, sizes, scales, and output flags in the repository verifier (9/9 PASS). All 20 mapped procedure objects are present. This catalog evidence does not prove stored procedure body equivalence or successful execution.

## Runtime parameters

- Registration uses `Email NVARCHAR(320)`, `DisplayName NVARCHAR(150)`, `PasswordHash NVARCHAR(1024)`, `VerificationTokenHash BINARY(32)`, `VerificationExpiresAtUtc DATETIME2(3)`, optional request/correlation IDs, and `UserId`/`ChallengeId` BIGINT OUTPUTs.
- Tenant creation derives `OwnerUserId` from claims and supplies the exact tenant code, type code, display name, optional organization type/name, request/correlation IDs, and BIGINT OUTPUTs.
- Membership/role operations pass IDs and actor IDs as BIGINT and role code as VARCHAR. Session procedures pass GUID public session IDs and BINARY(32) token hashes.
- `RequestId` is VARCHAR(100), correlation is UNIQUEIDENTIFIER, string types are explicitly mapped for Unicode or ANSI procedure parameters, nullable BIGINTs retain BIGINT parameter types.
- Cancellation is propagated to every Dapper `CommandDefinition`. Timeouts come from `database.command_timeout_seconds`.

## Versioned SQL additions

The source API maps procedures for all 15 published routes, and all 20 mapped procedure objects are present in the observed Development catalog. The two v1.4 SQL additions support runtime settings and a least-privilege read permission:

1. `database/migrations/v1.4/001_runtime_settings.sql` proposes `database.command_timeout_seconds` and `security.auth_requests_per_minute`; runtime startup successfully read and validated these SQL settings, but this migration file was not executed in this task.
2. `database/migrations/v1.4/002_runtime_read_grant_TEMPLATE.sql` proposes EXECUTE permission on the existing `mst.usp_TenantType_GetAll`; it is a DBA template, not an automatic migration.
3. `database/validation/001_runtime_settings_readonly.sql` reports setting presence without changing data.
4. `database/migrations/v1.5/001_auth_session_procedures.sql` is a fail-closed DRAFT wrapper for the nine absent auth/session procedures. It reuses `sql/100_auth_session_delta.sql` without modifying that source artifact and stops if any target procedure already exists.

These are DRAFT proposals. Never execute them automatically or in Production without change approval. The v1.5 wrapper has not been run.

## Recommended Development sequence

Use an isolated Development clone and the owner-approved deployment process:

1. Check baseline versions, current definitions, and the missing-object preflight. Do not re-run historical table migrations.
2. Review v1.3 Development config seed and the v1.5 auth/session wrapper; deploy only after approval to an isolated Development clone.
3. Review the v1.2.1 and v1.3 EXECUTE grants against the actual runtime principal.
4. Review the v1.4 settings proposal and required grant; runtime settings were readable during this validation, but no migration/grant script was applied here.
5. Run v1.3 post-deploy and invariant read-only scripts. Capture database/server/time and result sets.
6. Run SQL tests from `docs/TEST_PLAN.md` against a database ending `_TEST`; retain test evidence and the effective permission list.

The integration test fixture requires committed writes, so wrapping calls in a rollback transaction is invalid. The included sample test identity can query fixture state and is not sufficient proof that the production runtime role is EXECUTE-only.

## Known database gates

- All 20 mapped procedure objects are present; the nine auth/session signatures pass read-only verification. The latest verifier reports all nine explicit EXECUTE grants to `klop_app_runtime` as FAIL and that role has no members. The current Integrated Security caller has broad `db_owner` and `db_ddladmin` membership, so effective access under that caller does not establish runtime least privilege; authenticated workflows remain blocked.
- The v1.4 SQL migration and procedure grant template were not executed here; runtime configuration values were nevertheless successfully loaded and validated at startup.
- There is no independent connection from this session to a disposable clone/test database.
- Authenticated OIDC/Entra flows, password reset, organization verification, configuration writes, idempotency, and email outbox are not supported by these procedure contracts.
- Successful auth/session, tenant-write, permission/isolation, SQL audit, concurrency, and effective runtime-grant behavior remain unverified; see [KNOWN_ISSUES.md](KNOWN_ISSUES.md).
- The observed Development SQL inspection identity is elevated (`db_owner` and `db_ddladmin`); it is not the API runtime identity. `klop_app_runtime` currently has no members, and the existing grant template is incomplete for all 20 mapped procedures. Do not claim least-privilege runtime validation until the actual API identity and full EXECUTE set are reviewed and tested.
