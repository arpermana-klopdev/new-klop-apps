# Platform Legal Documents Backend Report

## 1. Existing implementation and mapping

- The Register flow continues to use `GET /api/v1/public/legal/terms/current` and the existing public PDF endpoint. Their SQL procedures and consent enforcement were not changed.
- Legal administration now has protected APIs for listing/detail, private preview, PDF draft upload, metadata/scope edit, submit, approve/reject, publish, and archive.
- Authorization uses the authenticated JWT `sub` and `sid`, validates the active verified session, and then checks effective permissions on an existing `PLATFORM` role assignment. Tenant membership is not consulted.
- Development was inspected read-only: the v1.6 legal tables and procedures exist, but there are no `leg.LegalDocuments`, version, or scope records. PLATFORM role/permission and assignment structures exist; the existing `SUPER_ADMIN` and `PLATFORM_SUPPORT` roles are reused without creating roles or user assignments.

## 2. Source changes

- Added application contracts and lifecycle service validation.
- Added PLATFORM permission authorization and Dapper calls to stored procedures.
- Added private filesystem PDF storage with PDF signature, size, SHA-256, path, and stored-file integrity checks.
- Added protected Minimal API endpoints and exception mappings. The route group is disabled unless `PlatformLegalDocuments:AdministrationEnabled=true`.
- Connected the existing Platform Setup → Legal Documents page to permissions, list/detail, upload, update, preview, submit, approve/reject, publish, and archive.
- Added OpenAPI contracts, a versioned v1.7 SQL delta, a runtime EXECUTE-grant template, and focused route/permission/UI tests.
- No authentication, Register, email-verification, tenant-creation, or unrelated Platform Setup flow was modified.

## 3. API payload verification

Draft upload is multipart form data containing `title`, `versionIdentifier`, UTC `effectiveAtUtc`, one or both repeated `registrationTypes` values (`PERSONAL`, `ORGANIZATION`), an optional existing `legalDocumentId` for a new version, and one `file` PDF. The server calculates the hash and opaque storage reference; clients cannot provide either.

Draft metadata edits use `PUT /api/v1/platform/legal-documents/versions/{documentVersionId}` with `title`, `versionIdentifier`, `effectiveAtUtc`, `registrationTypes`, and the actual Base64 `rowVersion`. Approval uses `{"decisionCode":"APPROVED"|"REJECTED","decisionNote":null}`. No registration scope or version ID is fabricated.

## 4. Terms and private storage status

- The same version can be assigned both registration scopes; the existing public read procedures remain the source of consent-eligible published versions.
- The PDF at `klop-next_ui/docs/KLOP_Next_Terms_and_Conditions.pdf` was previously verified to exist and be readable (81,536 bytes; SHA-256 `1EE4125215D5C3CAC5F80935105B9643709E72BDBF6DFCEC527CDA34607F6F47`). It was not uploaded or registered.
- `LegalDocuments:StorageRoot` is not configured in the Development settings. Set it to a private, non-webroot directory before enabling upload.
- No document was approved or published. The existing Register consent checks remain unchanged.

## 5. Build and tests

- Backend: isolated `dotnet build klop-next-platform-api/KLOP.Platform.sln --no-restore` — pass, 0 warnings/errors. `dotnet test klop-next-platform-api/tests/KLOP.Platform.UnitTests/KLOP.Platform.UnitTests.csproj --no-restore` — pass, 111 tests. Isolated output avoids the normal API output lock held by a running Visual Studio/API process.
- Frontend: `npm run typecheck` — pass; `npm run build` — pass (existing non-blocking Rollup annotation warnings from Zod); `npm test` — pass, 72 tests; OpenAPI TS generation — pass.
- Focused tests cover active-session/platform permission handling, default-off route mapping, route contracts, draft upload payload/scopes, and PDF signature, storage integrity, and hash mismatch validation. No database-writing integration tests were run.
- No SQL script, runtime grant, Development data mutation, automated registration, or test database was run/created.

## 6. Remaining blockers before Development use

1. Review and explicitly approve `database/migrations/v1.7/001_platform_legal_documents.sql`. It adds PENDING_APPROVAL, submitter metadata, append-only approval decisions, permission definitions/role links, audit actions, workflow procedures, and lifecycle guards.
2. Explicitly approve the proposed permission links: existing PLATFORM `SUPER_ADMIN` receives the complete capability set; `PLATFORM_SUPPORT` receives read/create/edit/preview only. No roles or user assignments are created. Confirm this is the intended policy before applying.
3. Review and apply the separate v1.7 runtime EXECUTE-grant template after the migration and runtime identity/ownership-chain checks pass.
4. Configure `LegalDocuments:StorageRoot` as private storage, deploy the backend, then explicitly enable `PlatformLegalDocuments:AdministrationEnabled`.
5. Decide whether policy requires submitter/approver separation-of-duties; no such restriction was inferred or added.
6. Development full-stack validation and any Terms publication remain manual approval activities. Current Terms metadata is absent for both scopes, so Register remains safely subject to its existing backend consent requirement.

## 7. Manual Development verification

1. Review the v1.7 SQL delta, permission-role mapping, runtime grants, and storage/configuration policy with the database/security owner.
2. After approval, apply the migration and grants manually to Development, configure the private storage root, and only then enable the feature flag.
3. Sign in as an authorized PLATFORM principal. Verify each permitted operation and confirm unauthorized principals receive 403; confirm PLATFORM Support cannot submit, approve, publish, or archive by default.
4. Upload the existing PDF once with both scopes; verify private preview and metadata/hash/size integrity.
5. Exercise DRAFT edit → submit → approve/reject → publish → archive with approved test data and verify audit actor/action/correlation entries.
6. Confirm `GET /api/v1/public/legal/terms/current` resolves the actual published version for both registration types, then manually validate Register and Email Verification without automated Development registration.
