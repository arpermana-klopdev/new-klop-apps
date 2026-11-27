# Authentication Compatibility Report

**Project:** KLOP Platform API  
**Database target:** `KlopPlatformDB`  
**Validation date:** 2026-11-22  
**Status:** Backend refactor checks passed; legacy password compatibility remains **BLOCKED** pending authoritative algorithm evidence.

## 1. Refactored backend validation

- The solution remains split across API, Application, Domain, Infrastructure, UnitTests, and IntegrationTests projects.
- `dotnet build KLOP.Platform.sln` succeeded with **0 warnings and 0 errors** after the changes in this work.
- The complete non-mutating unit-test project passed: **25 passed, 0 failed, 0 skipped**. Integration tests were not run because they can mutate persistent data.
- DI regression tests resolve the repository, token issuer, email sender and `AuthenticationService` without opening a SQL connection. `AuthenticationService` is registered in API service registration.
- Route-contract tests passed. `/api/v1/auth/login`, refresh, logout, and the other authentication routes remain mapped; no endpoint, DTO, status, response-envelope, or cookie contract was changed. The development Swagger UI is registered by the request pipeline.
- The repository still calls stored procedures by their existing names. A read-only catalog check found **20/20 mapped procedures** present. The read-only v1.5 signature check passed for all nine authentication/session procedures it covers (zero parameter mismatches). These checks establish object/signature compatibility, not procedure behavior or permission under a least-privilege principal.

## 2. Root cause of `INVALID_CREDENTIALS`

`PasswordCodec.Verify` currently accepts only the four-part `pbkdf2-sha256$rounds$salt$digest` format. A stored value in `100000.saltBase64.hashBase64` form does not pass its prefix/separator checks, so verification returns `false` before any digest comparison. For an existing candidate, `AuthenticationService.Login` consequently returns no session, and `/api/v1/auth/login` responds `401 INVALID_CREDENTIALS`; the existing failed-login recording path is also invoked for a password mismatch.

The encoding mismatch is confirmed by source. **The historical KDF and its exact parameters are not confirmed.** A search of the available local project/source snapshots found the current password writer but no authoritative historical writer or approved legacy test vector. The format and iteration number alone do not prove PBKDF2-HMAC-SHA256, salt/digest lengths, or Base64 rules.

## 3. Password compatibility implementation

No legacy verifier branch was added in this work. Choosing SHA-256 (or another KDF) without the historical writer/specification would risk rejecting the actual existing credentials or asserting an unverified credential contract. That would not satisfy the requirement to verify the approved legacy format. No hash was queried, logged, copied, or changed; no database write or real-account login was performed.

The current writer remains unchanged: new passwords use PBKDF2-HMAC-SHA256 with 600,000 iterations, a random 32-byte salt, a 32-byte digest, and the `pbkdf2-sha256$...` encoding. Current-format, wrong-password, and malformed-hash tests passed. A valid legacy-vector test is **not yet possible** until the authoritative writer/specification or a vetted non-secret deterministic vector is supplied.

## 4. Authentication flow review

- Login candidate retrieval uses `iam.usp_GetLocalLoginCandidate`; SQL returns the stored hash and account status without transforming the hash.
- The Application layer verifies the password, then requires an active account, verified email, and expired/absent lockout before creating a session.
- Mismatched passwords for an existing candidate call `iam.usp_RecordLocalLoginFailure`. The existing lockout/audit behavior was not changed.
- Success hashes a new refresh token and calls `iam.usp_CreateAuthSession`; the session stored procedure rechecks active/verified/unlocked status. The access JWT is issued after session creation.
- Refresh rotates hashed tokens via `iam.usp_RotateRefreshToken`; logout revokes the current session via `iam.usp_RevokeAuthSession`.
- Unit tests cover current valid/invalid/malformed hashes, inactive/unverified/locked candidates, authentication failure, successful session creation and token-issuer orchestration. No login, refresh, or logout E2E was claimed or executed.

## 5. Runtime SQL identity and permissions — read-only

Read-only SQL checks were run against `KlopPlatformDB` using integrated authentication; no SQL login, role, grant, schema, or data was changed.

- The checked caller maps to **`dbo` and `sysadmin`**, and is also `db_owner`.
- The caller is **not** a member of `klop_app_runtime`.
- All **20/20** mapped procedures report effective EXECUTE for this caller, but that is inherited from its administrative privileges and does **not** establish least-privilege runtime access.
- `klop_app_runtime` has **no members** and only **1 explicit EXECUTE grant** among the 20 mapped procedures: `mst.usp_TenantType_GetAll`. The nine auth/session grants checked by the read-only post-deployment script are all absent.

The project connection factory supports integrated security; this permission result is a blocker for least-privilege operation. A DBA must provision/approve the intended runtime identity and grants. No permission changes were made.

## 6. Changed files

- `tests/KLOP.Platform.UnitTests/Authentication/AuthenticationServiceTests.cs` — adds database-free tests for failed login, account eligibility, session creation, refresh-token hashing, and access-token issuance.
- `tests/KLOP.Platform.UnitTests/Persistence/InfrastructureRegistrationTests.cs` — verifies `AuthenticationService` and its registered dependencies resolve without opening SQL connections.
- `AUTHENTICATION_COMPATIBILITY_REPORT.md` — this report.

`PasswordCodec` was deliberately not changed because its legacy algorithm contract could not be authoritatively verified from the available source.

## 7. Manual Swagger login guide (not executed)

**Do not run this while the legacy verifier is unresolved or while the API is using the reported admin identity.** After the historical format is verified and the DBA-approved runtime identity/grants are in place:

1. Start the Development API using the approved non-admin runtime identity and open its Development Swagger UI (`/swagger`).
2. Select `POST /api/v1/auth/login` and test one account at a time:
   - `super.admin@klop-test.example`
   - `platform.support@klop-test.example`
3. Enter the matching account password only from the approved secure credential source in the Swagger request body. Do not put it in this report, shell history, source, screenshots, or logs.
4. A successful response should return the existing access-token envelope and set the refresh cookie. Do not claim E2E success until a human completes this check.
5. Stop after a single `401`; do not retry repeatedly because failed attempts are recorded and may trigger lockout. Do not use these accounts for automated diagnosis. Test refresh/logout only as a separate approved manual check after login succeeds.

## 8. Remaining blockers

1. Obtain the authoritative legacy password writer/specification and confirm KDF, iteration count, salt and digest sizes, and canonical Base64 rules. Then add deterministic valid/invalid legacy vectors and implement only that verified format with bounded parsing and constant-time comparison.
2. Have the DBA resolve the `dbo`/`sysadmin` runtime identity and grant the approved minimum EXECUTE permissions to the intended runtime role; verify under the actual API process identity.
3. After those gates, run the manual login flow. Until then, password compatibility and login E2E remain **unverified**.
