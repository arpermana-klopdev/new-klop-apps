# KLOP Register Full-Stack Review Report

**Review date:** 2026-11-24  
**Scope:** Development Register and email-verification review only. No application, SQL, database, runtime configuration, or frozen-baseline changes were made. No account was created and no email was sent.

## Executive assessment

| Area | Assessment |
|---|---|
| PERSONAL registration | **PARTIAL / BLOCKED in current Development state.** The current UI sends PERSONAL intent and explicit Terms consent. The API and SQL contract support it, but the Development database has no legal version to accept, and SQL consent enforcement is currently off only for legacy requests without a registration type. Typed registration still requires a current, scoped, PUBLISHED Terms version. |
| ORGANIZATION registration | **PARTIAL / BLOCKED in current Development state.** Same blockers as PERSONAL. Organization-specific onboarding requirements are a separate later flow and are not part of account registration. |
| Frontend/backend contract | **Implemented in current source.** UI posts to `POST /api/v1/auth/register` with `fullName`, `email`, `password`, `registrationType`, `termsDocumentVersionId`, and `termsAccepted: true`; Confirm Password is not sent. |
| Database integration | **Source implemented; runtime execution not verified.** Registration is designed as one stored-procedure transaction, but the intended least-privilege API identity is not active and grants are incomplete. No SQL-backed registration was attempted. |
| Email verification | **PARTIAL.** Token generation, SMTP sender, verify/resend APIs, and verified-email login gate exist. No email was sent or delivered during this review; the email link's fragment is not consumed by the UI automatically. |
| Development Terms approval bypass | **Not ready to activate.** A fail-closed Development-only policy can be designed without weakening Production, but there is currently no Terms version row. Without an existing version and immutable content/hash, versioned consent cannot be recorded safely. |

## Evidence and safety limits

Fresh read-only checks on 2026-11-24 targeted `DEV-PC\SQLEXPRESS` / `KlopPlatformDB`:

- All **28/28** reviewed API stored procedures exist.
- `klop_app_runtime` has **0 members** and **8 explicit EXECUTE grants** across the 28-procedure allowlist.
- No active SQL session named `KLOP.Platform.API` was found.
- The Development catalog contains **0 legal document version rows** and **0 registration application rows**.
- `registration.legal_consent_enforcement` is active and currently `false`.
- SMTP-related configuration keys are present and active by metadata; their values and any secret values were not read or included in this report.
- The inspecting SQL session was `DEV-PC\rajaa`, mapped to `dbo`, with `sysadmin` and `db_owner` membership. This is **not** evidence of the API process identity or its permissions.

The Development API configuration selects Windows Integrated Security for SQL. The API process was not running, so its effective Windows identity, SQL grants, environment overrides, SMTP connection, and private legal-document storage configuration could not be verified. No registration or email-verification Stored Procedure was invoked. These observations agree with the latest database state described in [SQL_V16_DEPLOYMENT_CORRECTION_REPORT.md](./klop-next-platform-api/SQL_V16_DEPLOYMENT_CORRECTION_REPORT.md), while the counts above were rechecked read-only for this review.

## Current architecture and endpoint mapping

### Frontend

- `/register` and `/verify-email` are public routes in [App.tsx](./klop-next_ui/src/app/App.tsx).
- [LoginPage.tsx](./klop-next_ui/src/features/auth/LoginPage.tsx) implements the Register type choice, form, Terms modal workflow, accepted state, resend form, and manual verification form.
- [RegistrationFlowContext.tsx](./klop-next_ui/src/features/auth/RegistrationFlowContext.tsx) keeps registration type, temporary form values, and Terms decision in React memory; it does not persist them in browser storage.
- [auth.ts](./klop-next_ui/src/api/auth.ts) calls the shared API client. [client.ts](./klop-next_ui/src/api/client.ts) uses `VITE_API_BASE_URL` when supplied, otherwise the relative `/api/v1` base path.
- [legal.ts](./klop-next_ui/src/api/legal.ts) requests current Terms metadata from `GET /api/v1/public/legal/terms/current?registrationType=...`.
- [termsDocuments.ts](./klop-next_ui/src/features/auth/termsDocuments.ts) maps published API metadata and retains a local draft-PDF fallback. The fallback has no database version ID and is not eligible consent.

### Backend and database

- `POST /api/v1/auth/register`, `POST /api/v1/auth/verify-email`, and `POST /api/v1/auth/resend-verification` are anonymous, auth-rate-limited routes in [AuthenticationEndpoints.cs](./klop-next-platform-api/src/KLOP.Platform.Api/Endpoints/Authentication/AuthenticationEndpoints.cs).
- [AuthenticationHandlers.cs](./klop-next-platform-api/src/KLOP.Platform.Api/Endpoints/Authentication/AuthenticationHandlers.cs) keeps Register and resend responses generic HTTP 202; Verify delegates to the existing challenge-confirmation flow.
- [AuthenticationService.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Authentication/AuthenticationService.cs) hashes passwords and tokens, calls the repository, then sends verification email after registration commits.
- [AuthenticationValidators.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Authentication/AuthenticationValidators.cs) validates the registration payload. `RegistrationRequest` in [Contracts.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Contracts.cs) includes the compatible `fullName` alias and optional registration/consent fields.
- [KlopIdentityRepository.cs](./klop-next-platform-api/src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/Identity/KlopIdentityRepository.cs) calls the authentication stored procedures through Dapper; it does not issue table CRUD.
- [002_registration_onboarding_procedures.sql](./klop-next-platform-api/database/migrations/v1.6/002_registration_onboarding_procedures.sql) defines the v1.6 registration transaction. It creates the user, credential, email challenge, registration application, consent record, and audit records together when registration intent is present. It does not create a Tenant or assign a role.

## Registration journey review

| Step | Finding |
|---|---|
| Open Register | **Implemented.** `/register` enters the type-choice flow. |
| Select PERSONAL or ORGANIZATION | **Implemented.** Stable codes are kept in React context and are sent in the current request. They are onboarding intent only, not a role or permission. |
| Enter registration fields | **Implemented.** Full Name, Email, Password, and Confirm Password are presented for both types. Confirm Password is client-only. |
| Validate | **Partial.** Name, email, confirmation equality, and maximum lengths are checked in the UI and backend. The UI accepts any non-empty password up to 128 characters; backend policy comes from `security.password.min_length` and is bounded to 12–128. This guarantees a mismatch for some inputs: the UI can enable submission for a password that the API rejects. |
| Display and accept Terms | **Implemented, intentionally gated.** Current published metadata and its exact version ID are fetched. The checkbox lives in the modal, is not pre-checked, and must be explicitly selected. Draft acknowledgment is explicitly not consent. The Register button remains disabled without a current published document and accepted version. |
| Submit | **Implemented in source.** The UI sends canonical `fullName`, email, password, selected `registrationType`, the returned Terms version ID, and `termsAccepted: true`. It does not send the confirmation password or client acceptance time/hash. `TERMS_VERSION_OUTDATED` triggers a fresh Terms review and acceptance. |
| Handle duplicate and API errors | **Implemented in source.** A duplicate normalized email is translated to the same generic 202 response as an accepted registration. Validation errors are server-authoritative; rate limiting maps to 429. No account-existence distinction is displayed. |
| Show email instructions | **Implemented with generic wording.** The accepted screen does not claim that a message arrived or sign the user in. Registration type remains temporary UI state; no Tenant is created. |
| Verify email | **Partial integration.** The backend email contains a link to `/verify-email` with `userId` and token in the URL fragment. The frontend verification form currently asks the user to enter both fields and does not parse or clear that fragment. The user must manually extract the values; clicking the link alone does not submit verification. |
| Return to Login | **Implemented.** Successful verification shows a success message and switches to Login; it does not automatically sign the user in. |

### PERSONAL and ORGANIZATION specifics

Both choices use the same account-registration DTO and stored procedure. The database application records the stable registration type, and subsequent profile/onboarding data is type-specific. The current registration source does not collect personal identity details or organization records, create a Tenant, or assign roles. Organization requirements and submission policies belong to a later onboarding flow; Development currently has no registration application rows and no approved policy activation.

The current frontend contract is confirmed in [LoginPage.tsx](./klop-next_ui/src/features/auth/LoginPage.tsx), [auth.ts](./klop-next_ui/src/api/auth.ts), and [schema.d.ts](./klop-next_ui/src/api/schema.d.ts). The older [KLOP_NEXT_REGISTRATION_UI_IMPLEMENTATION_REPORT.md](./klop-next_ui/KLOP_NEXT_REGISTRATION_UI_IMPLEMENTATION_REPORT.md) describes an earlier UI version that omitted registration type and Terms fields. Its statements about that old payload are superseded by the current source and [REGISTER_UI_BACKEND_INTEGRATION_REPORT.md](./REGISTER_UI_BACKEND_INTEGRATION_REPORT.md).

## Terms consent and proposed Development-only approval bypass

### Current enforcement points

1. The UI's `loadCurrentTermsDocument`, `isPublishedTermsDocument`, and `hasCurrentPublishedTermsAcceptance` checks in [termsDocuments.ts](./klop-next_ui/src/features/auth/termsDocuments.ts) and [RegistrationFlowContext.tsx](./klop-next_ui/src/features/auth/RegistrationFlowContext.tsx) require a published document ID/version before enabling submission.
2. [TermsModal.tsx](./klop-next_ui/src/features/auth/TermsModal.tsx) keeps the checkbox unchecked by default. A draft can only be acknowledged as a preview; that state cannot satisfy registration consent.
3. `RegistrationRequestValidator` in [AuthenticationValidators.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Authentication/AuthenticationValidators.cs) requires a valid version GUID and `termsAccepted: true` when a registration type is supplied.
4. `LegalTermsService.GetCurrent` in [LegalTermsService.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Registration/LegalTermsService.cs) returns only published/effective metadata.
5. `iam.usp_RegisterLocalUser` in [002_registration_onboarding_procedures.sql](./klop-next-platform-api/database/migrations/v1.6/002_registration_onboarding_procedures.sql) resolves the current published version for the selected scope and rejects missing, stale, or mismatched IDs. With a typed request, it requires explicit acceptance even when the legacy consent-enforcement flag is off. On success it records the actual version ID, hash, server time, source, application, and audit in the same transaction.

### Review conclusion

A Development-only bypass is technically feasible **only as a workflow eligibility override for one existing, versioned document**, not as removal of user consent or fabrication of legal approval:

- The bypass must be disabled by default, server-controlled, and evaluated only when the API environment is Development. Startup must fail closed if the switch is enabled in Production. The SQL connection must target the separate Development database; no client-supplied flag can activate it.
- It may bypass only the approval/publication-state predicate for a specifically configured Development Terms version. It must still require a real version ID, immutable content/hash, correct PERSONAL/ORGANIZATION scope, current version selection, and explicit unchecked-by-default user acceptance.
- The transaction must continue to write the append-only consent with the actual version ID/hash and server acceptance time, plus an auditable record that the Development-only override was in effect. It must not update approval/publication rows or create an approval decision.
- The Development UI must disclose that this is a temporary Development workflow override while still showing the document and requiring the user to check the box and select I Agree.
- Production must have a separate fail-closed guard and no matching override configuration; the Development setting must not be a shared/global policy.

**Not ready now:** fresh Development inspection found zero legal version rows. Without a real versioned document and content hash, there is nothing to scope, show, or record in the required consent audit. Do not invent a GUID, accept the bundled draft as if it were stored, or write a consent without a version. Current consent enforcement is off, but typed registration still fails closed at the current-version lookup.

No such setting currently exists. Treat any proposed Development override key as a design candidate requiring product, security, DBA, and legal approval; do not add it or change `registration.legal_consent_enforcement` during this review.

## Backend, SQL, and security assessment

- **Atomicity:** The reviewed registration procedure owns its transaction and uses `XACT_ABORT`; user, credential, challenge, typed application, consent, and registration/legal audit records commit together. SQL constraints/locking enforce duplicate protection and current Terms matching. These behaviors are source/catalog evidence, not proof from a live registration execution.
- **Initial account state:** The procedure creates an active user with no `EmailVerifiedAtUtc`; typed application starts in `DRAFT`. No Tenant, membership, or role is created.
- **Password storage:** The current writer uses PBKDF2-HMAC-SHA256 with a random salt and versioned hash format, as documented in [REGISTER_IMPLEMENTATION_REPORT.md](./klop-next-platform-api/REGISTER_IMPLEMENTATION_REPORT.md). Plaintext passwords are not logged or sent to SQL.
- **Token storage:** Application generates a cryptographically random token and sends only its SHA-256 digest and expiry to the repository. The raw token is retained only for email composition.
- **Runtime SQL security:** The configured API connection uses Integrated Security. Fresh SQL inspection observed an elevated interactive SQL session, not an API session. Runtime role has no members and 8/28 explicit procedure grants. Do not treat elevated `dbo`/`sysadmin` access as runtime validation or run registration through it.
- **Error behavior:** Duplicate is intentionally generic. Other persistence/configuration failures are not converted into a success-shaped response. SMTP failure after commit is logged safely and does not undo account creation; resend is the recovery path.
- **Audit:** Registration and consent audit rows are part of the stored-procedure transaction; verification/resend procedures have their own audit path. No application log is a replacement for database audit.

## Security and failure scenarios

| Scenario | Assessment |
|---|---|
| Existing email | Generic HTTP 202; SQL normalized-email uniqueness/locking protects duplicate creation. |
| Invalid registration payload | Backend FluentValidation returns 400; SQL also validates critical registration and Terms invariants. |
| Password policy violation | Backend enforces configured minimum; frontend has only a non-empty check, so users can submit a password the server rejects. |
| Database transaction failure | Procedure transaction rolls back its account/onboarding/consent writes; API does not claim success for an unhandled failure. Not exercised against Development. |
| SMTP unavailable after registration | Account transaction remains committed; failure is sanitized in logs and user sees generic accepted response. Resend can recover. No durable outbox is present. |
| Invalid/expired/reused verification token | Existing confirmation procedure contract is intended to reject absent, expired, consumed, or invalidated challenges. SQL-backed outcomes were not exercised in this review. |
| Resend abuse | Auth endpoints share a configured per-IP rate-limit policy. No separate per-account resend cooldown or maximum-attempt policy was found; each eligible resend invalidates prior outstanding challenges. |
| Login before verification | Blocked in Application (`EmailVerifiedAtUtc` must exist) and rechecked when creating a SQL session. |
| Concurrent duplicate registration | SQL transaction/locking and normalized-email uniqueness are the authoritative controls. No concurrent SQL integration test was run. |
| Unapproved Terms in Development | Current UI and typed SQL registration reject the missing/unpublished version. |
| Accidental Production bypass | No bypass exists now. Future implementation must be Production-denied at startup and in the backend/database policy, not controlled by client input. |

## Verification run for this review

- Frontend focused test: `npm test -- tests\LoginPage.test.tsx` from `klop-next_ui` — **PASS**, 28 tests.
- Backend unit suite: `dotnet test tests\KLOP.Platform.UnitTests\KLOP.Platform.UnitTests.csproj --no-restore` from `klop-next-platform-api` — **PASS**, 111 tests.
- Tests are non-mutating and do not establish Development database integration or email delivery.
- SQL checks were SELECT/catalog-only. No data-changing tests, migrations, stored-procedure executions, registrations, or emails were performed.

## Overall readiness

**NOT READY for Development end-to-end registration.** Current source wiring is largely present, but there is no current Terms version, no verified least-privilege runtime identity, the runtime role is incomplete, email-link consumption is not integrated into the UI, and no provider acceptance/delivery evidence exists. Preserve the existing mandatory email-verification gate and Production legal enforcement.

## Related reports

- [REGISTER_UI_BACKEND_INTEGRATION_REPORT.md](./REGISTER_UI_BACKEND_INTEGRATION_REPORT.md)
- [REGISTER_IMPLEMENTATION_REPORT.md](./klop-next-platform-api/REGISTER_IMPLEMENTATION_REPORT.md)
- [REGISTRATION_API_CONTRACTS.md](./klop-next-platform-api/REGISTRATION_API_CONTRACTS.md)
- [REGISTRATION_BACKEND_ENHANCEMENT_REPORT.md](./klop-next-platform-api/REGISTRATION_BACKEND_ENHANCEMENT_REPORT.md)
- [SQL_V16_DEPLOYMENT_CORRECTION_REPORT.md](./klop-next-platform-api/SQL_V16_DEPLOYMENT_CORRECTION_REPORT.md)
- [SQL_RUNTIME_SECURITY_REMEDIATION_REPORT.md](./klop-next-platform-api/SQL_RUNTIME_SECURITY_REMEDIATION_REPORT.md)
- [PLATFORM_SETUP_CENTER_IMPLEMENTATION_REPORT.md](./PLATFORM_SETUP_CENTER_IMPLEMENTATION_REPORT.md)
- [PLATFORM_SETUP_BACKEND_CONTRACTS.md](./PLATFORM_SETUP_BACKEND_CONTRACTS.md)
