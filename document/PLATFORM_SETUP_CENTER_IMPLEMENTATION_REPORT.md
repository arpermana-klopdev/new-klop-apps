# Platform Setup Center Implementation Report

## 1. Scope and existing backend mapping

The original task implemented a read-only Platform Setup foundation with six sections. A follow-up Legal Documents backend enhancement now adds protected administration source code and frontend wiring; it remains feature-gated pending manual Development approval. The Registration Center remains separate, and existing authentication, registration, and tenant flows were not changed.

| Section | Verified current capability |
| --- | --- |
| Registration Setup | Existing Register and email-verification behavior remains authoritative. No frontend-facing API exposes the database-backed registration settings requested for display. |
| Legal Documents | Existing public current-Terms metadata and PDF APIs remain unchanged. Protected draft lifecycle APIs/UI are implemented in source and require effective PLATFORM permissions, but are omitted unless `PlatformLegalDocuments:AdministrationEnabled=true`. Development previously had no legal document/version/scope records; the v1.7 SQL delta and runtime grants are prepared but not executed. The local PDF remains a draft preview until an authorized user uploads it. |
| Master Data | Reuses `GET /api/v1/master/organization-types` for a read-only organization-type list. No generic catalog administration API is available. |
| System Configuration | No frontend-facing configuration API is mapped. Backend repository-level reads do not constitute a frontend contract. |
| Notifications | No notification template, channel, activation, or approval API is mapped. |
| Access & Approval | Legal Documents has a separate session-validated PLATFORM permission handler and audited approval API. Other Platform Setup authorization/approval modules remain unimplemented; tenant authorization remains unchanged. |

The backend exposes public legal reads through `PublicLegalEndpoints.cs`; those endpoints and their consent rules were not changed. Protected administration routes are described in [PLATFORM_LEGAL_DOCUMENTS_API_CONTRACTS.md](./PLATFORM_LEGAL_DOCUMENTS_API_CONTRACTS.md) and gated behind an explicit configuration flag. See [PLATFORM_LEGAL_DOCUMENTS_BACKEND_REPORT.md](./PLATFORM_LEGAL_DOCUMENTS_BACKEND_REPORT.md) and [PLATFORM_LEGAL_DOCUMENTS_SQL_CHANGE_MANIFEST.md](./PLATFORM_LEGAL_DOCUMENTS_SQL_CHANGE_MANIFEST.md) for deployment prerequisites.

## 2. Files changed

- `klop-next_ui/src/app/modules.ts` — adds one primary Platform Setup navigation entry and six non-primary nested sections.
- `klop-next_ui/src/app/App.tsx` — adds the section routes and redirects legacy Master Data, Configuration, and Notifications routes.
- `klop-next_ui/src/components/AppShell.tsx` — displays nested route titles and removes the duplicate Notifications account-menu link.
- `klop-next_ui/src/features/setup/PlatformSetupPages.tsx` — implements the landing page, Registration Setup, Master Data, System Configuration, Notifications, and Access & Approval.
- `klop-next_ui/src/features/setup/LegalDocumentsPage.tsx` — reads current Terms for both registration types, groups matching backend version IDs, and provides published/local-draft read-only previews.
- `klop-next_ui/src/styles/terms-document.css` — shares the existing modal/PDF viewer layout styles with the Legal Documents preview.
- `klop-next_ui/src/features/auth/TermsPdfViewer.tsx` and `klop-next_ui/src/features/auth/login.css` — move shared viewer/modal styles without changing the existing Register acceptance behavior.
- `klop-next_ui/tests/AppShell.test.tsx`, `klop-next_ui/tests/modules.test.ts` — verify primary navigation and section routing metadata.
- `klop-next_ui/tests/PlatformSetupPages.test.tsx`, `klop-next_ui/tests/LegalDocumentsPage.test.tsx` — cover section inventory, organization-type read, published-version grouping, unavailable Terms, draft preview, and API error distinction.

## 3. Authorization and data safety

- The pages make no database calls from the browser and perform no writes.
- No permissions, users, roles, tenants, or legal records have been created in Development. The unexecuted v1.7 SQL proposal seeds permission definitions and maps them only to existing PLATFORM roles if approved.
- The local Terms PDF is labeled as a draft preview; it does not receive a generated document ID, publication state, or consent record.
- No global access is inferred from a profile name or a tenant-scoped permission. Legal administrative operations require backend effective PLATFORM permission validation.
- Legal controls are shown only with effective capabilities; other setup administration remains unavailable.
- No SQL was executed. The v1.7 schema/procedure delta and separate runtime grant template are prepared for manual review only. The existing PLATFORM assignment schema was confirmed through read-only Development inspection.

## 4. Validation

| Check | Result |
| --- | --- |
| `npm run typecheck` | Pass |
| `npm test` | Pass — 71 tests |
| `npm run build` | Pass — Vite production build completed; Rollup emitted non-blocking annotation warnings from installed Zod dependencies. |

Backend source and database were not modified, so no backend build or database test was run. No manual browser or mobile visual verification is claimed.

## 5. Remaining blockers

1. **Legal Documents:** Development still has no registered/published Terms version for either scope. The local PDF remains preview-only until an authorized upload and subsequent human approval/publication. Register must continue enforcing published-version consent.
2. **Legal Documents deployment:** Review/apply v1.7 SQL and runtime grants, configure a private storage root, and explicitly enable the feature flag before using administrative routes.
3. **Other Access & Approval modules:** Effective PLATFORM-scoped permission checks and approval APIs remain out of scope and unavailable.
4. **Registration/System Configuration:** No frontend-facing read contract currently returns the requested database-backed values; sensitive settings must not be surfaced by direct database access or inferred defaults.
5. **Master Data:** Only organization-type reference data is currently available to this frontend; editing and other catalogs need explicit API contracts.
6. **Notifications/Audit:** Template management and a general setup audit-query API are not currently mapped.

## 6. Manual verification steps

1. Sign in and confirm the primary navigation shows one **Platform Setup** entry while **Registrations** remains separate.
2. Open Platform Setup and confirm all six sections appear with their real read/API availability states.
3. Open **Legal Documents**. Confirm PERSONAL and ORGANIZATION statuses come from the public Terms API. When the API returns `TERMS_UNAVAILABLE`, confirm the local PDF is labeled draft-only and can be previewed without creating consent. Protected administration stays unavailable until the v1.7 deployment/configuration prerequisites are met.
4. If a published Terms version exists, confirm its returned metadata, applicable registration scope(s), and PDF can be viewed. Matching version IDs should appear once with both scopes.
5. Open **Master Data** and confirm only API-returned organization types are displayed. Retry behavior should be visible on API failure.
6. Open Registration Setup, System Configuration, Notifications, and Access & Approval. Confirm unavailable values/actions are not fabricated or editable.
7. Navigate to `/master-data`, `/configuration`, and `/notifications`; confirm each redirects into the corresponding Platform Setup section.
8. Recheck Register, email verification, and Login separately; this task did not alter those flows.
