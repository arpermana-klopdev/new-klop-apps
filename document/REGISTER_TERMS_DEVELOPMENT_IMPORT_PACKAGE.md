# Development Registration Terms Import Package

**Status:** Prepared for legal and DBA review; not imported or published  
**Environment:** `DEV-PC\SQLEXPRESS` / `KlopPlatformDB`  
**Scope:** One Terms version shared by `PERSONAL` and `ORGANIZATION`

## Verified source artifact

- Source: `klop-next_ui/docs/KLOP_Next_Terms_and_Conditions.pdf`
- Size: `81,536` bytes
- SHA-256: `1EE4125215D5C3CAC5F80935105B9643709E72BDBF6DFCEC527CDA34607F6F47`
- MIME type: `application/pdf`
- Database upload limit: `10,485,760` bytes

The PDF identifies itself as a draft not approved for publication and contains unfilled legal identity, effective-date, and contact placeholders. This package does not change or republish the PDF. Legal review must approve the exact artifact before it can become valid registration consent.

## Development state verified read-only

| Item | Result |
|---|---|
| `leg.LegalDocuments` | 0 rows |
| `leg.LegalDocumentVersions` | 0 rows |
| `leg.LegalDocumentVersionScopes` | 0 rows |
| Active `mst.TenantTypes` | `PERSONAL` (ID 1), `ORGANIZATION` (ID 2) |
| `GET /api/v1/public/legal/terms/current?registrationType=PERSONAL` | `404 TERMS_UNAVAILABLE` |
| `GET /api/v1/public/legal/terms/current?registrationType=ORGANIZATION` | `404 TERMS_UNAVAILABLE` |

The live `leg.usp_GetCurrentTerms` procedure selects only a `PUBLISHED` version effective at the current UTC time with a matching tenant-type scope. `leg.usp_GetPublicTermsFile` applies the same publication, effective-date, and scope requirements. Both procedures exist in Development. The API therefore returns 404 because no document/version/scope records exist; this is not a frontend-generated ID or consent issue.

The API host source `appsettings` files do not define `LegalDocuments:StorageRoot`. The runtime host may inject configuration separately; its value was not exposed or confirmed. Before serving an imported PDF, an operator must verify that the running API has an absolute storage root outside `wwwroot`.

## Import manifest

After approval, register exactly one document and one version, with two scopes:

| Field | Required value |
|---|---|
| Document type | `TERMS_AND_CONDITIONS` |
| Source PDF | The exact artifact and SHA-256 listed above |
| Storage reference | A unique GUID in `N` format; store the file as `<StorageRoot>\<StorageReference>.pdf` |
| Version identifier | To be supplied and approved by the document owner |
| Title | To be supplied and approved by the document owner |
| Effective UTC time | To be supplied by the approver; no date is prefilled |
| Publication state | Start as `DRAFT`; advance only through authorized approval/publication |
| Scopes | `PERSONAL` and `ORGANIZATION`, resolved by their active codes at import time |
| Document version ID | Generate from the database during the authorized insert; do not preassign or reuse an ID |

The file-serving implementation verifies the GUID storage reference, PDF signature, exact byte count, configured maximum size, and SHA-256. A file that fails any check is not served.

## Manual approval and execution steps

1. A legal approver must review and approve the exact PDF bytes. The current file is explicitly marked draft and contains placeholders, so publication is blocked until those issues are resolved and the actual publishable artifact is approved. Do not edit the PDF as part of this package.
2. The API operator must configure and verify a private, absolute `LegalDocuments:StorageRoot` outside the API `wwwroot`.
3. After approval, the DBA should prepare and separately authorize a one-time transaction using the verified table columns. It must create one `TERMS_AND_CONDITIONS` document/version and the two scope rows, use real operator identities and approved metadata, preserve the database-generated version ID, and enforce the approved state transitions.
4. No legal-document write/publish stored procedure or Legal Administration UI was found in the current backend. This package intentionally includes no executable mutation SQL and performs no insert/update. Do not substitute an unreviewed direct update for an approved DBA publication procedure.
5. After the authorized import/publication, verify both current-Terms endpoints return `200` with the same actual `documentVersionId`, verify the file endpoint returns the matching PDF/hash/size, then run frontend tests. Do not create test users or a test database.

## Non-actions

- No SQL mutation, migration, schema change, storage copy, or publication was performed.
- No document version ID, version label, effective date, approver, or publisher was fabricated.
- Register backend validation remains authoritative; draft acknowledgement is not registration consent.

