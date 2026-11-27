# Legacy Password Verifier Fix Report

## Changed files

- `src/KLOP.Platform.Application/Features/Security.cs` — retains the existing current-format writer/verifier and adds an exact encoded-length check before Base64 decoding. The legacy branch accepts only `100000.saltBase64.digestBase64`, with the specified 16-byte salt and 32-byte digest.
- `tests/KLOP.Platform.UnitTests/Authentication/AuthenticationServiceTests.cs` — regression tests cover successful login for the verified legacy vector and wrong-password rejection, login-failure recording, and prevention of session creation.
- `LEGACY_PASSWORD_FIX_REPORT.md` — this report.

Existing `SecurityTests.cs` already contains the deterministic vector and verifier rejection cases; it was run but did not require modification.

## Algorithm verification

- Legacy verification uses PBKDF2-HMAC-SHA256 with exactly 100,000 iterations, a 16-byte decoded salt, and a 32-byte digest.
- The supplied deterministic vector (`KLOP-Legacy-Test-Only!`) passes the unit test against the expected digest; the same encoded hash rejects a different password.
- Base64 must be canonical, and encoded segment lengths are checked before decoding. Digest comparison uses `CryptographicOperations.FixedTimeEquals`.
- Current-format writing remains PBKDF2-HMAC-SHA256 with 600,000 iterations, a 32-byte random salt, a 32-byte digest, and the unchanged `pbkdf2-sha256$rounds$salt$digest` format. Its verifier remains supported.
- No other historical hash formats are accepted.

## Validation

- Complete solution build: **PASS** — `dotnet build KLOP.Platform.sln --no-restore`; 0 warnings, 0 errors.
- All non-mutating unit tests: **PASS** — 34 passed, 0 failed (`KLOP.Platform.UnitTests`).
- Authentication behavior assertions continue to cover inactive, unverified, and locked accounts, and wrong-password lockout-failure recording. No endpoint contracts, role checks, audit behavior, or authentication service policy were changed.
- Database-writing integration tests were not run. No real-user login, credential, database, SQL grant, or login-identity change was made.

## Separate blocker: least-privilege SQL runtime

The latest recorded read-only Development evidence reports that the live API SQL caller maps to `dbo` and is a SQL Server `sysadmin`. The `klop_app_runtime` role has no members and only 1/20 mapped-procedure EXECUTE grants, including 0/9 auth/session procedure grants. Thus runtime least-privilege readiness and SQL-backed authentication remain blocked; the elevated caller does not establish least-privilege access. `KlopPlatformDB_TEST` is absent, so mutation-based SQL verification remains gated. No grants, identities, or database objects were modified for this password fix.

Evidence: `docs/DATABASE_DEPENDENCIES.md` (read-only recheck dated 2026-11-21) and `docs/DATABASE_V1_5_DEPLOYMENT.md`.

## Remaining blockers

- Resolve the least-privilege runtime identity and approved complete EXECUTE grants under DBA/change approval, then validate using an explicitly approved disposable `_TEST` database.
- End-to-end SQL-backed authentication and other mutation tests remain unverified until those gates are met.
