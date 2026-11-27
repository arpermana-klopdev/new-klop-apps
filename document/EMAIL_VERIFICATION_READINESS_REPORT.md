# KLOP Email Verification Readiness Report

**Review date:** 2026-11-24  
**Scope:** Source, current Development SQL metadata, and configuration wiring only. No credentials were read or disclosed, no email was sent, and no account or database data was changed.

## Executive conclusion

**PARTIAL**

KLOP has source implementations for SMTP delivery, random verification-token generation, database challenge persistence, verification/resend endpoints, and a login gate requiring verified email. This does **not** establish working email delivery: no live API process or SMTP send was observed, the actual SMTP/Key Vault values were not inspected, there is no published Terms version for typed registration, and the email URL fragment is not consumed by the frontend automatically. Do not claim that a real registration verification email currently reaches an inbox.

## Delivery path and implementation status

| Step | Status | Evidence / limitation |
|---|---|---|
| Register request reaches handler | **IMPLEMENTED IN SOURCE** | `POST /api/v1/auth/register` is public and rate-limited in [AuthenticationEndpoints.cs](./klop-next-platform-api/src/KLOP.Platform.Api/Endpoints/Authentication/AuthenticationEndpoints.cs). |
| Account/challenge creation | **IMPLEMENTED IN SOURCE; SQL RUNTIME BLOCKED** | [AuthenticationService.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Authentication/AuthenticationService.cs) calls the repository; [KlopIdentityRepository.cs](./klop-next-platform-api/src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/Identity/KlopIdentityRepository.cs) calls `iam.usp_RegisterLocalUser`. The procedure is transactional and creates the user, credential, challenge, and, for typed registration, application/consent/audit. No live registration was run. |
| Token generation and hash persistence | **IMPLEMENTED IN SOURCE** | 32 random bytes are generated with the platform cryptographic RNG, encoded Base64URL, then SHA-256 hashed for storage. The raw token is used only for email composition. |
| Email template preparation | **IMPLEMENTED, BASIC INLINE TEXT** | [SmtpVerificationEmailSender.cs](./klop-next-platform-api/src/KLOP.Platform.Infrastructure/Notifications/Email/SmtpVerificationEmailSender.cs) creates a plain-text message with subject, verification URL, expiry duration, and a warning not to share the link. No template file, template ID, localization/catalog, or rich HTML template is used. |
| Provider invocation | **IMPLEMENTED IN SOURCE; NOT RUNTIME VERIFIED** | The sender calls `.NET SmtpClient.SendMailAsync`. There is no alternate provider adapter or provider API client in the reviewed path. |
| SMTP acceptance | **NOT VERIFIED** | No API process was running, no send was attempted, and no SMTP/provider response was collected. |
| Inbox delivery | **NOT VERIFIED** | No test or real mailbox was used. SMTP acceptance alone would not prove inbox delivery. |
| User opens link and verifies | **PARTIAL FRONTEND INTEGRATION** | Email link points to `/verify-email#userId=...&token=...`; the UI route exists but currently does not read the fragment. It instead presents manual User ID and Verification code fields. |
| Account becomes login-eligible | **IMPLEMENTED IN SOURCE; SQL E2E NOT VERIFIED** | The application requires `EmailVerifiedAtUtc` for login and session creation; the stored-procedure session check repeats the verified/active requirement. No live verification/session flow was run. |

## A. Email infrastructure and configuration

### Provider and service

- Provider mechanism: SMTP through `System.Net.Mail.SmtpClient`, implemented by `SmtpVerificationEmailSender`.
- The sender address, host, port, TLS flag, and optional username are loaded by [RuntimeSettings.cs](./klop-next-platform-api/src/KLOP.Platform.Infrastructure/Configuration/RuntimeSettings.cs) from database-backed `cfg.usp_Configuration_GetByKey`.
- Development SQL read-only metadata shows active keys for `smtp.host`, `smtp.port`, `smtp.from`, `smtp.require_tls`, `smtp.username`, and `smtp.password_ref`. The values were intentionally not selected, emitted, or copied into this report.
- SMTP password is not expected in a plain configuration row. When a username is configured, the application requires `smtp.password_ref` to be a Key Vault reference and resolves it through [KeyVaultSecrets.cs](./klop-next-platform-api/src/KLOP.Platform.Infrastructure/Security/KeyVaultSecrets.cs) using `DefaultAzureCredential`.
- [appsettings.Development.json](./klop-next-platform-api/src/KLOP.Platform.Api/appsettings.Development.json) contains an empty checked-in Key Vault URI. Environment/command-line overrides and managed identity availability cannot be proven without the actual API process; therefore secret resolution is **not verified**.
- TLS is required by startup policy in Production; the SMTP sender also refuses non-TLS SMTP outside Development.
- Dependency injection registers `IVerificationEmailSender` to `SmtpVerificationEmailSender` in [InfrastructureRegistration.cs](./klop-next-platform-api/src/KLOP.Platform.Infrastructure/DependencyInjection/InfrastructureRegistration.cs).

### Configuration classification

| Setting | Source/status | Review note |
|---|---|---|
| SMTP host, port, from address, TLS, optional username | Database-backed runtime configuration; active key metadata exists in Development | Values were not inspected. Correctness/reachability is not verified. |
| SMTP password | Secret reference in database-backed configuration, value resolved from Azure Key Vault | No secret value was read. Vault URI/identity/runtime availability are unverified. |
| Verification expiry | `auth.email_verification_hours` database setting; runtime loader bounds it to 1–24 hours | Actual setting value was not emitted. |
| Frontend origin | `web.allowed_origin` database-backed setting, required to be an HTTPS origin | Link is constructed by backend, not hardcoded to a Development host. Actual runtime value was not emitted. |
| Provider selection/API endpoint | No provider-selection abstraction found; current implementation is SMTP | SMTP host/port are host configuration, not a provider choice. |
| Resend cooldown/attempt cap | No distinct settings or enforcement found | Only the shared auth per-IP rate limit is present. |
| Email template identifier | None found | Message subject/body are inline in the sender implementation. |
| Registration Terms bypass | No existing key or implementation | Current `registration.legal_consent_enforcement` is a separate SQL policy; it is currently `false`, not an approval-state bypass. |

## B. Verification token and challenge

- **Generation:** `SecretTokens.NewToken()` uses `RandomNumberGenerator.GetBytes(32)` and Base64URL encoding in [Security.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Security.cs).
- **At-rest form:** Application passes `SHA-256(token)` to the repository; the SQL challenge schema stores a fixed 32-byte hash, not the raw token. The raw token exists only for message generation.
- **Expiry:** Application calculates challenge expiry from the database-backed `auth.email_verification_hours`. The database procedure also rejects expiry in the past or beyond its 24-hour upper bound.
- **Single-use/invalidation:** The existing challenge procedures and database design support consuming a valid challenge and invalidating outstanding challenges after confirmation or resend. Resend invalidates prior outstanding challenges before inserting a replacement.
- **Invalid/expired/reused token:** The verify route hashes the supplied token before repository lookup; the database confirmation procedure is authoritative for challenge eligibility and consumption. Exact Development SQL execution outcomes were not tested.
- **Resend behavior:** Resend uses a new random token/hash and only sends when the stored procedure returns an eligible unverified user. The public response remains generic, avoiding account enumeration.
- **Abuse protection:** Verify/resend/register share the `auth` rate-limit policy partitioned by caller IP. No separate per-account resend cooldown, maximum resend count, or delivery queue was found. Resends can repeatedly invalidate earlier active links within the shared rate limit.
- **Audit:** Database procedures record correlated challenge issuance/verification events. No token, password, or token hash should be copied to logs/reports.

## C. Verification API and frontend

### API contract

- `POST /api/v1/auth/verify-email` accepts `userId` and `token`, is rate-limited, and delegates to `AuthenticationService.ConfirmEmail`.
- `POST /api/v1/auth/resend-verification` accepts email and returns a generic HTTP 202 message.
- Registration also returns generic HTTP 202; the handler does not disclose duplicate status.
- `AuthenticationService.SendVerificationSafely` catches delivery failures after database commit and logs operation, correlation ID, and failure type only. Cancellation requested by the caller is rethrown. There is no durable outbox; resend is the recovery path.

### Link mismatch

`VerificationEmailLink.Build` requires an HTTPS origin and builds a `/verify-email` URL with `userId` and token in the **fragment**, keeping the token out of the query string and HTTP referrer. However, the current `VerifyForm` in [LoginPage.tsx](./klop-next_ui/src/features/auth/LoginPage.tsx) renders empty manual fields and does not parse the fragment, prefill values, submit automatically, or clear sensitive fragment data. Thus:

- The link destination is correct as a route, but **one-click verification is not implemented**.
- A user may manually extract values from the URL fragment, but the message and page do not make that the intended seamless flow.
- A future UI fix should parse only the expected fragment fields, validate them, submit through the existing API, and remove the fragment from browser history promptly. Do not store the token in local/session storage or analytics.

## D. Account activation and login gate

- Registration inserts the account as `IsActive=1`, but it has no verified timestamp; the account is not login-eligible until successful email verification.
- `AuthenticationService.Login` requires a matching password, an active user, a non-null `EmailVerifiedAtUtc`, and no active lockout.
- The SQL session-creation procedure repeats active/verified/lockout checks before creating a session; bearer-session validation also checks active/verified status.
- The UI returns to Login after verification and does not automatically sign in.
- This is a mandatory email-verification requirement. No bypass or weakened login rule is proposed.

## E. Current Development database/runtime evidence

Read-only checks on 2026-11-24 found all 28 reviewed API procedures present, zero active `KLOP.Platform.API` SQL sessions, zero runtime-role members, and 8 explicit `EXECUTE` grants for the 28-procedure set. The current SQL inspection session was elevated (`dbo`/`sysadmin`/`db_owner`), so its access cannot validate the application runtime. The Development API is configured for Integrated Security, but no API process was available to identify its Windows token.

SMTP configuration-key metadata is present, but no host/from/credential values were displayed, no Key Vault call was made, and no SMTP connection was attempted. Legal data readiness is also absent: Development has zero Terms version rows, so typed registration cannot currently pass the published-version lookup. The runtime role/identity and legal prerequisites therefore block safe end-to-end testing.

## F. Security and failure scenarios

| Scenario | Current handling / gap |
|---|---|
| SMTP/provider unavailable | Registration remains committed; sender failure is safely logged; generic response is retained; user must use resend. No durable outbox or automatic retry exists. |
| Provider accepts but recipient never receives | Not observable from current source; inbox delivery is not verified. Do not equate SMTP send acceptance with inbox delivery. |
| Invalid/expired token | Rejected by challenge lookup/procedure contract; live SQL behavior not exercised. |
| Reused token | Single-use consumption/invalidation is intended; live SQL behavior not exercised. |
| Resend flood | Shared IP-based auth limiter bounds requests; there is no separate per-account cooldown/count. Repeated eligible resend invalidates the previous link. |
| Duplicate registration | Generic HTTP 202; no second active registration should be created due to SQL normalized-email constraint/transaction. |
| Login before verification | Rejected in Application and checked again by SQL session creation. |
| Verification-link click | Opens a page that currently does not consume URL-fragment values automatically. |
| Request cancelled after database commit | The email sender preserves request cancellation rather than swallowing it; account may remain committed with no delivered email. Resend is required. |

## Verification performed

- Frontend `LoginPage.test.tsx`: **28 passed**.
- Backend `KLOP.Platform.UnitTests`: **111 passed**.
- These isolated tests do not establish SMTP connectivity, provider acceptance, inbox delivery, SQL runtime grants, challenge behavior against Development data, or end-to-end verification.
- No live account, email, database mutation, or integration test was used.

## Final answer

**Can KLOP currently send a real registration verification email? — PARTIAL.**

The SMTP send call and its configuration pathway are implemented, and required configuration-key metadata exists. But actual runtime configuration, Key Vault access, SMTP connection/acceptance, and inbox delivery have no supporting runtime evidence. Registration itself is blocked by the missing Development Terms version and unverified least-privilege SQL runtime. In addition, the email link does not automatically deliver its fragment token to the verification form. A safe manual or end-to-end claim is therefore not supported.

## Related reports

- [REGISTER_FULLSTACK_REVIEW_REPORT.md](./REGISTER_FULLSTACK_REVIEW_REPORT.md)
- [REGISTER_IMPLEMENTATION_REPORT.md](./klop-next-platform-api/REGISTER_IMPLEMENTATION_REPORT.md)
- [REGISTRATION_API_CONTRACTS.md](./klop-next-platform-api/REGISTRATION_API_CONTRACTS.md)
- [REGISTRATION_BACKEND_ENHANCEMENT_REPORT.md](./klop-next-platform-api/REGISTRATION_BACKEND_ENHANCEMENT_REPORT.md)
- [SQL_V16_DEPLOYMENT_CORRECTION_REPORT.md](./klop-next-platform-api/SQL_V16_DEPLOYMENT_CORRECTION_REPORT.md)
