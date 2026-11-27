# Combined validation plan (one delivery, no staged baselines)

**Existing evidence:** v1.1/v1.2/v1.2.1 deployed to Development without errors and prior read-only validation reported PASS by project owner. This is historical reported status, **not** proof that v1.3 scripts/tests have run.

## Automated tests included

- `KLOP.Platform.UnitTests`: PBKDF2 encoding/verification, random salt, format rejection, 256-bit verification token hashing, email input sanity checks.
- `KLOP.Platform.IntegrationTests`: registration → email verification → tenant OWNER; last-OWNER revoke/remove denial; actual session validation → refresh rotation → replay revocation; organization invitation/acceptance/OWNER assignment → two-session race to remove OWNER; invalid master code and duplicate email rejection.
- `scripts/validate_static.py`: static repository SP reference check. A successful result is **not** a SQL/.NET runtime pass.
- `sql/400_invariants_READONLY.sql`: owner count, PERSONAL active membership count, role-scope consistency, orphan token, audit volume report.

## Integration test setup (explicit mutation opt-in)

Create a **disposable clone** of the Development schema under database name ending `_TEST`, e.g. `KLOP_PLATFORM_TEST`. Apply the **reviewed** v1.3 SQL delta and grants. Tests write persistent random fixture users/tenants; they cannot be wrapped in an outer transaction because the original SPs reject nested/external transactions. Never run on Production or on normal Development with important test data.

Set environment variables in your terminal (no secrets shown in logs):

- `KLOP_TEST_SQL_SERVER` — verified clone server
- `KLOP_TEST_SQL_DATABASE` — database name ending `_TEST`
- `KLOP_TEST_SQL_AUTH` — `IntegratedSecurity` or `ActiveDirectoryDefault`
- `KLOP_TEST_ALLOW_MUTATION` — exact value `I_UNDERSTAND_TEST_DATA_IS_PERSISTENT`

Then run:

```bash
dotnet test tests/KLOP.Platform.UnitTests/KLOP.Platform.UnitTests.csproj
dotnet test tests/KLOP.Platform.IntegrationTests/KLOP.Platform.IntegrationTests.csproj
```

If the opt-in variables are not set, integration tests **fail loudly** rather than showing a misleading PASS. Use a separate privileged fixture assertion identity for direct read-only assertions where runtime principal cannot read tables; confirm API runtime role only has EXECUTE rights. The included sample harness uses one identity for convenience and must be adapted for principal isolation before security certification.

## Coverage matrix (all statuses start NOT RUN)

- Registration unique email + case folding; generic anti-enumeration response; verification one-time and expiry; resend.
- PERSONAL tenant creation, one active OWNER, attempts to add second PERSONAL owner; ORGANIZATION tenant PENDING with legal type.
- Invitation, acceptance, MEMBER role assignment, removal; foreign tenant actor, invalid/inactive masters, cross-scope roles.
- Last OWNER removal/revocation and two-session race; forced audit failure rollback and permission-grant audit.
- Login success/failure lockout, session creation, JWT signature/audience expiry, session revocation, refresh replay/multiple simultaneous requests, origin/cookie CSRF.
- No direct DML from API runtime principal; no secrets/PII in logs; 5xx mapping; SMTP retry and outage; Key Vault principal access.
- Full API integration through HTTPS and SPA, including Microsoft Entra/OIDC (separate pending architecture item).

Capture raw test execution output, SQL Server time, database name, test ID, observed versus expected result, evidence path, reviewer, and defect ID in `KLOP_Integrated_Tracker_v1.3_DRAFT.xlsx`.
