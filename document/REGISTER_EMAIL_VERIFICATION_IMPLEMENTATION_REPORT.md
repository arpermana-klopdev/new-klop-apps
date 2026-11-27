# Registration and Email Verification Implementation Report

**Status:** Source implementation and safe local validation complete. Development rollout and manual email testing are **not approved or complete**.  
**Scope:** Development-only Terms bypass, policy-driven registration/password validation, and email-link verification. No SQL migration, database configuration, application configuration, account, or email was changed.

## Delivered

### Backend policy and registration

- Added public, rate-limited `GET /api/v1/auth/registration-policy`, returning whether Terms are required, the configured password length bounds, and currently enabled registration types. Responses are marked `Cache-Control: no-store`.
- Added `Registration:DevelopmentTermsBypassEnabled`, defaulting to `false`. Startup rejects it outside Development and rejects incompatible Terms-enforcement settings. Production still requires Terms enforcement.
- Registration validation now requires an enabled registration type, enforces the database-backed minimum password length and shared 128-character maximum, and only accepts omitted Terms fields when the trusted Development bypass is active.
- The bypass flag is supplied to persistence by server configuration, never by the client. The SQL procedure independently requires the explicit flag, disabled consent enforcement, and the exact Development SQL Server/database. When bypassed, it creates no consent row and records a policy-bypass audit event.

### Frontend and API contract

- The registration UI now loads the effective server policy before allowing submission. A policy-fetch failure is visible and fails closed.
- The form uses the server password bounds and allowed registration types.
- Terms content and metadata are not requested or displayed when the policy says Terms are not required. In that case the registration request contains only name, email, password, and registration type. With Terms required, the existing explicit acceptance/version flow remains in effect.
- OpenAPI now documents the policy endpoint and makes the Terms fields optional in the request schema; generated TypeScript API types were refreshed.
- `/verify-email#userId=...&token=...` links are strictly parsed and submitted once. The fragment is replaced immediately before the request, invalid links are rejected without submission, and successful verification routes to Login without signing the user in. Manual verification and resend remain available after an error.

### SQL artifacts

- Added [001_registration_terms_policy.sql](./klop-next-platform-api/database/migrations/v1.8/001_registration_terms_policy.sql), a versioned replacement for the atomic registration procedure. It preserves user, credential, challenge, DRAFT application, and audit writes. It was **not applied**.
- Added [registration_terms_enforcement_DEV_TEMPLATE.sql](./klop-next-platform-api/database/security/registration_terms_enforcement_DEV_TEMPLATE.sql), an approval-gated Development-only template for the existing consent-enforcement setting. It defaults to no change and does not configure the application bypass. It was **not executed**.
- The template preserves the configuration contract's `true`/`false` values and bounds the approval ticket to the audit request-ID size.

## Verification

| Check | Result |
|---|---:|
| Frontend `npm run typecheck` | Passed |
| Frontend `npm test -- --run` | 76 passed |
| Frontend `npm run api:types` | Passed |
| Backend `dotnet build KLOP.Platform.sln --no-restore` | Passed, 0 warnings/errors |
| Backend `dotnet test tests/KLOP.Platform.UnitTests/KLOP.Platform.UnitTests.csproj --no-restore` | 113 passed |
| SQLCMD `SET PARSEONLY ON` for both new SQL artifacts | Passed; no SQL statements were executed |

No integration tests, API startup, registration, database writes, or mail sends were performed. Build and unit-test success do not establish Development runtime readiness or email delivery.

## Rollout blockers and safeguards

Prior read-only Development evidence dated 2026-11-24 found the consent-enforcement value `false`, no Terms version rows, zero registration applications, zero members of `klop_app_runtime`, and only 8 of 28 reviewed procedure grants. The inspection identity was elevated and does not establish application runtime permissions. These values have not been changed or rechecked during implementation.

The sanitized SMTP readiness review found host/port metadata, but the sender address is missing or invalid; Development TLS is disabled; SMTP username/secret-reference readiness and Key Vault/runtime identity are unverified. `RuntimeSettings.Load` requires a valid sender address, so startup and actual delivery remain blocked until an authorized operator resolves the configuration. No secret values were read or included.

Before any Development manual test:

1. Obtain product/security/DBA approval and review/apply the migration only to the intended Development database.
2. Verify the non-admin runtime identity and exact stored-procedure grants, including the updated registration procedure.
3. Keep `Registration:DevelopmentTermsBypassEnabled` off by default. Enable it only in the approved Development process environment; never set it from a request, shared configuration, or Production.
4. Confirm the existing database consent-enforcement setting is `false`; make no change if it remains so. Any future change requires a separate approved ticket and the gated template.
5. Resolve sender/TLS/secret-reference/Key Vault/runtime identity prerequisites and use only an approved local sink or explicitly approved non-production recipient.

The implementation does not create Terms records, synthesize consent, mark legal documents approved, enable the bypass automatically, weaken login verification, or enable any Production bypass.

See the [Development configuration checklist](./REGISTER_DEVELOPMENT_CONFIGURATION_CHECKLIST.md) and [manual test guide](./REGISTER_MANUAL_TEST_GUIDE.md). The earlier [email readiness report](./EMAIL_VERIFICATION_READINESS_REPORT.md) remains a dated pre-implementation snapshot.
