# Platform Legal Documents API Contracts

Base path: `/api/v1/platform/legal-documents`. All endpoints except the effective-permissions discovery endpoint require Bearer authentication, a valid active session, `platform.legal_documents.read`, and the route-specific capability. Authorization is PLATFORM-scoped; tenant membership is not a substitute.

The route group is not mapped unless `PlatformLegalDocuments:AdministrationEnabled=true`. The application must keep this false until the v1.7 procedures/grants and private storage configuration are approved and deployed.

## Routes

| Method and route | Additional capability | Contract |
| --- | --- | --- |
| `GET /permissions` | Authenticated active session | Returns only this user’s effective legal-document permission codes. |
| `GET /` | `platform.legal_documents.read` | Returns legal document and version history, including scopes and latest approval decision. |
| `GET /{legalDocumentId}` | `platform.legal_documents.read` | Returns one document and its versions; never returns private filesystem paths. |
| `POST /` | `platform.legal_documents.draft.create` | Multipart PDF upload; returns a DRAFT version (201). |
| `PUT /versions/{documentVersionId}` | `platform.legal_documents.draft.edit` | Updates DRAFT title/version/effective time/scopes with row-version concurrency. |
| `GET /versions/{documentVersionId}/preview` | `platform.legal_documents.draft.preview` | Private PDF stream for DRAFT, PENDING_APPROVAL, or APPROVED versions; no-store, range-enabled, ETag set. |
| `POST /versions/{documentVersionId}/submit-for-approval` | `platform.legal_documents.submit` | Revalidates private file integrity and transitions DRAFT → PENDING_APPROVAL. |
| `POST /versions/{documentVersionId}/approve` | `platform.legal_documents.approve` | Body `{"decisionCode":"APPROVED"|"REJECTED","decisionNote":null|string}`; appends an immutable decision. Approval transitions to APPROVED; rejection returns to DRAFT. |
| `POST /versions/{documentVersionId}/publish` | `platform.legal_documents.publish` | Revalidates storage integrity; only APPROVED versions can become PUBLISHED. |
| `POST /versions/{documentVersionId}/archive` | `platform.legal_documents.archive` | Archives a superseded PUBLISHED version; refuses to archive a currently effective version for any included scope. |

## Upload form

`multipart/form-data` fields:

| Field | Type | Constraints |
| --- | --- | --- |
| `legalDocumentId` | UUID, optional | Existing Terms document when creating a replacement version; otherwise a new document is created. |
| `title` | string | Required, 1–300 characters. |
| `versionIdentifier` | string | Required, 1–50 characters; unique within the document. |
| `effectiveAtUtc` | ISO 8601 date-time | Required, UTC offset. |
| `registrationTypes` | repeated enum | One or both of `PERSONAL`, `ORGANIZATION`. |
| `file` | PDF | Exactly one file; server validates MIME, PDF signature, configured size, hash, and storage integrity. |

The server creates the opaque storage reference and SHA-256. These values, document IDs, approval metadata, and consent records cannot be supplied by the UI.

## Draft update JSON

```json
{
  "title": "KLOP Next Terms",
  "versionIdentifier": "2.0",
  "effectiveAtUtc": "2026-01-01T00:00:00Z",
  "registrationTypes": ["PERSONAL", "ORGANIZATION"],
  "rowVersion": "<base64 value returned by the API>"
}
```

Only DRAFT metadata and scope rows are editable. A stale `rowVersion` returns 409. Content replacement creates another version through the upload endpoint.

## Lifecycle and errors

`DRAFT → PENDING_APPROVAL → APPROVED → PUBLISHED → ARCHIVED`. A rejected decision is auditable and returns the version to DRAFT. Published content and scopes are immutable; consent history is unchanged.

Standard responses use the existing API envelope for JSON. Relevant errors: 400 invalid metadata/file, 401 inactive/missing session, 403 missing effective PLATFORM permission, 404 unknown/unavailable version, 409 invalid lifecycle/concurrency/current-version conflict, and 503 storage/configuration/dependency unavailable. Existing public Terms and Register response contracts are unchanged.
