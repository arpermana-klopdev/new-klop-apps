# KLOP Registration Backend Enhancement Report

**Status:** PARTIAL IMPLEMENTATION COMPLETE — API/source changes are present; Development catalog verification on 2026-11-23 found a partial v1.6 deployment. Legal reads, runtime security, and policy-gated flows remain blocked.  
**Database changes by this task:** NONE. Only read-only catalog inspection and the read-only post-deployment verifier were run; no migration, DML, DDL, grant, Stored Procedure execution, or database creation was performed.  
**Baseline:** Frozen v1.1 and historical v1.4/v1.5 proposals remain untouched. v1.6 package files are additive; Development reflects a partial deployment with unknown exact script lineage.  
**Deployment approval:** NOT APPROVED.

## Latest Development Post-Deployment Verification — 2026-11-23

The operator reported that SQL v1.6 had been run. Read-only inspection of `DEV-PC\SQLEXPRESS / KlopPlatformDB` confirms a **partial, unversioned deployment**, not a complete v1.6 rollout. The exact deployed migration chain cannot be inferred because the database has no migration marker or deployment record.

| Check | Latest Development evidence | Result |
|---|---|---|
| `reg` and `leg` schemas; all ten v1.6 tables; registration/onboarding procedures | Present. `iam.usp_RegisterLocalUser` has the v1.6 intent/consent parameters; all six `reg` procedures are present with the expected parameter names/types. | Present, but exact deployment version cannot be established. |
| Public legal read procedures | `leg.usp_GetCurrentTerms` and `leg.usp_GetPublicTermsFile` are absent. | **BLOCKER** |
| Legal immutability protections | `trg_LegalDocumentVersions_Immutable`, `trg_LegalDocumentVersionScopes_Immutable`, and `trg_UserLegalConsents_AppendOnly` are absent. | **BLOCKER** |
| Onboarding status codes | All seven required codes are active. | PASS |
| Referential integrity, uniqueness, concurrency | The new-table foreign keys inspected are enabled/trusted; the expected current-application, legal-version/scope/consent, and storage-reference unique keys exist. Rowversion columns exist on the status, application, profile, supporting-document, and legal-version tables that define them in the schema script. | PASS for inspected catalog constraints. |
| Policy configuration | Registration PERSONAL/ORGANIZATION are `true`; legal-consent enforcement and both onboarding submission controls are `false`. Required v1.6 metadata passed the verifier. | Consent and submission remain disabled; no policy was changed. |
| Terms publication and organization requirements | No Terms versions are present; organization requirement group and requirement counts are both zero. | **BLOCKER** for new intent/consent E2E and Organization requirements. |
| Runtime identity and grants | Development API configuration uses Integrated Security. The inspection connection was `DEV-PC\rajaa` mapped to `dbo` with `sysadmin`; this is not proof of API identity. `klop_app_runtime` has zero members. Of 28 repository-required procedures, 8 have EXECUTE granted to the role, 18 existing Authentication/Tenant/Master/Configuration procedures lack grants, and 2 legal procedures are missing. | **BLOCKER**; actual API identity/effective grants are unverified. |

The read-only `database/migrations/v1.6/004_postdeploy_READONLY.sql` verifier was run. It reported the two missing legal procedures, missing immutability triggers, and an empty runtime role, then exited with SQL error 51620 as designed. The preflight script was not run because its intended pre-deployment absence checks would be invalid after partial deployment. No repair or grant was applied.

### Required EXECUTE matrix (source-backed)

The unexecuted `database/security/v1.6_runtime_grants_TEMPLATE.sql` now contains the complete 28-procedure proposal and prechecks for role membership and object existence. Its currently observed state is:

| Category | Procedures with EXECUTE on role | Missing EXECUTE grant | Object missing |
|---|---|---|---|
| Authentication | — | `iam.usp_ConfirmEmail`, `iam.usp_CreateAuthSession`, `iam.usp_GetLocalLoginCandidate`, `iam.usp_GetUserProfile`, `iam.usp_IssueEmailVerificationChallenge`, `iam.usp_RecordLocalLoginFailure`, `iam.usp_RevokeAuthSession`, `iam.usp_RotateRefreshToken`, `iam.usp_ValidateSessionAccess` | — |
| Registration | `iam.usp_RegisterLocalUser` | — | — |
| Master | `mst.usp_TenantType_GetAll` | `mst.usp_OrganizationType_GetAll` | — |
| Configuration | — | `cfg.usp_Configuration_GetByKey` | — |
| Tenant | — | `iam.usp_AssignTenantRole`, `iam.usp_RevokeTenantRole`, `ten.usp_AcceptMembership`, `ten.usp_CreateTenantWithOwner`, `ten.usp_InviteExistingUser`, `ten.usp_ListMyTenants`, `ten.usp_RemoveTenantMember` | — |
| Onboarding | `reg.usp_GetApplicationForOwner`, `reg.usp_GetMyApplication`, `reg.usp_GetOrganizationRequirements`, `reg.usp_SaveOrganizationDraft`, `reg.usp_SavePersonalDraft`, `reg.usp_SubmitOnboarding` | — | — |
| Legal | — | — | `leg.usp_GetCurrentTerms`, `leg.usp_GetPublicTermsFile` |

The current role has no members, so even the eight role grants do not establish effective access for the API. Have the DBA identify/map the real API principal and validate permissions as that identity. Do not execute the template, grant permissions, or change role membership during this task.

### Contract/E2E readiness

The API source exposes the documented public Terms routes, registration intent/consent fields, authenticated owner-scoped onboarding routes, and policy-pending/error mappings. The SQL-backed Terms endpoint is currently unavailable because its procedures are missing; typed registration cannot succeed until an applicable published Terms version exists. Submission correctly remains disabled by policy, and the empty Organization ruleset returns unavailable. The repository contains no frontend application or Terms modal, so browser-side wiring and frontend/backend E2E compatibility could not be verified here. Existing Authentication source routes are unchanged; the Development API's use of the sysadmin inspection identity must not be used as evidence of regression-safe runtime permissions.

**Manual Development E2E: NOT READY.** Blockers: legal procedures/immutability triggers absent; no published Terms version; runtime principal not validated and runtime role empty/incomplete; Organization requirement masters empty; submission policies disabled. No database or production repair is authorized by this report.

## 1. Current Backend Assessment

The solution is a .NET 10 Minimal API with API, Application, Domain, Infrastructure, and test projects. The API maps Authentication, Master, System, and Tenant endpoints from `src/KLOP.Platform.Api/Endpoints/PlatformEndpointMappings.cs`. Application services use `IPlatformRepository`; the Dapper repository invokes named Stored Procedures only. Request validation uses FluentValidation; API results use the existing envelope and RFC 9457 error mapping. Existing unit tests are xUnit; database integration tests are guarded and write-capable tests are not to be run without approval.

The current source contains public Terms read APIs, a configured non-public PDF storage adapter, owner-scoped onboarding endpoints, registration intent/consent plumbing, and v1.6 SQL drafts. Platform administration, final Tenant creation, and activation remain blocked by missing authorization and business policies. This execution verified source and Development catalog metadata read-only, ran the read-only post-deployment verifier, and syntax-parsed the grant proposal only; no migration/grant/data-operation script was executed.

## 2. Existing Authentication Contracts

Existing public routes and handler/service paths remain unchanged:

- `POST /api/v1/auth/register` — generic HTTP 202; delegates to `AuthenticationService.Register` and `iam.usp_RegisterLocalUser`.
- `POST /api/v1/auth/resend-verification` — generic HTTP 202; uses the existing challenge flow.
- `POST /api/v1/auth/verify-email` — existing single-use email challenge confirmation.
- `POST /api/v1/auth/login`, `/refresh`, `/logout`, and `GET /me` — existing password, session, refresh rotation, cookie, origin, JWT, and profile behavior.

`RegistrationRequest` accepts `email`, `password`, and `fullName` (with the existing `displayName` compatibility alias), plus optional `registrationType`, `termsDocumentVersionId`, and `termsAccepted`. When type is present, validation requires a supported type, a non-empty version ID, and explicit acceptance. `AuthenticationService` uses the existing `PasswordCodec`, passes only a SHA-256 verification-token hash and the intent/consent fields to the repository, and sends email after the repository reports commit. SMTP delivery failures are logged without falsely claiming the account transaction rolled back. The register flow does not create a Tenant or assign roles. The Development registration procedure has the v1.6 parameters and consent/application body, but the full legal runtime path is blocked by missing public legal procedures/triggers and no published document.

## 3. Existing Database Object Inventory (pre-deployment snapshot)

Source-backed procedure dependencies found include `iam.usp_RegisterLocalUser`, `iam.usp_ConfirmEmail`, `iam.usp_IssueEmailVerificationChallenge`, `iam.usp_GetLocalLoginCandidate`, `iam.usp_CreateAuthSession`, `iam.usp_RotateRefreshToken`, `iam.usp_RevokeAuthSession`, `iam.usp_ValidateSessionAccess`, `iam.usp_GetUserProfile`, `ten.usp_CreateTenantWithOwner`, `ten.usp_ListMyTenants`, tenant membership/role procedures, master-data procedures, and `cfg.usp_Configuration_GetByKey`.

This inventory describes the pre-deployment catalog and is retained as historical evidence. See “Latest Development Post-Deployment Verification” above for the current catalog. The current database still has no migration/version marker, so neither the earlier nor current catalog can establish the exact applied script lineage.

Relevant live column contracts include `iam.Users.Email`/`NormalizedEmail` (`NVARCHAR(640)`) and `DisplayName` (`NVARCHAR(300)`), `iam.UserCredentials.PasswordHash` (`NVARCHAR(2048)`), and `iam.VerificationChallenges.TokenHash` (`BINARY(32)`) with expiry/consumed/invalidated timestamps. Unique indexes enforce normalized-email uniqueness, one credential row per user, verification token-hash uniqueness, Tenant Type code uniqueness, and membership/role uniqueness. `ten.Organizations` is keyed by TenantId and references Organization Type and Verification Status; `iam.TenantRoleAssignments` references tenant membership and role masters. Audit, Security, and Business event tables contain the expected event/actor/target/correlation fields. The new API limits registration names/email to narrower request-validator sizes than database columns; no column expansion is needed for this contract.

The current deployed `iam.usp_RegisterLocalUser` owns a transaction and inserts the user, credential, email challenge, and audit event; duplicate normalized email uses error 52113. `iam.usp_ConfirmEmail` consumes an unexpired, non-invalidated challenge and invalidates other outstanding challenges. `ten.usp_CreateTenantWithOwner` resolves master IDs by code, creates PERSONAL Tenants as ACTIVE and ORGANIZATION Tenants as PENDING, and assigns an ACTIVE Owner membership in either case. `iam.usp_ValidateSessionAccess` accepts ACTIVE and PENDING Tenant statuses. Therefore the existing Tenant procedure must not be used by ORGANIZATION onboarding before an approved activation policy and safe authorization behavior are established.

The current catalog was queried read-only for object/column metadata, master counts/codes, relevant procedure definitions, configuration-key metadata (not values), and the SQL caller/runtime-role gate. No DDL, data mutation, or SQL permission change was run.

The repository does not contain authoritative historical table DDL. Current catalog metadata confirmed the requested baseline tables and relevant columns, absence of `reg`/`leg` schemas and onboarding/legal procedures, and absence of a database migration marker. The exact deployed baseline/package chain cannot be independently established from SQL metadata; DBA confirmation is required before applying the prepared delta.

## 4. Registration/Onboarding Gap Analysis (completed before code changes)

| Capability | Current evidence | Gap / safe implementation constraint |
|---|---|---|
| Registration intent | Register accepts no registration type; no application model or retrieval endpoint | Schema/procedures are absent, but the live registration SP transaction and relevant existing user/master metadata were inspected. A new additive `reg`/`leg` model and same-transaction registration SP extension can now be prepared. |
| Atomic account, challenge, intent, consent, audit | Live `iam.usp_RegisterLocalUser` owns a transaction and inserts user, credential, email challenge, and audit | A compatible optional extension of the existing procedure is feasible; consent and application must be inserted in that same transaction. No second registration call is acceptable. |
| Legal documents and consent | No legal-document model/storage, endpoint, or consent record found | Can prepare normalized metadata/consent tables and read SP contracts. Storage provider and authorized approval/publication policy are still unavailable; do not expose admin publishing endpoints. |
| Email verification | Existing verification is implemented and must be reused | No new verification engine is justified; authenticated onboarding must rely on the existing verified-session gate. |
| Onboarding | No registration application/status workflow or onboarding API found | Status transitions, ownership, idempotency, concurrency, and database transactions require new stored procedures and schema. |
| Personal/organization profiles | Existing tenant creation accepts type code; product-required personal fields and organization requirements are not defined in code | Do not invent identity requirements. Organization completion/activation remains blocked by business policy. |
| Tenant completion | Live `ten.usp_CreateTenantWithOwner` and `iam.usp_ValidateSessionAccess` bodies inspected | Existing procedure creates an ACTIVE membership and OWNER role for both types; it creates ORGANIZATION as PENDING, and session authorization still allows PENDING tenants. Do not use for onboarding until organization policy and a safe idempotent permission boundary are approved. |
| Platform registration center | No PLATFORM-scoped permission handler or current admin permission contract found | No administrative route may be exposed until effective permissions and restricted Support policy are defined in SQL and runtime authorization. |
| Legal-document administration | No platform publication authorization or approved storage exists | Do not create unsecured upload/publish endpoints or imply drafts are approved/published. |
| Database versioning/rollout | Workspace has v1.4/v1.5 proposals; no database schema version marker exists | Prepare a new additive v1.6 package with preflight/post-deploy checks; do not modify any historical package. |
| SQL runtime least privilege | Current read-only inspection reports current caller as sysadmin/db_owner/db_ddladmin; runtime role is not the current caller and has one mapped EXECUTE grant | New APIs requiring SQL remain disabled/blocked until an approved least-privilege identity and grants are established and verified. |
| Database testing | Existing tests include gated persistent-write integration tests | Do not run mutation-capable tests, create a test database, or claim integration success. |

## 5. New Registration Intent Design

Target design is an application record linked to the global user and the master tenant-type stable code (`PERSONAL` or `ORGANIZATION`), not a role, permanent user type, or Tenant membership. It needs explicit onboarding state, UTC timestamps, completion timestamp, optional Tenant link, rowversion, correlation/audit references, uniqueness protection for one active initial application per user, and append-only event history. Legacy users without an application remain unclassified. Future multi-Tenant membership remains independent of initial registration intent.

**Status: SOURCE IMPLEMENTED; PARTIALLY DEPLOYED IN DEVELOPMENT** — the new `reg.RegistrationApplications` model links the global user to a master Tenant Type resolved by stable code, with onboarding status, timestamps, optional Tenant, rowversion, and correlation/history references. New registration fields are optional for coordinated rollout; the observed register procedure has v1.6 intent/consent parameters. Legacy users remain unclassified, no Tenant/role is created, and no registration type change endpoint exists. Consent enforcement remains disabled; no Terms version is published, so typed registration is not ready for E2E.

## 6. Legal Documents Data Model

Target normalized design separates logical document metadata, immutable versions, and registration-type scopes. A version records type/title/version/effective date/publication state/storage reference/SHA-256/MIME/size/timestamps/author/publisher/archive time. State transitions are Draft → Approved → Published → Archived only under approved policy; published bytes and scope are immutable. Shared binary versions can be scoped to both registration types without duplication. Binary storage must remain outside SQL and outside any public static directory, with a deployment-owned provider and no business-logic disk paths.

**Status: PUBLIC READ API IMPLEMENTED; DEVELOPMENT SQL INCOMPLETE; ADMINISTRATION BLOCKED** — normalized version/scope tables exist, but both public read procedures and the three immutability triggers are absent. The API's configured external-file storage adapter checks opaque references, containment, PDF signature, length, and recorded SHA-256. No upload/approve/publish/archive API or approved publication policy exists. No Terms version is present/published; the frontend PDF remains an unpublished legal-review candidate and was not copied or published.

## 7. Legal Consent Data Model

Target consent is append-only and links user, registration application, selected registration type, immutable legal version/hash, purpose, server-generated UTC accepted time, source, and correlation ID. API validation must resolve the currently effective published version and compare the submitted version and registration scope inside the same authoritative registration transaction. Client timestamps and hashes are never authoritative.

**Status: SOURCE AND SQL DRAFT IMPLEMENTED** — the API requires explicit `termsAccepted: true`, registration type, and version ID for the new contract; SQL resolves the published/effective scoped version and stored hash and timestamps the append-only consent in the existing account transaction. Client times/hashes are not accepted. The document/version tables and consent triggers/procedures are prepared only; historical consent is not modified.

## 8. Updated Register Contract

Existing deployed request remains compatible: `email`, `fullName` (or legacy `displayName`), and `password`. Intended new fields are `registrationType`, `termsDocumentVersionId`, and `termsAccepted`; confirm-password remains frontend-only. The implementation must not accept and silently ignore these fields as proof of consent. The register endpoint remains generic HTTP 202 and must use one atomic SP for account, credential, application, consent, verification challenge, and audit writes when activated.

**Status: IMPLEMENTED IN SOURCE; REGISTER PROCEDURE PRESENT, TERMS DEPENDENCIES MISSING** — optional request fields preserve the current JSON contract. A complete selected-registration payload is passed to the existing registration Stored Procedure; observed procedure signature/body includes v1.6 intent/consent fields. Existing password, verification, generic HTTP 202 duplicate handling, and email recovery behavior remain intact. Missing intent is permitted only while the database policy is disabled; when enforcement is enabled, SQL rejects it. No current/published Terms record exists, so typed registration cannot succeed until legal dependencies are complete.

## 9. Email Verification Integration

Reuse existing challenge creation, resend, confirmation, token hashing, expiry, replay prevention, and verified-login rules. Verification must not create a Tenant. Onboarding must require the existing authenticated/verified session state and application ownership.

**Status: EXISTING ENGINE PRESERVED; ONBOARDING ROUTES IMPLEMENTED** — onboarding endpoints require authorization and rely on the existing JWT/session validation path, which rechecks active/verified identity. Verification still creates no Tenant. SQL deployment and runtime EXECUTE grants are prerequisites for these routes.

## 10. PERSONAL Onboarding Design

A separate extensible Personal Profile should capture only approved personal/contact/address/country/region and additional verification data. No NIK/KTP requirement is inferred. Draft save must not create a Tenant. Final completion requires verified identity, valid intent/consent, approved rules, idempotent Tenant creation with `PERSONAL` resolved by code, Owner membership/role through existing authorized mechanisms, event recording, and application-to-Tenant linkage.

**Status: DRAFT API AND SQL PREPARED** — authenticated Personal draft reads/writes are owner-scoped and concurrency-protected, with optional contact/address fields and no invented NIK/KTP requirement. Draft save and submission do not create a Tenant. Tenant/Owner completion remains blocked pending approved requirements and a policy-safe, idempotent transaction.

## 11. ORGANIZATION Onboarding Design

A separate Organization onboarding profile should resolve organization type and identity requirements from SQL masters, preserving country, effective dates, conditionality, active status, and ALL/ANY/MINIMUM grouping. It must not hardcode NPWP/NIB requirements. Supporting-document references must retain auditability. The prospective representative is the authenticated global user.

**Status: DRAFT/REQUIREMENTS APIs AND SQL PRESENT; SUBMISSION/ACTIVATION BLOCKED** — the requirement-group and requirement tables exist, but read-only counts are zero. Draft persistence procedures are present; the API treats an empty applicable requirement set as unavailable, not as “no documents required.” Submission policies are disabled. Final Tenant activation remains BLOCKED BY BUSINESS POLICY because existing session authorization accepts PENDING tenants with active Owner membership.

## 12. Onboarding Status and State Transitions

Target persisted statuses: DRAFT, SUBMITTED, UNDER_REVIEW, NEEDS_REVISION, APPROVED, REJECTED, COMPLETED. Email verification, onboarding state, organization verification, and Tenant operational status are distinct. Transition rules, permissions, idempotency, and rowversion checks belong in SQL procedures.

**Status: DRAFT WORKFLOW PREPARED** — the new delta adds database-backed status codes, history, rowversion concurrency, owner-scoped draft procedures, and a submit procedure guarded by disabled-by-default PERSONAL/ORGANIZATION policy settings. Email verification, onboarding state, organization verification, and Tenant operational status remain distinct. Administrative transitions are not implemented without permission policy.

## 13. Tenant Creation Integration

Existing `POST /api/v1/tenants/` and `ten.usp_CreateTenantWithOwner` are preserved. Registration will not create a Tenant. Onboarding completion may reuse the established Tenant operation only after its stored procedure invariants and required authorization are reviewed and an idempotent transaction linking Tenant, Owner, profile, and application is approved.

**Status: BLOCKED FOR ONBOARDING COMPLETION** — actual creation and authorization procedures were inspected. Existing `ten.usp_CreateTenantWithOwner` is not idempotent and grants active Owner membership for PENDING ORGs; do not call it for onboarding until the organization activation policy is approved and a new guarded transaction preserves the existing invariants.

## 14. Platform Registration Monitoring APIs

No `GET /api/v1/platform/registrations` routes were added. Existing authorization only checks tenant-scoped permissions; no effective PLATFORM permission contract or restricted Support access policy was found. Adding routes without that control would expose registrations insecurely.

**Status: BLOCKED.**

## 15. Legal Document Administration APIs

No upload/approve/publish/archive API was added. Ordinary users/Tenant Owners must not publish global legal documents. Platform Admin authorization, approval policy, storage, immutable version logic, and audit SP contracts are not available.

**Status: BLOCKED.**

## 16. New/Modified Stored Procedures

Current catalog reflects some of these procedures, but the exact applied chain is unverified and the legal procedure script is incomplete/not reflected.

## 17. New Versioned SQL Migration Package

The current Development catalog reflects partial v1.6 objects; exact script execution and approval records are unavailable. The grant proposal remains unexecuted.

## 18. Least-Privilege Permission Proposal

New procedures require explicit EXECUTE grants to the approved API runtime role, never table DML or DDL rights. The historical repository report says the runtime role/grants are not ready and the observed caller is privileged. No grant or SQL identity change was made.

## 19. Logging and Audit Integration

Existing compact request completion logging and correlation are preserved. Safe correlated failure stages now cover registration, verification, legal-document, and onboarding operations. Passwords, hashes, tokens, request bodies, legal binaries, and identity document contents must not be logged. Authoritative registration/consent/onboarding/publication events are defined in the Stored Procedure delta, not substituted with application logs.

## 20. Backward Compatibility Strategy

The existing registration fields remain accepted, and the generic HTTP 202 response plus login/verification/session behavior are preserved; optional type/Terms fields are additive. Future rollout must deploy reviewed database additions first, deploy backend support compatibly, publish only legally reviewed documents, then deploy frontend fields and activate mandatory consent through an approved database policy. Missing consent/version must fail closed after activation; old clients must not bypass consent. No Production rollout or mandatory-consent activation occurred.

## 21. Changed Backend Files

**New application/API/infrastructure files:**

- `src/KLOP.Platform.Application/Features/Registration/RegistrationContracts.cs`
- `src/KLOP.Platform.Application/Features/Registration/RegistrationValidators.cs`
- `src/KLOP.Platform.Application/Features/Registration/LegalTermsService.cs`
- `src/KLOP.Platform.Application/Features/Registration/OnboardingService.cs`
- `src/KLOP.Platform.Api/Endpoints/Legal/PublicLegalEndpoints.cs`
- `src/KLOP.Platform.Api/Endpoints/Legal/PublicLegalHandlers.cs`
- `src/KLOP.Platform.Api/Endpoints/Onboarding/OnboardingEndpoints.cs`
- `src/KLOP.Platform.Api/Endpoints/Onboarding/OnboardingHandlers.cs`
- `src/KLOP.Platform.Infrastructure/Persistence/SqlServer/LegalDocuments/FileSystemLegalDocumentStorage.cs`
- `src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/Registration/KlopRegistrationRepository.cs`

**Modified integration points:** `src/KLOP.Platform.Application/Features/Contracts.cs`, `src/KLOP.Platform.Application/Features/Authentication/AuthenticationValidators.cs`, `src/KLOP.Platform.Application/Features/Authentication/AuthenticationService.cs`, `src/KLOP.Platform.Application/Abstractions/Persistence/IPlatformRepository.cs`, `src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/Identity/KlopIdentityRepository.cs`, `src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/KlopRepository.cs`, `src/KLOP.Platform.Infrastructure/DependencyInjection/InfrastructureRegistration.cs`, `src/KLOP.Platform.Api/Bootstrap/ServiceRegistration.cs`, `src/KLOP.Platform.Api/Endpoints/PlatformEndpointMappings.cs`, `src/KLOP.Platform.Api/Endpoints/Authentication/AuthenticationEndpoints.cs`, `src/KLOP.Platform.Api/Extensions/ApiHelpers.cs`, and `src/KLOP.Platform.Api/Logging/RequestLoggingMiddleware.cs`.

**Tests updated/added:** `tests/KLOP.Platform.UnitTests/Registration/RegistrationEnhancementTests.cs`, `tests/KLOP.Platform.UnitTests/ApiContracts/ApiRouteContractTests.cs`, Authentication unit tests, and `tests/KLOP.Platform.IntegrationTests/Persistence/DatabaseWorkflowTests.cs` (signature compatibility only; integration tests not run).

## 22. New SQL Scripts

New v1.6 drafts: `database/migrations/v1.6/000_preflight_READONLY.sql`, `001_registration_onboarding_schema.sql`, `002_registration_onboarding_procedures.sql`, `003_legal_read_procedures.sql`, and `004_postdeploy_READONLY.sql`; permission proposal: `database/security/v1.6_runtime_grants_TEMPLATE.sql`. The current Development catalog reflects portions of 001/002, does not reflect the legal procedures/guards from 003, and the 004 read-only verifier was run. Exact execution lineage is unknown; the permission proposal remains unexecuted and all corrective changes require DBA/product/security approval. `REGISTRATION_DATABASE_CHANGE_MANIFEST.md` documents dependencies, order, verification, approval gates, and recovery. No historical/frozen SQL file was edited.

## 23. Build Results

**PASS (verified in this execution)** — `dotnet build KLOP.Platform.sln --no-restore` completed with 0 warnings and 0 errors.

## 24. Unit Test Results

**PASS (verified in this execution)** — `dotnet test tests\\KLOP.Platform.UnitTests\\KLOP.Platform.UnitTests.csproj --no-build --no-restore`: 105 passed, 0 failed, 0 skipped. Database integration tests and SQL-mutating tests were not run. These mocked/unit results do not establish SQL integration or cover the blocked full end-to-end Tenant activation flow.

## 25. Prior Database-Unchanged Confirmation (historical)

The earlier implementation execution performed read-only inspection and SQL Server `SET PARSEONLY ON`; it did not alter the database. The current task separately ran read-only catalog queries and the read-only post-deployment verifier. No SQL DML, DDL, migration, seed, grant, user/role/permission update, database creation, or data-operation Stored Procedure execution occurred in this task. The frozen v1.1 baseline and historical SQL scripts were not edited.

## 26. Remaining Business Policy Decisions

- Exact approved PERSONAL and ORGANIZATION draft/completion fields and required validations.
- Whether ORGANIZATION Tenants are created before or only after manual verification; activation must remain blocked until resolved.
- Legal review/approval and effective date of the candidate frontend PDF.
- Authorized legal document publication/approval roles and any dual-control requirements.
- Platform Support visibility and field-level privacy policy.
- Retention, privacy metadata, and supporting-document storage provider/size limits.
- Reconciliation policy for abandoned registration/onboarding applications.

## 27. Manual Development Integration Checklist

1. Provide authoritative current schema/table/procedure definitions and actual database version/manifest for the existing Development database.
2. Confirm database baseline/version, target isolation, backup/recovery, and DBA approval.
3. Review new schema/procedures and permission set; keep scripts unexecuted until explicit approval.
4. Approve business requirements and Organization activation policy.
5. Approve legal PDF publication after legal review; configure secured non-public storage.
6. Establish/verify a least-privilege runtime principal and explicit EXECUTE grants.
7. Obtain an approved forward repair/deployment plan for the observed partial state; then run the read-only post-deployment/invariant checks. Do not rerun preflight without DBA review.
8. Enable the backend and compatible frontend contract only after prerequisites pass.
9. Run manual end-to-end testing against approved Development using authorized accounts and monitor audit/diagnostics.
10. Production deployment remains subject to separate approvals.

## 28. Rollback/Recovery Guidance

The current database has a partial deployment with unknown exact script lineage; the v1.6 manifest documents stop-and-repair guidance rather than a destructive rollback. Obtain DBA review before any forward repair. Preserve transaction/audit evidence. Published legal versions and accepted consent history must never be destructively edited. Binary storage/metadata failures need approved compensation/quarantine before upload is enabled. Never reset users, modify historical consent, or roll back the frozen baseline.

## 29. Production Readiness Blockers

**BLOCKED / NOT PRODUCTION READY.** The current Development catalog shows partial v1.6 deployment, missing public legal procedures/immutability triggers, no published Terms version, empty Organization requirements, disabled onboarding submission, and incomplete runtime EXECUTE grants with no runtime-role members. The API's actual SQL principal/effective permissions have not been verified; the sysadmin inspection connection is not proof of API access. Legal publication authorization, PLATFORM permission contracts, and Organization activation policy remain unavailable. No manual E2E is possible until these blockers are resolved through separately approved changes.
