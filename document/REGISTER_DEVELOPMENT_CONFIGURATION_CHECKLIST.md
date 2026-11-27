# Development Registration Configuration Checklist

**Purpose:** Controlled rollout checklist for the Development-only Terms bypass and automatic email verification. This checklist is preparatory; no settings, SQL, database, or runtime configuration were changed.

## Approval and scope gate

- [ ] Record explicit product, security, and DBA approval for the Development bypass and its test scope.
- [ ] Identify the exact Development SQL Server/database and API process/environment. Do not use Production or a Production-equivalent live endpoint.
- [ ] Assign a change ticket, approver, operator, rollback/recovery plan, and approved test recipient or local mail sink.
- [ ] Keep the bypass disabled until every prerequisite below is complete.

## Database rollout

- [ ] DBA reviews [v1.8 registration migration](./klop-next-platform-api/database/migrations/v1.8/001_registration_terms_policy.sql), prerequisites, current procedure definition, and audit behavior.
- [ ] Apply it only to the explicitly approved Development database through the normal migration process. It has not been applied by this implementation.
- [ ] Verify the resulting procedure signature and its exact `DEV-PC\SQLEXPRESS` / `KlopPlatformDB` bypass guard using an approved read-only check.
- [ ] Verify `registration.legal_consent_enforcement` remains `false`. Prior read-only evidence dated 2026-11-24 reported it as false; recheck before rollout. Do not change it if already false.
- [ ] If an approved configuration change is actually required, use [the gated Development template](./klop-next-platform-api/database/security/registration_terms_enforcement_DEV_TEMPLATE.sql) with an approved ticket and approver. Its default is no change; do not run it as part of this implementation.
- [ ] Confirm the API's actual non-admin runtime identity and the exact required procedure grants. Prior evidence showed zero runtime-role members and 8/28 grants; the elevated inspection account is not runtime proof.
- [ ] Do not grant table DML, broad schema rights, `db_owner`, or `sysadmin`.

## API process configuration

- [ ] Confirm the API process environment is `Development`.
- [ ] Set `Registration:DevelopmentTermsBypassEnabled` to `true` only in the approved Development process configuration (environment-variable form: `Registration__DevelopmentTermsBypassEnabled=true`). The application default is `false`.
- [ ] Do not put this flag in client configuration, request payloads, shared settings, or Production configuration.
- [ ] Keep the setting absent or `false` in Production. Confirm startup rejects it if accidentally enabled outside Development.
- [ ] Confirm startup policy: bypass enabled requires database Terms enforcement disabled; Production requires enforcement enabled.
- [ ] Confirm the public policy endpoint returns the effective Terms requirement, password bounds, and enabled registration types before allowing the UI to submit.

## Email delivery prerequisites

- [ ] Resolve a valid configured SMTP sender address. The prior sanitized review found `smtp.from` missing/invalid, and the API loader requires it.
- [ ] Review SMTP TLS and provider requirements. Prior Development evidence reported TLS disabled; do not weaken Production TLS.
- [ ] Configure any approved SMTP username and its Key Vault secret reference through the authorized secret/configuration process. Do not put a password or secret value in source, this checklist, logs, or test output.
- [ ] Confirm the Development Key Vault URI, runtime identity, secret access, network path, and provider acceptance without exposing values.
- [ ] Prefer a local SMTP sink. If a recipient is necessary, use only an explicitly approved non-production test mailbox; never send to real users during this test.
- [ ] Treat sender/provider acceptance and mailbox receipt as separate verification results.

## Stop conditions

Stop without enabling the bypass if any approval, migration, exact server/database, runtime identity/grant, sender address, TLS, Key Vault, or test-recipient prerequisite is unresolved. The current sanitized readiness review does not establish that the API can start or send mail. No change in this checklist authorizes a Production modification.
