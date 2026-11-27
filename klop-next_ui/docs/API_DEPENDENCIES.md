# API dependency report

This report is based on the backend at `D:\PROJECT\Smart\klop\klop-next-platform-api`, including its live Development `/openapi/v1.json`, route handlers, application contracts, and response/domain models. The frontend `openapi.yaml` was refreshed directly from the live document; it exposes 15 `/api/v1` operations. Runtime Axios paths remain relative to its `/api/v1` base URL.

## API-backed portal features

| Portal feature | Backend operation(s) | UI behavior and dependency |
|---|---|---|
| Sign in / session restoration | `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`, `GET /api/v1/auth/me` | Access token only in memory; refresh token remains an HttpOnly backend cookie. |
| Sign out | `POST /api/v1/auth/logout` | Revokes the current server session before clearing the in-memory token. |
| Registration / verification | `POST /api/v1/auth/register`, `/resend-verification`, `/verify-email` | Registration and resend use non-disclosing API messages; verification requires user ID and emailed code. |
| Tenant overview | `GET /api/v1/tenants/mine` | Shows only the current user's API-returned tenants and statuses. |
| Tenant creation | `POST /api/v1/tenants` | Tenant type code remains user-entered because there is no tenant-type catalog endpoint. The server validates type and registration configuration. |
| Organization type lookup | `GET /api/v1/master/organization-types` | Options are loaded from the API; no organization catalog is hardcoded. |
| Invite existing user | `POST /api/v1/tenants/{tenantId}/invitations` | Requires a known numeric user ID; no user lookup endpoint is available. |
| Accept invitation | `POST /api/v1/tenants/memberships/{membershipId}/accept` | Requires a membership ID; there is no pending-invitation listing endpoint. |
| Membership / role actions | `DELETE /api/v1/tenants/{tenantId}/memberships/{membershipId}`, role POST/DELETE routes | Requires known IDs and role code. Server permission checks remain authoritative; 403 responses are surfaced. |

## Unavailable dependencies

| Requested module | Missing API support |
|---|---|
| Platform-wide dashboard / tenant operational metrics | No aggregate dashboard or platform summary endpoint. UI only reports the authenticated user's returned tenant count and profile verification state. |
| User directory, details, status administration | No user search/list/detail/status endpoints. |
| Tenant member directory and membership discovery | No tenant member list or pending invitation list. |
| Role catalog, permission catalog, permission editing | No roles/permissions discovery or permission mutation endpoints. |
| Dynamic master-data interfaces | Only organization types are exposed; no generic master-data discovery endpoint. |
| Configuration listing/editing | No configuration read/write endpoints for the portal. |
| Audit/security events | No audit or security log query endpoints. |
| Password reset | No password reset request/confirmation endpoints. |
| Profile editing | Current profile is read-only; no profile mutation endpoint. |
| Localization catalog | No localization resource endpoint; the portal currently provides English UI only. |

The production frontend source uses the real API client; no mock authentication bypass is enabled. Browser-to-API CORS was verified from `https://localhost:5173`; the Playwright login-error test installs a test-only route stub for an HTTP 401 and does not provide successful authentication. Missing modules display explicit unavailable states rather than fabricated data or client-side security decisions. See the [current integration run](./INTEGRATION_REPORT.md) for runtime URLs, results, and remaining blockers.

## Integration requirements

1. Reconcile the checked-in snapshot with the live document after every backend contract change. The live document has no trailing slash on the tenant-creation route; keep the frontend request slashless.
2. Provide a least-privilege API identity and an explicitly approved isolated `_TEST` database with disposable test users and tenants for login, refresh-cookie, registration/verification, tenant creation, membership, and authorization workflows. The current Development Integrated Security caller is elevated and is not suitable for this validation.
3. Configure the exact backend `AllowedOrigin` to match the portal origin. The configured `https://localhost:5173` passed an exact-origin API preflight and a credentialed browser read; the trusted local development certificate was verified. The refresh request was denied with 401 because no session cookie was present, so positive `SameSite=Strict` refresh-cookie behavior remains unverified.
4. To implement the unavailable modules, publish and authorize the corresponding backend endpoints and contracts. Do not work around the absence in the browser.

## Platform registration UI follow-up

The current frontend provides public self-registration through `POST /api/v1/auth/register` with `displayName`, `email`, and `password`, plus email verification/resend. `GET /api/v1/auth/me` exposes the signed-in user's `displayName`, `email`, and email verification timestamp only. These endpoints do not provide an administrative registration queue, a post-verification personal identity profile, or registration history. A global user account registration is not the same thing as a `PERSONAL` Tenant. The `POST /api/v1/tenants` operation creates a tenant; it is not a pending registration/review workflow.

The ORGANIZATION page reads organization-type reference data only from the existing `GET /api/v1/master/organization-types` operation. The API does not expose an organization-registration intake, owner detail, verification/review status, document catalog, or document upload requirement. The frontend does not substitute a hardcoded type/document catalog or tenant creation for those missing workflows.

Suggested future contract scope (proposal only; no routes are implemented by this frontend task):

- Authorized, paginated/filterable PERSONAL and ORGANIZATION registration list operations with server-defined status values and search semantics.
- Registration detail operations with applicant/owner identity fields, verification state, profile completion state, current registration state, and associated tenant ID when one exists.
- Registration timeline/history operations with event timestamps and actor/action references.
- ORGANIZATION application data including organization-type ID, owner identity reference, review status, and a document-requirement catalog sourced from master data. Document upload/access rules should be specified separately and remain server-authorized.
- Explicit capability requirements and least-privilege authorization for list, detail, review, and any document operations.

The UI uses a frontend view-model adapter for search/filter/table presentation, but keeps production queue state unavailable until these contracts exist. No fake production registration rows or identity fields are emitted.

## Public account registration intent

The public PERSONAL/ORGANIZATION selector is currently a frontend-only onboarding choice. It remains in React component state for the current registration screen, is not included in the existing `POST /api/v1/auth/register` request, is not persisted across refreshes, and is never used as an authorization signal. The account API continues to receive only `displayName`, `email`, and `password`; the UI-only `confirmPassword` is excluded. A generic HTTP 202 response is presented without echoing the API message or implying that a Tenant, profile, or verified account was created.

Persistent onboarding intent requires a future backend contract. A proposed contract should:

- Accept a stable `PERSONAL` or `ORGANIZATION` intent code alongside a registration operation only after backend owners approve and publish its semantics.
- Validate the intent against server-owned registration/tenant-type configuration; never accept a browser-provided database ID or treat the intent as a role, permission, or Tenant Owner grant.
- Preserve generic, non-enumerating acceptance semantics and associate the intent with a server-owned pending registration record.
- Provide an explicit, authorized post-verification continuation that reads the persisted intent and creates the appropriate Tenant only after required profile/application data is submitted and validated.
- Source Organization Type and document requirements from authorized master-data APIs and define server-side validation, upload, review, and audit behavior.

No request property, endpoint, database object, or persistence behavior for this proposal is implemented by the frontend change.

## Registration Terms & Conditions delivery and consent

The repository contains `docs/KLOP_Next_Terms_and_Conditions.pdf`. Its embedded title/subject and page content identify it as an unapproved draft; the body labels it version 0.1 and leaves the effective date as a placeholder. The exact file is served at `/documents/KLOP_Next_Terms_and_Conditions.pdf` in Vite development for UI review. The draft is excluded from production builds, marked `DRAFT`, and cannot be accepted; account creation remains disabled. The same combined PDF is shown for PERSONAL and ORGANIZATION; this does not imply separately approved documents. `src/features/auth/termsDocuments.ts` preserves the API adapter boundary and does not invent an official document ID or publication status.

The future document-management contract must support:

- Privileged Platform Admin upload of an official document, preferably PDF, with a stable `DocumentId`, `DocumentType`, `RegistrationType`, title, immutable version, effective date, and publication status.
- Authorized publish/withdraw operations and an immutable version history. PERSONAL and ORGANIZATION current documents must be independently retrievable.
- A public or otherwise registration-authorized read operation that returns only the current Published, applicable document and its content or a safely delivered PDF URL. The response must define content type, caching/version semantics, and how the frontend can distinguish loading, unavailable, withdrawn, and failed states.
- Server-side validation at registration that the submitted document ID/version is Published, current, and applicable to the registration intent. A browser-side acceptance flag is not legal evidence.
- A server-recorded consent event associated with the pending registration/user reference, registration type/intent, Terms Document ID, accepted version, and server-generated acceptance timestamp. The event must be immutable and auditable, including the applicable document version and evidence of the explicit action.

This is a proposal only. No route names or request fields are assumed, and the existing `POST /api/v1/auth/register` contract remains unchanged. The backend must approve and publish its document-management and consent-enforcement contracts before frontend loading or production registration enforcement can be enabled.
