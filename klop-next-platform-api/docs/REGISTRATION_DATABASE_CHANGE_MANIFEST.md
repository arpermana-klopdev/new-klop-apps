# Registration Database Change Manifest

**Package:** KLOP Platform Database Enhancement v1.6 DRAFT  
**Package status:** DRAFT / NOT APPROVED. Read-only Development verification on 2026-11-23 found a partial v1.6 deployment; do not assume any migration step completed as a whole.  
**Approval:** NOT APPROVED  
**Database:** Existing `KlopPlatformDB` only; no TEST database, Production change, or application data mutation is authorized by this package.  
**Baseline:** Do not modify the FROZEN v1.1 foundation or historical v1.4/v1.5 files.

## Pre-deployment catalog evidence (historical) and versioning caveat

Read-only inspection of the Development target `DEV-PC\\SQLEXPRESS / KlopPlatformDB` confirmed the baseline schemas/tables and definitions of `iam.usp_RegisterLocalUser`, `iam.usp_ConfirmEmail`, `ten.usp_CreateTenantWithOwner`, and `iam.usp_ValidateSessionAccess`. The database has no `reg`/`leg` schemas or migration/version marker. Master counts were 2 Tenant Types (PERSONAL and ORGANIZATION), 7 Organization Types, 5 Identity Document Types, 5 Verification Statuses, and zero Organization identity requirement groups/requirements. New legal-consent and onboarding-policy config keys are absent. The inspection identity is `sysadmin`, `db_owner`, and `db_ddladmin`, not a member of `klop_app_runtime`; the runtime role has one explicit procedure EXECUTE grant (`mst.usp_TenantType_GetAll`). No configuration values or user data were selected. The exact deployed migration chain cannot be inferred without a marker and deployment records. Obtain DBA confirmation before migration approval. An elevated inspection identity is not evidence of acceptable production runtime privilege.

The Organization identity masters exist but currently have zero requirement groups and zero identity requirements. No legal Terms record is seeded or published by this package.

### Latest Development catalog verification — 2026-11-23

`DEV-PC\SQLEXPRESS / KlopPlatformDB` now contains `reg`/`leg`, the ten v1.6 tables, the six onboarding procedures, and the altered registration procedure with v1.6 parameters. The expected seven active status codes, configured policy metadata, key new foreign keys/unique indexes/rowversion columns were observed. However, both `leg` public read procedures and all three legal immutability triggers are absent. Registration types are enabled, while consent enforcement and both onboarding submission controls are disabled. No Terms version is published/present; organization requirement group and requirement counts remain zero.

The read-only post-deployment verifier returned blockers for the missing legal procedures, missing immutability triggers, and empty `klop_app_runtime` membership. The inspection connection was a sysadmin `dbo` mapping and does not prove API runtime permissions. The v1.6 package/version marker and deployment record remain absent; exact deployment lineage is unknown. This task performed no database repair, migration, seed, grant, or role change. See `REGISTRATION_BACKEND_ENHANCEMENT_REPORT.md` for the detailed permission matrix and E2E blockers.

## Scripts and dependency/execution order

| Order | Script | Type | Dependencies / effect | Approval and status |
|---:|---|---|---|---|
| 0 | `database/migrations/v1.6/000_preflight_READONLY.sql` | Read-only preflight | Intended for pre-deployment checks; its expected absence checks are no longer applicable after partial deployment | **Not run**; do not rerun without DBA review of expected blockers |
| 1 | `database/migrations/v1.6/001_registration_onboarding_schema.sql` | Additive schema/config | Creates `reg`/`leg`, onboarding status master and registration/profile/history/document-reference tables; legal metadata/version/scope/append-only consent tables; inserts secure configuration defaults (consent enforcement and onboarding submission disabled) | **Partially reflected in catalog**; exact script execution/version unverified |
| 2 | `database/migrations/v1.6/002_registration_onboarding_procedures.sql` | Procedure delta | Alters existing `iam.usp_RegisterLocalUser` with optional fields for compatible public calls; persists user, credential, email challenge, application, consent, audit in its existing transaction; adds owner-checked draft/status/requirements Stored Procedures | **Key procedures/signatures present**; exact script execution/version unverified |
| 3 | `database/migrations/v1.6/003_legal_read_procedures.sql` | Legal read procedures and guards | Adds public published/effective metadata/file Stored Procedures and triggers preventing edits to published document content/scopes and consent history | **Not fully reflected:** both legal read procedures and all three triggers are missing; no Terms version is present |
| 4 | `database/security/v1.6_runtime_grants_TEMPLATE.sql` | Permission proposal | Complete source-backed EXECUTE-only matrix for all API-called procedures; prechecks prevent granting if role membership or any required procedure is missing | **REVIEW ONLY / NOT EXECUTED**; role has zero members and two legal objects are absent |
| 5 | `database/migrations/v1.6/004_postdeploy_READONLY.sql` | Read-only verification | Checks required objects, initial disabled policy flags, status codes, immutability triggers, and reports runtime access gate without printing configuration values | **Run read-only 2026-11-23; BLOCKER result**, expected exit 51620 |

`001` must complete before `002`/`003`; `002` and `003` consume the newly created metadata. The permission template is considered only after schema and procedure verification and a separate least-privilege review. Do not execute it from the migration process. Run the read-only post-deployment verifier after separately approved execution.

## New logical objects

- `mst.OnboardingStatuses` (stable status codes, not numeric IDs in application logic).
- `reg.RegistrationApplications`, `reg.RegistrationApplicationHistory`.
- `reg.PersonalOnboardingDetails`, `reg.OrganizationOnboardingDetails`.
- `reg.ApplicationSupportingDocuments` (storage reference/hash/metadata only; no binary in SQL).
- `leg.LegalDocuments`, `leg.LegalDocumentVersions`, `leg.LegalDocumentVersionScopes`, `leg.UserLegalConsents`.
- New database configurations: `registration.legal_consent_enforcement` (false), `legal.maximum_upload_bytes` (10 MiB default), `onboarding.personal_submission_enabled` (false), and `onboarding.organization_submission_enabled` (false). All are system-managed and approval-required; the API does not provide generic configuration editing.

The versioned Terms binary remains external. `StorageReference` is an opaque GUID handle, not a filesystem path. The current frontend PDF is not copied into the package and is not published.

## Primary key, integrity, concurrency, and transaction rules

The package uses foreign keys to existing global Users, Tenant Types, Tenant, Organization Type, Identity Document Type, and Verification Status masters; unique keys/indexes prevent duplicate versions/consents and multiple current initial applications; rowversion values protect concurrent draft edits; UTC timestamps are written in SQL. Published content and scope are immutable. Consent is append-only. User and consent hashes are generated/resolved server-side. SQL errors are numbered and mapped to safe API errors.

All application SQL data operations remain Dapper calls to Stored Procedures. API repositories contain no direct table SELECT/INSERT/UPDATE/DELETE. The registration Stored Procedure owns one transaction and must roll back user, credential, verification challenge, application, consent, history, and audit writes together. It does not create a Tenant or assign roles.

## Authorization and grants

The template grants no schema/table access and makes no role membership or SQL login change. It contains an EXECUTE-only proposal for all 28 distinct procedures called by the current API repository, with prechecks that stop before granting if any required procedure is missing or the runtime role has no member. It does not prove that the correct API process identity is mapped to that role; DBA must verify the real API principal and effective permissions before use. No PLATFORM registration-center or legal publication Stored Procedures/routes are included because effective PLATFORM permission/Support policies are unavailable.

## Validation and application restrictions

- Do not use database backups as an excuse to create a TEST database; no test database is part of this package.
- Do not execute migration, grant, seed, user, role, or permission mutations without explicit DBA/product/security approval.
- Do not execute any SQL-mutating automated tests.
- Consent enforcement and both onboarding submission controls are seeded disabled. Keep them disabled until corresponding UI/legal/product/security requirements are approved and all dependencies are verified.
- No migration step seeds a candidate PDF or sets a version to APPROVED/PUBLISHED.
- Organization Tenant completion/activation is intentionally absent. Existing `ten.usp_CreateTenantWithOwner` creates a PENDING Organization but active Owner membership; `iam.usp_ValidateSessionAccess` accepts PENDING tenants. Do not use that path for Organization onboarding until policy and safe authorization behavior are approved.

## Read-only SQL validation status

All v1.6 migration, permission-template, preflight, and post-deployment scripts passed SQL Server `SET PARSEONLY ON` syntax parsing against the Development target. Parse-only validation did not execute any script. This is not semantic/dependency validation and is not SQL integration PASS; DBA review, fresh preflight, and explicit approval are still required.

## Rollback and recovery

No rollback script is provided because dropping registration/consent/history tables or restoring an older registration procedure after legal enforcement is enabled could destroy evidence or bypass mandatory consent. Given the observed partial Development deployment, do not drop objects or rerun migration scripts blindly. Before any DBA-approved forward repair, capture an owner-approved recoverable backup and reviewed source definitions. For failure during a future application, stop, preserve SQL error/output, check transaction state and catalog definitions read-only, and have the DBA apply a forward repair. If a rollback is considered before enforcement activation, first verify no registrations/consents were committed and reconstruct the exact prior `iam.usp_RegisterLocalUser` definition from the approved backup/source. Once enforcement is active or consent exists, rollback must preserve enforcement and immutable consent history. No Production rollback is authorized.
