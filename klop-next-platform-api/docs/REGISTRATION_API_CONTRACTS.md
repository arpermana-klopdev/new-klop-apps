# Registration and Onboarding API Contracts

**Status:** Implemented in API source. Read-only Development verification on 2026-11-23 found a partial v1.6 deployment: the Terms read procedures and legal immutability triggers are missing, the runtime role has no members/incomplete grants, no Terms version is published, and onboarding submission remains policy-disabled. SQL-dependent registration/onboarding use is **BLOCKED** pending repair and DBA approval.  
**Production status:** BLOCKED.  
All successful JSON responses use the existing `{ success, data, error, meta }` envelope. Errors use the existing RFC 9457 Problem Details response with `success`, `error`, and `meta` extensions. `meta.requestId` is the correlated request identifier.

## Authentication registration

### `POST /api/v1/auth/register`

Anonymous, existing auth rate limit, HTTP 202 response retained. Existing `POST /auth/register` remains the same entry point.

New request fields are backward-compatible at the JSON contract level. The database policy controls whether legacy registration without an intent is still accepted; when legal consent enforcement is enabled, SQL rejects missing registration type/consent. A complete new registration request is:

```json
{
  "fullName": "Budi Santoso",
  "email": "budi@example.com",
  "password": "<user-entered-password>",
  "registrationType": "ORGANIZATION",
  "termsDocumentVersionId": "<published-version-guid>",
  "termsAccepted": true
}
```

`fullName` is canonical; legacy `displayName` remains accepted when `fullName` is absent. If both appear, `fullName` is used. `registrationType` is case-insensitively validated against `PERSONAL` or `ORGANIZATION`, then normalized to the stable database master code. When the type is present, a non-empty GUID and `termsAccepted: true` are mandatory. The API does not accept a client timestamp/hash. Confirm Password is frontend-only and must not be sent. Password hashing, verification challenge generation/hashing, expiry, email sending, and generic duplicate handling remain the existing implementation.

The new Stored Procedure contract validates the current published/effective version and scope, and atomically commits user, credential, email challenge, application, consent, and audit records. It creates no Tenant or role. Duplicate email still returns the same generic 202 acceptance response. SMTP failure after database commit remains an operational warning and recoverable through resend-verification.

Success data remains generic:

```json
{"message":"If accepted, verification instructions will be emailed."}
```

New relevant errors: `400 VALIDATION_FAILED` (incomplete/invalid fields), `400 REGISTRATION_CONSENT_REQUIRED` (enforcement enabled but absent), `403 REGISTRATION_DISABLED`, `409 TERMS_VERSION_OUTDATED` (re-fetch and display current Terms), `409 CONFLICT`, `429 RATE_LIMITED`, `503 FEATURE_UNAVAILABLE` (v1.6 SQL prerequisites not deployed). Error bodies do not distinguish duplicate addresses.

## Public Terms API

### `GET /api/v1/public/legal/terms/current?registrationType=PERSONAL|ORGANIZATION`

Anonymous. Returns only the latest published, effective version with an explicit configured scope. One shared version may return for either type when both scopes exist. No matching version returns `404 TERMS_UNAVAILABLE`. An unavailable SQL dependency returns 503.

Response `data`:

```json
{
  "documentVersionId": "<guid>",
  "title": "Terms and Conditions",
  "registrationType": "PERSONAL",
  "version": "<version-label>",
  "effectiveAtUtc": "<UTC timestamp>",
  "documentUrl": "/api/v1/public/legal/terms/<guid>/file",
  "contentHash": "<lowercase-sha256-hex>",
  "publicationStatus": "PUBLISHED"
}
```

The current-metadata response uses an SHA-256 ETag and short-lived `public, max-age=60, must-revalidate` caching so clients can detect a replacement version.

### `GET /api/v1/public/legal/terms/{documentVersionId}/file`

Anonymous. Returns the official `application/pdf`, only for a published/effective version with a configured scope. Uses the stored reference (never returned in metadata), verifies the PDF signature, byte length, and SHA-256 against the immutable database record, and returns a content-hash ETag with long-lived immutable caching. Storage absence, file absence, malformed metadata, or integrity failure returns `503 LEGAL_DOCUMENT_UNAVAILABLE`. Arbitrary paths are not accepted. The document storage root is host configuration (`LegalDocuments:StorageRoot`), must be absolute and outside `wwwroot`; no local frontend path is used.

## Onboarding APIs

All routes below require a bearer JWT whose session is revalidated by SQL. The existing session procedure requires an active user and verified email. The authenticated subject is the only user ID accepted; caller-supplied user IDs are not part of the DTOs.

### `GET /api/v1/onboarding/me`

Returns the current user's active application, or `404 ONBOARDING_NOT_FOUND` for an existing/legacy user without an application. No legacy user is automatically classified.

### `GET /api/v1/onboarding/{applicationId}`

Returns only an application owned by the authenticated user. Another user's ID and a nonexistent ID both return 404.

Response data:

```json
{
  "applicationId": 123,
  "registrationType": "PERSONAL",
  "onboardingStatus": "DRAFT",
  "createdAtUtc": "<UTC timestamp>",
  "updatedAtUtc": "<UTC timestamp>",
  "completedAtUtc": null,
  "tenantId": null,
  "rowVersion": "<base64-encoded-8-byte-rowversion>"
}
```

### `PUT /api/v1/onboarding/personal/draft`

```json
{
  "rowVersion": "<base64-encoded-8-byte-rowversion>",
  "phoneNumber": null,
  "countryCode": null,
  "region": null,
  "city": null,
  "postalCode": null,
  "addressLine": null
}
```

All profile fields are optional while product requirements are pending. It does not collect NIK/KTP and does not create a Tenant. The request must carry the latest rowversion. Stale non-identical writes return `409 CONFLICT`; exact retries are idempotent.

### `PUT /api/v1/onboarding/organization/draft`

```json
{
  "rowVersion": "<base64-encoded-8-byte-rowversion>",
  "organizationTypeId": null,
  "countryCode": null,
  "registeredName": null,
  "contactEmail": null,
  "contactPhone": null,
  "region": null,
  "city": null,
  "postalCode": null,
  "addressLine": null
}
```

Organization type IDs are database master IDs and are never hardcoded. Draft fields are optional pending approved validation rules; organization type/country consistency is checked against SQL master data when provided. No supporting files or sensitive identity numbers are accepted by this endpoint.

### `GET /api/v1/onboarding/organization/requirements`

Returns the current user's effective, database-driven organization requirements, preserving group selection mode, minimum count, country, organization type, active state, and effective dates. An empty applicable rule set is treated as unavailable (`503 ORGANIZATION_REQUIREMENTS_UNAVAILABLE`), not as proof that no documentation is required. The current Development catalog has zero requirement groups/requirements.

### `POST /api/v1/onboarding/submit`

```json
{"rowVersion":"<base64-encoded-8-byte-rowversion>"}
```

Route is implemented but the v1.6 database seed leaves both submission policies disabled. It returns `503 ONBOARDING_POLICY_PENDING` until approved business validation rules and safe policy are implemented/approved. No Tenant is created by saving a draft or submitting. A repeated already-submitted request is idempotent.

Application status and email verification are separate. Registration type has no self-service change endpoint and is not changed by a repeated registration request; duplicate email continues to receive the generic HTTP 202 response and creates no second active initial application. An intent correction requires a future authorized recovery/support process, which is not implemented. Abandoned DRAFT records remain private/current; no automatic deletion/expiry is implemented.

## Routes deliberately not exposed

The following administrative routes are **BLOCKED** and are not mapped: `/api/v1/platform/registrations*`, `/api/v1/platform/legal-documents*`, document upload, approve/publish/archive, review, and Tenant completion. The current backend has no PLATFORM-scoped effective permission contract, restricted Support policy, approved legal document publication policy, or safe verified-Organization activation policy. Frontend visibility is not used as authorization.

## Frontend integration mapping

1. Fetch current Terms by selected type and open the returned `documentUrl` in the modal.
2. Store the returned `documentVersionId` in the active registration form state; do not use local/session storage as durable onboarding state.
3. Send `registrationType`, that exact version ID, and `termsAccepted: true` with the existing registration fields. Do not send confirmation password or client acceptance time/hash.
4. On `TERMS_VERSION_OUTDATED`, re-fetch and explicitly present the newly current version; require a fresh user acceptance.
5. Keep existing verify-email, resend, login, refresh, logout, and `/auth/me` flows unchanged.
6. After verified login, call `/onboarding/me`; use the returned `rowVersion` for draft updates.
7. Do not treat submission response as Tenant activation. Tenant completion and admin review are not enabled.
