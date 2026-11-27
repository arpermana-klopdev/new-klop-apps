# Platform Setup Backend Contracts

**Status:** This document retains the broader Platform Setup proposals. The Legal Documents section is superseded by the implementation and approval artifacts [PLATFORM_LEGAL_DOCUMENTS_BACKEND_REPORT.md](./PLATFORM_LEGAL_DOCUMENTS_BACKEND_REPORT.md), [PLATFORM_LEGAL_DOCUMENTS_API_CONTRACTS.md](./PLATFORM_LEGAL_DOCUMENTS_API_CONTRACTS.md), and [PLATFORM_LEGAL_DOCUMENTS_SQL_CHANGE_MANIFEST.md](./PLATFORM_LEGAL_DOCUMENTS_SQL_CHANGE_MANIFEST.md). Legal admin source routes and UI are implemented but gated; the v1.7 SQL delta and runtime grants are prepared only and have not been executed.

## 1. Existing mapped contracts

| Capability | Existing behavior | Boundary |
| --- | --- | --- |
| Organization type reference | `GET /api/v1/master/organization-types` returns active organization types. | Read-only list only; not a generic master-data API. |
| Current Terms metadata | `GET /api/v1/public/legal/terms/current?registrationType=...` returns effective PUBLISHED metadata or `404 TERMS_UNAVAILABLE`. | Public consent lookup; not an administrative catalog. |
| Published Terms file | `GET /api/v1/public/legal/terms/{documentVersionId}/file` returns a published document file. | Does not provide a privileged draft preview or document mutation path. |
| Configuration reads | Backend repository code calls `cfg.usp_Configuration_GetByKey`. | No frontend-facing configuration endpoint was found. Repository access is not a browser contract. |
| Authorization | Existing tenant authorization remains tenant-scoped. Legal administration now has a separate authenticated PLATFORM permission resolver backed by existing assignment/role/permission structures. | Legal mutation routes remain omitted unless `PlatformLegalDocuments:AdministrationEnabled=true`; the v1.7 resolver/procedures must be approved and deployed first. |
| Audit | Selected authentication and onboarding procedures write audit events. | No general setup audit-query API or complete setup mutation audit contract was found. |

Backend source evidence:

- `src/KLOP.Platform.Api/Endpoints/PlatformEndpointMappings.cs` maps Legal Documents administration only when its explicit enable flag is set; other Platform Setup modules remain unimplemented.
- `src/KLOP.Platform.Api/Endpoints/Legal/PublicLegalEndpoints.cs` maps public current-Terms and file reads only.
- `src/KLOP.Platform.Api/Authorization/TenantPermissionAuthorization.cs` remains tenant-scoped. Legal administration uses the separate `PlatformPermissionAuthorization.cs` path and does not rely on tenant membership.
- `database/migrations/v1.6/003_legal_read_procedures.sql` implements published legal reads and immutability protections; it does not create, approve, publish, or upload documents.
- `src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Repositories/MasterData/KlopMasterDataRepository.cs` contains repository-level organization/tenant-type and configuration reads; these are not mapped setup endpoints.

## 2. Authorization contract required before protected setup work

### Required invariant

Platform Setup authorization must be evaluated server-side against the authenticated principal and an effective **PLATFORM-scoped** permission. A tenant ID, tenant membership, client-supplied actor ID, email, display name, or role label must not substitute for this check.

### Authorization interface

The legal administration source resolves `sub`/`sid` from the authenticated principal, validates the active session, and checks action-specific effective PLATFORM permissions in the database. `GET /api/v1/platform/legal-documents/permissions` is for UI visibility only; every protected route and Stored Procedure repeats the required authorization. The current tenant requirement remains unchanged for tenant APIs.

Permission categories to define and seed only after the platform principal/assignment model is approved:

- Platform Setup read.
- Legal document draft create/edit/preview/submit-for-approval/approve/publish/archive.
- System configuration read/update/approve.
- Notification template read/update/approve.
- Platform access/approval administration.
- Setup audit read.

Do not map these categories to Platform Super Admin or Platform Support based on frontend labels alone. Determine the authoritative identity source, assignment lifecycle, grant/revoke audit, and separation-of-duties rules before creating permission records.

## 3. Proposed API contracts

The Registration Setup, System Configuration, Notifications, and Master Data paths below remain **proposals**. Legal Documents routes are implemented in source as described separately below. Every protected operation requires authenticated principal resolution, an action-specific PLATFORM permission, input validation, and server-generated audit actor identity.

### Legal Documents

The Legal Documents API routes below are now implemented in source and documented in `PLATFORM_LEGAL_DOCUMENTS_API_CONTRACTS.md`. They are not active unless explicitly enabled after the approved v1.7 SQL delta, grants, and private storage configuration are in place.

| Implemented route | Purpose | Authorization / invariants |
| --- | --- | --- |
| `GET /api/v1/platform/legal-documents` | List documents, current state, and scopes. | PLATFORM legal-read permission; pagination and filters. |
| `GET /api/v1/platform/legal-documents/{documentId}` | Read document metadata and version history. | PLATFORM legal-read permission. Never return storage paths or connection details. |
| `POST /api/v1/platform/legal-documents` | Upload a new DRAFT version and its metadata. | Draft-create permission; validate file type/size, calculate hash server-side, persist storage reference privately. |
| `PUT /api/v1/platform/legal-documents/versions/{versionId}` | Edit DRAFT metadata/scopes. | Draft-edit permission; reject non-DRAFT state and stale `ETag`/row version. |
| `GET /api/v1/platform/legal-documents/versions/{versionId}/preview` | Read a draft PDF for authorized review. | Draft-preview permission; do not broaden the public file procedure. |
| `POST /api/v1/platform/legal-documents/versions/{versionId}/submit-for-approval` | Submit a complete draft. | Submit permission; require a valid file/hash, version, effective date, and scopes. |
| `POST /api/v1/platform/legal-documents/versions/{versionId}/approve` | Record an approval decision. | Approval permission; require pending state and audit. Consider distinct submitter/approver identities as an explicit policy decision. |
| `POST /api/v1/platform/legal-documents/versions/{versionId}/publish` | Publish an approved version. | Publish permission; verify approval, effective-date rules, registration scopes, and no conflicting current version. |
| `POST /api/v1/platform/legal-documents/versions/{versionId}/archive` | Archive where legal policy permits. | Archive permission; preserve immutable publication and consent history. |

Lifecycle proposal: `DRAFT → PENDING_APPROVAL → APPROVED → PUBLISHED → ARCHIVED`. A denied approval returns to a controlled editable state with an audited decision. Published content and its scopes remain immutable; corrections require a new version. The current public Terms procedures remain the sole source of consent-eligible versions.

One version may serve PERSONAL and ORGANIZATION only when that same version has both verified scope rows. The API must return the actual `documentVersionId`; the frontend must never construct or reuse a placeholder ID.

Suggested errors include `PLATFORM_PERMISSION_REQUIRED`, `LEGAL_VERSION_NOT_DRAFT`, `LEGAL_APPROVAL_REQUIRED`, `LEGAL_VERSION_CONFLICT`, `LEGAL_SCOPE_INVALID`, `LEGAL_EFFECTIVE_DATE_INVALID`, `LEGAL_FILE_INVALID`, and `LEGAL_VERSION_OUTDATED`. Keep existing public error semantics intact.

### Registration Setup and System Configuration

| Proposed route | Purpose | Authorization / invariants |
| --- | --- | --- |
| `GET /api/v1/platform/setup/registration` | Return only the approved, non-secret registration/onboarding configuration fields needed by this page. | PLATFORM setup-read permission; values come from the authoritative configuration service, not frontend constants. |
| `GET /api/v1/platform/configurations` | List allowlisted configuration metadata and safe values. | Configuration-read permission; omit or redact secrets and sensitive values. |
| `PUT /api/v1/platform/configurations/{configurationKey}` | Submit a validated configuration change. | Configuration-update permission; optimistic concurrency (`ETag`/row version), validation, and audit. |
| `POST /api/v1/platform/configurations/{configurationKey}/approve` | Approve a pending sensitive change if required by policy. | Configuration-approve permission; enforce approved separation-of-duties policy. |

Use the existing configuration service/stored-procedure boundary where verified. Do not expose repository methods directly or add an alternate database access path. Confirm exact keys, sensitivity classification, data types, and approval rules from the authoritative Development definitions before writing SQL or response schemas.

### Notifications

Proposed future endpoints are `GET /api/v1/platform/notification-templates`, `PUT /api/v1/platform/notification-templates/{templateId}`, and an action endpoint for activation/approval if required. The contract must define supported template keys, channels, localized content, rendering validation, activation state, versioning, and delivery audit before the UI exposes editing.

### Master Data and audit

Keep the existing organization-type reference endpoint read-only. Add catalog-specific protected endpoints only after each catalog has a reviewed ownership, validation, versioning, and audit policy; do not add a generic write endpoint without those rules.

Provide a paginated, permission-checked setup audit query before showing administrative history. Setup mutation procedures must record authenticated actor, action, target, request/correlation ID, timestamp, and safe before/after values; never record secrets or raw document contents.

## 4. Versioned database prerequisites (review plan; not executable SQL)

No SQL changes were executed. Read-only Development inspection confirmed existing PLATFORM role, permission, and assignment objects; `database/migrations/v1.7/001_platform_legal_documents.sql` and the separate runtime grant template are prepared for manual review and approval. Do not treat them as applied migrations. See the SQL manifest for exact objects and approval requirements.

Legal document authorization, lifecycle procedures, audit, and the PENDING_APPROVAL state are prepared in the v1.7 delta cited above. The other Platform Setup modules still require their own reviewed schema/procedure work. Do not execute any script without explicit approval.

1. Prepare System Configuration allowlisted reads and validated updates with concurrency and audit.
2. Prepare Notification template administration only after ownership, versioning, and delivery policy are approved.
3. Add catalog-specific master-data procedures only after catalog ownership/validation policy is verified.
4. Add a general setup audit-query API only if the existing audit model cannot safely meet the reviewed query requirements.

Before any script is approved for deployment: compare against actual Development table/procedure definitions, test against a disposable isolated test database (not the Development database), review grant boundaries for runtime principals, verify rollback/forward-only policy, and obtain explicit database-owner approval. Do not rerun or alter existing v1.6 migrations as part of this work.

## 5. Frontend behavior and deployment gate

- Show public Terms metadata/file responses and the existing organization-type reference response.
- When Terms returns `TERMS_UNAVAILABLE`, show that no published version is available and label any local PDF as draft preview only.
- Keep Register API consent validation unchanged; a draft preview cannot make registration ready.
- Do not display configuration values that the API does not return.
- The Legal Documents page calls protected administration APIs only when the authenticated user has returned effective PLATFORM capabilities. The server independently checks each action.
- Protected routes are not mapped by default. Keep the administration feature flag disabled until the v1.7 migration, runtime grants, and private storage root are manually approved and deployed.
- Notification and configuration mutations remain absent. Platform authorization is not inferred from profile labels or tenant roles.
