# Registration and Email Verification Manual Test Guide

**Status:** Not executed. Manual testing is blocked until the [Development configuration checklist](./REGISTER_DEVELOPMENT_CONFIGURATION_CHECKLIST.md) is approved and complete. Do not create test accounts, write Development data, run migrations, or send email as part of this guide without separate explicit authorization.

## Test boundaries

- Use only the approved Development API and exact Development database.
- Use a local SMTP sink when possible. Otherwise use only an explicitly approved non-production test mailbox.
- Never use Production, real users, personal mailboxes, real customer data, or copied credentials.
- Do not print, screenshot, store, log, or send verification tokens to analytics. Do not place tokens in query strings.
- Do not run these scenarios as automated database-mutating integration tests without separate approval.

## Preflight

1. Confirm migration approval and application to the approved Development database; confirm the runtime identity is non-admin and has only the required procedure grants.
2. Confirm `ASPNETCORE_ENVIRONMENT=Development`, the bypass process flag is enabled only for the approved Development session, and database consent enforcement is false.
3. Confirm Production settings remain unchanged and the Production startup guard rejects the bypass.
4. Confirm the API starts under the approved identity. Resolve the known sender-address, SMTP TLS/authentication, Key Vault, and runtime-identity blockers first.
5. Confirm the destination is a local sink or specifically approved non-production test mailbox.

## Registration policy and form behavior

1. Request `GET /api/v1/auth/registration-policy`; check `termsRequired=false`, the authoritative minimum/maximum password lengths, and only the enabled registration types. Confirm the response is not cached.
2. Open registration and choose each permitted type. Confirm no Terms document metadata, PDF, acceptance status, or consent control is requested/rendered under bypass policy.
3. Submit the direct registration form and verify its payload has only `fullName`, `email`, `password`, and `registrationType`; no Terms IDs, acceptance flag, confirm-password field, token, or client timestamp.
4. Check password values just below the minimum, exactly at the minimum, exactly at the maximum, and above the maximum. The UI must use policy bounds; the API must reject invalid values even if a client bypasses the UI.
5. Verify a disabled registration type cannot be selected/submitted. If policy retrieval fails, confirm submission remains disabled and a safe retry/error is shown.

## Backend guard behavior

1. With the Development bypass enabled, send a request omitting both Terms fields and confirm it is accepted only in the exact Development environment/database.
2. With the bypass enabled, send either Terms field and confirm the API rejects the mixed contract.
3. With the bypass disabled, omit Terms fields or decline acceptance and confirm registration is rejected; the standard explicit published/effective Terms flow remains required.
4. In a non-Production-safe configuration check, verify enabling the bypass outside Development fails closed. Do not test by changing Production configuration.
5. For an approved single Development registration, verify the expected user, credential, verification challenge, DRAFT application, and correlated audit records. Confirm no consent row, false consent, Tenant, membership, or role is created by the bypass. Do not clean up audit history by direct deletion.

## Email-link verification

1. Confirm the approved sink/mailbox receives one message and record provider acceptance separately from inbox receipt.
2. Click the `/verify-email#userId=...&token=...` link. Confirm a single verification request is submitted automatically and the browser fragment is removed before completion.
3. Confirm success routes to Login, displays a generic confirmation, and does not sign the user in.
4. Confirm invalid, incomplete, duplicate, expired, and already-used link values do not produce a successful verification. A failed link should leave the manual verification and resend recovery paths accessible.
5. Confirm the token is not written to local/session storage, application logs, analytics, or a query string. Do not copy token values into test notes.
6. Attempt login before verification and confirm the existing verification gate rejects it. After verification, confirm the approved test user can sign in.
7. Test resend only with the approved disposable identity and sink. Confirm the response remains generic, the new link works, and the prior outstanding token is invalidated as expected.

## Terms-required and Production regression

1. In a safe unit/contract environment, verify Terms-required policy keeps the existing document review and explicit-consent flow and sends the current Terms version and acceptance flag.
2. Verify the API and SQL layers still require consent when the bypass is off.
3. Verify Production startup requires consent enforcement and rejects the Development bypass. Do not change or probe live Production settings.

## Completion record

Record only sanitized outcomes: environment, approved ticket, test case, pass/fail, timestamps, and non-sensitive correlation IDs. Do not record user email, password, token, secret, or full SMTP/configuration values. Report separately whether API startup, provider acceptance, and inbox delivery were verified. Until authorized manual testing occurs, all three remain unverified.
