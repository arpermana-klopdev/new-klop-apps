# KLOP Platform Development Integration Validation — Superseded Baseline

> This is a historical validation snapshot. Its API/database and browser-run status has been superseded by the current [integration report](./INTEGRATION_REPORT.md); do not use the historical blockers below as current runtime evidence.

**Validation date:** 2026-11-21  
**Overall status:** **BLOCKED** for complete authentication and business-workflow integration. This is not a Production-readiness or FROZEN approval.

## Result summary

| Area | Result | Evidence / limitation |
|---|---|---|
| Backend restore | PASS | `dotnet restore KLOP.Platform.sln` succeeded. |
| Backend Release build | PASS | Release build succeeded with 0 warnings and 0 errors. |
| Backend unit tests | PASS | 17 passed. |
| Backend SQL integration tests | BLOCKED | 3 database tests were skipped; no explicitly approved, isolated database ending in `_TEST` was configured. |
| Frontend dependency install | PASS | `npm ci --no-audit` restored dependencies from the existing lockfile; no manifest changes. |
| Frontend TypeScript check / production build | PASS | Both passed; Vite emitted two non-fatal Rollup annotation warnings from Zod dependencies. |
| Frontend unit tests | PASS | 5 tests passed in 2 files. |
| Frontend Playwright tests | PASS (mocked denial only) | 1 browser test passed. It stubs a 401 login response and does not prove successful API authentication. |
| Development API basic probes | PASS | Liveness/readiness, Swagger/OpenAPI, JWKS, and SQL-backed organization-type query returned HTTP 200; organization types returned 7 rows. |
| Live API contract | PASS | Live OpenAPI contains 15 `/api/v1` operations; the frontend snapshot is retained and the slashless tenant-create route is covered by a unit test. |
| SQL auth/session dependencies | PASS (catalog/signatures only) | All 20 mapped procedures are present; all 9 auth/session signatures match. No migration was executed by this validation. |
| SQL runtime permissions | BLOCKED | `klop_app_runtime` has no members and 0/9 explicit auth/session EXECUTE grants. The current Integrated Security caller is `db_owner` and `db_ddladmin`. |
| API CORS preflight | PASS (preflight only) | `https://localhost:5173` received matching allow-origin and credentials headers; an unapproved origin received no allow-origin header. |
| Browser-to-API HTTPS session | NOT RUN | The frontend was not served over HTTPS at the configured origin during this run. Vite TLS requires configured certificate paths. |
| Positive login, refresh, logout, protected workflows | BLOCKED | No approved isolated `_TEST` database/runtime identity is available; no successful authentication or protected business workflow was attempted. |
| Production behavior / approval | NOT RUN | Production was not used. The platform is not approved or frozen. |

The API smoke test observed a valid generated correlation ID after an invalid incoming ID, unauthenticated protected-route denials (`401`), invalid-login-payload validation (`400`), refresh denial without an Origin (`403`), and CORS preflight behavior. These denial checks do not prove positive authorization or refresh rotation.

## Frontend module-to-API mapping

| Portal area | Frontend behavior and API mapping | Status |
|---|---|---|
| Login / session restoration | `POST /auth/login`, cookie-based `POST /auth/refresh`, then `GET /auth/me`; access token held in memory. | Source is wired to the real API; successful flow BLOCKED by runtime grants and lack of an approved `_TEST` database. Error UI tested with a stubbed 401. |
| Registration / verification | `POST /auth/register`, `/auth/verify-email`, `/auth/resend-verification`. | Procedures are present; positive flows BLOCKED by runtime grants and write-safety gate. |
| Logout | `POST /auth/logout`; the client clears the in-memory token only after API success. | BLOCKED for success by runtime grants and lack of an approved `_TEST` session. |
| Dashboard | `GET /tenants/mine`; displays API-returned tenants and profile state only. | BLOCKED for authenticated tenant data by runtime grants/test identity gate. |
| Tenant management | `GET /tenants/mine`, `POST /tenants`, `POST /tenants/{tenantId}/invitations`, and `GET /master/organization-types`. | Organization-type read is live-tested; protected reads/writes are BLOCKED by runtime grants and write-safety gate. |
| Membership management | `POST /tenants/memberships/{membershipId}/accept`; uses returned tenant IDs and user-supplied known membership IDs. | BLOCKED for success; no membership-directory endpoint exists. |
| Role actions | `POST`/`DELETE /tenants/{tenantId}/memberships/{membershipId}/roles...`; role code must be known by the operator. | BLOCKED for success; no role or permission catalog endpoint exists. |
| User directory | No supported user list/search/detail/admin API. | BLOCKED / explicitly unavailable in UI. |
| Platform dashboard metrics | No aggregate dashboard endpoint. | BLOCKED / UI is limited to the current user's API-returned tenant count. |
| Master data | Organization types load from the SQL-backed endpoint and feed tenant creation. No generic master-data endpoint exists. | Organization-type read PASS; generic module unavailable. |
| Configuration | No configuration read/write API; appearance preference is local UI state only. | Backend configuration management unavailable. |
| Audit / security logs | No query endpoints are published. | BLOCKED / explicitly unavailable in UI. |

The current Development API publishes 15 operations. The 9 authenticated API operations return `401` without a bearer token; this validates denial only. Tenant, membership, role, and cross-tenant authorization success were not exercised. The backend's tenant authorization is authoritative; the UI does not grant or infer permissions.

All application pages are behind an authentication route guard. Per-permission navigation filtering is BLOCKED because the API does not expose a permission-discovery endpoint; the backend remains responsible for authorization and `403` responses.

## Contract and security findings

- The frontend snapshot's tenant-create path had a trailing slash while live OpenAPI publishes `/api/v1/tenants`. Both URL forms were routed by the current API, but the client and snapshot are now aligned to the canonical path and a focused regression test covers it.
- The live OpenAPI marks tenant-summary values and 64-bit identifiers as optional/string-or-number. The UI now tolerates omitted display fields, disables tenant actions when an identifier is absent, and preserves IDs as strings where users select or enter them.
- The backend reads `web.allowed_origin` from SQL and requires `https://localhost:5173`. A live API preflight accepted that origin and rejected an unapproved origin. Vite serves HTTP unless both `KLOP_DEV_TLS_KEY_PATH` and `KLOP_DEV_TLS_CERT_PATH` point to a local development certificate; those variables were unset during this validation, so browser-to-API CORS/session success remains NOT RUN.
- Access tokens are stored in JavaScript memory. Refresh tokens are `HttpOnly`, `Secure`, `SameSite=Strict` cookies with credentialed requests. The browser's `localStorage` use is only the appearance preference, not authentication.
- Backend configuration keeps business settings in SQL and retrieves referenced secrets from Azure Key Vault. No secret values were copied to Vite variables or this report.
- Backend structured request logging and correlation enrichment are configured. The live response correlation header was observed, including safe fallback for malformed input. No password/token was sent to the live API; sensitive-log scanning and stored-procedure audit behavior were not exercised.
- SQL metadata shows all 20 mapped procedures and matching auth/session signatures, but `klop_app_runtime` is empty and its nine explicit auth/session grants fail. The API's current Integrated Security identity is in `db_owner` and `db_ddladmin`; effective access under that elevated caller is not least-privilege evidence.
- No fake API success responses were added. Unavailable modules remain explicitly unavailable.

## SQL dependency status and remediation

The following objects were absent from the Development SQL catalog:

1. `iam.usp_GetLocalLoginCandidate`
2. `iam.usp_RecordLocalLoginFailure`
3. `iam.usp_IssueEmailVerificationChallenge`
4. `iam.usp_CreateAuthSession`
5. `iam.usp_ValidateSessionAccess`
6. `iam.usp_RotateRefreshToken`
7. `iam.usp_RevokeAuthSession`
8. `iam.usp_GetUserProfile`
9. `ten.usp_ListMyTenants`

Do not run a migration automatically. Have the database owner review the baseline and the draft [v1.5 migration proposal](../../klop-next-platform-api/database/migrations/v1.5/001_auth_session_procedures.sql), approve it through the normal change process, and deploy only to an approved isolated Development database. Then re-run the read-only catalog/signature checks, validate effective `EXECUTE` grants and SQL-backed configuration, and run mutation integration tests only against a disposable database named with the `_TEST` suffix and explicit mutation opt-in. Repeat the browser flow after the Vite server is started on the configured HTTPS origin. Also stop the currently running Vite process before running `npm ci` in the active frontend workspace; the attempted install there failed on its locked esbuild executable.

See [API dependencies](API_DEPENDENCIES.md) and the backend [database dependency evidence](../../klop-next-platform-api/docs/DATABASE_DEPENDENCIES.md) for the full endpoint and procedure mapping.
