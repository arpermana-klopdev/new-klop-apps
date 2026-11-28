# Notification Management v1.11

## Status and boundaries

This is a source implementation and an owner-held SQL proposal, not a production-ready or frozen artifact. Work is on the dedicated Copilot working branch `copilot/notification-management-email-templates`, synced with main commit `2d08a97329fff7709664dd8341bd54b9c91985f3`; the similarly named feature branch is not used. No SQL was executed, no live database was accessed, no SMTP send or network probe was performed, and no deployment was made. Owner SQL approval, least-privilege runtime identity, role mapping approval, and live Development UAT remain on HOLD.

The only initially supported channel and flow is email verification through the existing registration/resend flow. SMS, WhatsApp, in-app notifications, password reset, registrations beyond existing verification delivery, invitations, and welcome messages are planned, not enabled. The existing sender stays in use while `notification.email_verification_templates.enabled` is absent or false. In this default path it makes no calls to the v1.11 notification schema. A separate `notification.email_verification_delivery_audit.enabled` setting also defaults to false; turn it on only after the owner-reviewed schema and exact stored-procedure grants are installed. Audit persistence is best effort and cannot change the reported SMTP outcome. If the owner enables template rollout but no valid active English verification version is available, the sender fails safely and does not fall back to the legacy message.

The application still generates HTTPS verification links from `web.allowed_origin`; SQL stores only the template with typed placeholders, never rendered content, verification tokens, or full links. Existing token hashing, expiry, single-use, and generic registration/resend responses are unchanged. No automated retry is added.

## Data and lifecycle decisions

The additive v1.11 proposal uses schema `ntf` and these tables:

- `NotificationChannels` and `NotificationChannelStatuses`
- `NotificationTemplateTypes`, `NotificationTemplateStatuses`, `NotificationVariableDefinitions`
- `NotificationTemplates`, `NotificationTemplateVersions`, `NotificationTemplateVersionVariables`
- `NotificationTemplateApprovals`
- `NotificationDeliveries`, `NotificationDeliveryAttempts`, `NotificationDeliveryOutcomes`, `NotificationErrorCategories`

Channel, template type, status, variable, outcome, and safe error-category definitions are data rows, not API/UI business defaults. The initial seed proposal defines EMAIL and the existing verification wording as a DRAFT only. It does not create an active template, enable template rollout, alter existing SMTP settings, create role assignments, or introduce other active channels. The seed requires an explicitly supplied approved actor ID; no user ID is guessed.

The transition procedure enforces DRAFT → PENDING_APPROVAL → APPROVED → ACTIVE → ARCHIVED. Rejection returns a submitted version to DRAFT and records the decision. SQL transaction locks and expected `rowversion` enforce optimistic concurrency; a filtered unique index permits at most one active version per template/channel/locale, and activation archives the prior active version atomically. An update trigger blocks edits to an activated version's contents. Administrative changes and approval decisions write to the existing `aud.AuditEvents` model in their transaction.

Active and archived versions cannot be edited or deleted. Version rows retain the template code and use composite foreign keys to prevent a version's variable set from referencing another template's definitions. Delivery records contain no recipient metadata column; attempts enforce positive attempt numbers and provider-accepted/rejected outcome consistency. Automatic archival of the previous active version is audited in the activation transaction.

The verification flow selects only the seeded `EMAIL` / `EMAIL_VERIFICATION` / `en` active version. Other locales are not selected, and API/UI mutations and preview reject non-English verification templates. `verification_link` and `expiry_hours` are required in the body; only the expiry placeholder may be used in a subject, and the verification link is never permitted there. Placeholder matching is ordinal/case-sensitive in application code and binary-collated in the proposal procedures.

When the independent delivery-audit gate is explicitly enabled, history records the provider attempt outcome, template/version (or the explicit `LEGACY` label while template rollout is off), channel, UTC timestamp, correlation ID, and an allowlisted safe error category. With the default-off audit gate, the legacy sender makes no notification SQL calls and no delivery history is recorded. The schema deliberately omits recipient metadata. It does not record an email address, token, URL, body, SMTP secret, or exception payload. `PROVIDER_ACCEPTED` means accepted by the SMTP provider only; it is not evidence of inbox delivery. There is no automatic retry policy.

## Permission proposal — owner decision required

All proposed capabilities are PLATFORM-scoped. The permission catalog proposal adds definitions only; it maps none of them to existing roles. Do not infer or add role grants until the owner approves the matrix.

| Proposed permission code | Capability | Role mapping |
|---|---|---|
| `platform.notifications.read` | Read template catalog, versions, and channels | UNASSIGNED — owner review |
| `platform.notifications.draft.create` | Create template drafts | UNASSIGNED — owner review |
| `platform.notifications.draft.edit` | Edit drafts | UNASSIGNED — owner review |
| `platform.notifications.draft.preview` | Render synthetic preview | UNASSIGNED — owner review |
| `platform.notifications.submit` | Submit a draft for approval | UNASSIGNED — owner review |
| `platform.notifications.approve` | Approve or reject a submitted version | UNASSIGNED — owner review |
| `platform.notifications.activate` | Activate an approved version | UNASSIGNED — owner review |
| `platform.notifications.archive` | Archive a version | UNASSIGNED — owner review |
| `platform.notifications.history` | Read paginated delivery attempts | UNASSIGNED — owner review |
| `platform.notifications.settings.read` | Read safe readiness metadata | UNASSIGNED — owner review |

Every administrative endpoint requires a validated authenticated platform session and its exact SQL-backed permission. The UI shows mutation controls only after the permission API verifies the capability. No role-label shortcut or client-only authorization is used; missing permission mappings fail closed.

The v1.11 authorization delta restores the ten notification codes to both explicit allowlists in `iam.usp_ValidatePlatformPermission` and `iam.usp_GetPlatformPermissions`. It preserves the v1.10 session validation, PLATFORM-only role checks, permission scope, and `AllowsEffective=1` readiness check. It requires the v1.10 matrix tables and inserts missing notification matrix metadata as `HOLD` (`AllowsEffective=0`, `AllowsMatrixEdit=0`); it refuses pre-existing non-HOLD rows or any notification role mapping. It does not assign roles. Owner-approved matrix readiness changes and role mappings remain separate gated decisions.

## SMTP inventory and manual checklist

Runtime settings already load through `cfg.usp_Configuration_GetByKey`, are type-checked at startup, and are held in memory until restart. This feature adds no SMTP credential write UI, generic configuration write API, test-send action, probe, or new provider.

| Existing key | Required/type | Owner action/check |
|---|---|---|
| `smtp.host` | Required `STRING` / `PLAIN` | Enter the environment-specific SMTP host in the existing configuration path. |
| `smtp.port` | Required `INTEGER` / `PLAIN`, 1–65535 | Confirm the owner-selected port. |
| `smtp.from` | Required `STRING` / `PLAIN` | Confirm the approved sender address. |
| `smtp.require_tls` | Required `BOOLEAN` / `PLAIN` | Must be `true` in Production; keep TLS enabled for the production provider. |
| `smtp.username` | Optional `STRING` / `PLAIN` | Supply only if the owner/provider requires SMTP authentication. |
| `smtp.password_ref` | Optional `STRING` / `KEYVAULT_REFERENCE`; required when username is set | Store the secret value in the environment's Azure Key Vault and put only its approved reference in SQL. |
| `auth.email_verification_hours` | Required `INTEGER` / `PLAIN`, 1–24 | Existing token/challenge lifetime; keep it consistent with the verification template wording. |
| `web.allowed_origin` | Required `STRING` / `PLAIN`, HTTPS origin without path/query/fragment | Existing source for HTTPS verification links; do not put a full verification URL in the template. |

Before any authorized manual setup:

1. Inventory presence, active state, type, and storage type only; do not select or print configuration values in logs or tickets.
2. Confirm separate Development and Production SQL/Key Vault resources and the exact secret name/reference with the owner.
3. Keep passwords exclusively in Key Vault. Never paste secret values, raw secret references, or connection details into SQL seed scripts, source control, browser responses, previews, logs, or CI.
4. Confirm the runtime identity can execute only the reviewed settings and notification stored procedures; the currently documented Development identity/grants are not least-privilege ready.
5. After an approved change, restart the API because runtime settings are loaded at startup. Verify only the authorized readiness booleans; never display host, sender, username, or secret reference values.
6. Confirm Production TLS is enabled. Do not run a real SMTP send or network test under this change.

The Settings tab exposes only configured/not-configured booleans, TLS-required status, template and delivery-audit gate status, and verification-lifetime validity, behind `platform.notifications.settings.read`. It does not expose raw values or permit writes.

## SQL package and manual execution order

The scripts are proposals only. No script is run by application startup, CI, or this agent. Approval templates use SQLCMD mode and default `KLOP_APPLY_CHANGES` to `NO`. They are restricted to the repository's reviewed Development target and must not be used to modify any frozen baseline or Production.

1. `database/migrations/v1.11/000_notification_preflight_READONLY.sql` — inspect prerequisites and collisions; read-only.
2. `database/migrations/v1.11/001_notification_schema_APPROVAL_TEMPLATE.sql` — create the additive schema/tables/index/immutability trigger after explicit owner/DBA approval.
3. `database/migrations/v1.11/002_notification_procedures_APPROVAL_TEMPLATE.sql` — install the stored-procedure boundary after the schema.
4. Apply the owner-approved v1.10 RBAC migration (`v1.10/003_tenant_permission_policy_APPROVAL_TEMPLATE.sql`) before notification authorization integration; never edit the v1.10 files.
5. `database/migrations/v1.11/003_notification_seed_APPROVAL_TEMPLATE.sql` — seed the EMAIL channel, database definitions, both off-by-default notification settings if absent, and an English DRAFT verification template. Supply an existing user ID with an active PLATFORM assignment; never infer one.
6. `database/migrations/v1.11/004_notification_permissions_APPROVAL_TEMPLATE.sql` — add PLATFORM permission definitions only. It deliberately adds no role mappings.
7. `database/migrations/v1.11/006_notification_authorization_delta_APPROVAL_TEMPLATE.sql` — after v1.10 and permission definitions, add matrix metadata and replace both authorization procedure allowlists. Notification rows remain HOLD and UNASSIGNED. No v1.10 files are changed.
8. `database/security/v1.11_notifications_runtime_grants_APPROVAL_TEMPLATE.sql` — exact `EXECUTE` grants to the already-existing `klop_app_runtime` database role only after the identity is least-privilege ready. It creates no users, roles, or memberships.
9. `database/security/v1.11_notifications_runtime_validation_READONLY.sql`, then `database/migrations/v1.11/005_notification_postdeploy_READONLY.sql` — verify exact object grants, all 13 notification tables, authorization dependencies, matrix definitions/mappings, rollout gate state, and resulting schema/state read-only.

Keep the owner-approved change ticket, script outputs, backup/restore point, and SQLCMD variables with the DBA change record. Stop at the first unexpected object, duplicate key, failed audit prerequisite, or validation mismatch. Do not blindly rerun non-idempotent DDL/procedure installation or manually patch a partially applied migration. Record the exact failing statement and transaction outcome, keep the rollout disabled, and have the DBA compare current object definitions with the approved script before preparing an owner-approved corrective/forward migration or restoring the authorized backup. There is intentionally no automatic rollback script and no migration version ledger; the deployment record must be maintained externally.

## Manual UAT checklist — HOLD

Perform only after the owner lifts the SQL/UAT hold, approves permission-to-role mapping, confirms least-privilege runtime grants, and supplies non-production configuration:

- Verify API permission checks and SQL session validation deny unauthenticated, expired-session, and unmapped callers for every read and mutation.
- Verify create/edit, draft-only editing, required/unknown variables, CR/LF subject injection, synthetic preview, submit, approve/reject, activation, archival, rowversion conflict, atomic single-active behavior, and audit atomicity using isolated non-live storage tests.
- Use a mock transport for SMTP acceptance/failure tests. Verify no real send, no retry, safe generic registration/resend responses, preserved HTTPS link/expiry/single-use behavior, and safe error categories.
- Verify delivery history shows provider acceptance (not inbox delivery), template version, timestamps, correlation, and no full recipient, URL, token, body, secret, or raw exception.
- Verify EMAIL-only readiness, no SMS/WhatsApp/in-app active channel, the default-off gate, fail-safe missing-active-template behavior, keyboard-accessible tabs, loading/error/empty/conflict states, and no hidden SMTP values.
- Confirm generated OpenAPI/TypeScript, backend tests/build, frontend typecheck/tests/build, and the repository KLOP CI all pass for the reviewed head/base.

Do not use live Playwright, a live database, a new test database, real SMTP, or a deployment until separately authorized.

## Validation evidence and remaining gates

The source-level tests use fake SMTP transport, fake repositories, and local SQL-contract inspection; they do not execute SQL or contact SMTP. Validation on the current working tree:

- `dotnet test /home/runner/work/new-klop-apps/new-klop-apps/klop-next-platform-api/tests/KLOP.Platform.UnitTests/KLOP.Platform.UnitTests.csproj --no-restore` — PASS, 158 tests.
- `cd /home/runner/work/new-klop-apps/new-klop-apps/klop-next_ui && npm test -- --run` — PASS, 97 tests.
- `cd /home/runner/work/new-klop-apps/new-klop-apps/klop-next_ui && npm run typecheck` — PASS.
- `cd /home/runner/work/new-klop-apps/new-klop-apps/klop-next_ui && npm run build` — PASS (Rollup emitted existing dependency annotation warnings).
- `cd /home/runner/work/new-klop-apps/new-klop-apps/klop-next_ui && npm run api:types` — PASS; a second generation matched the first byte-for-byte, and `git diff --check` passed.
- `cd /home/runner/work/new-klop-apps/new-klop-apps/klop-next_ui && npm ci` — PASS; npm audit reported zero vulnerabilities.
- Notification SQL procedure variable references were checked statically; no undeclared local-variable references were found. SQL parsing/installation was not tested because SQL execution is held.

Current-head KLOP CI has not yet passed; the existing run was `action_required` with zero jobs. SQL syntax and procedure installation remain unverified because SQL Server execution is explicitly held. The live v1.10/v1.11 migration order, owner role-matrix decisions, permission effective-state changes, SMTP setup, manual UAT, and deployment remain owner-held gates.
