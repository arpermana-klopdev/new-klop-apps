# KLOP Admin Portal

React, TypeScript (strict), Vite, Tailwind, React Router, Axios, TanStack Query, React Hook Form, Zod, Radix UI, and Vitest frontend for the existing KLOP Platform API.

## Run locally

```powershell
npm install
Copy-Item .env.example .env
# Set VITE_API_BASE_URL to the backend API base URL in .env
npm run dev
```

The checked-in Development API URL is `https://localhost:7041/api/v1`. The backend reads its exact allowed SPA origin from SQL (`web.allowed_origin`); this Development database is configured for `https://localhost:5173`. Vite is HTTP by default, so export and trust a local ASP.NET Core development certificate before starting Vite with HTTPS:

To stop an existing Vite process for this project on port 5173, prepare the local certificate, and start the UI over HTTPS in one step, run:

```powershell
.\start-ui.ps1
```

The script will not stop an unrelated process occupying port 5173.

```powershell
$certDirectory = Join-Path $env:LOCALAPPDATA "KLOP\dev-certs"
New-Item -ItemType Directory -Force -Path $certDirectory | Out-Null
dotnet dev-certs https --trust
dotnet dev-certs https --export-path (Join-Path $certDirectory "localhost.pem") --format PEM --no-password
$env:KLOP_DEV_TLS_CERT_PATH = Join-Path $certDirectory "localhost.pem"
$env:KLOP_DEV_TLS_KEY_PATH = Join-Path $certDirectory "localhost.key"
npm run dev -- --host localhost --port 5173
```

The certificate path variables are consumed only by the Vite Node configuration and do not use the `VITE_` prefix. Do not copy private keys into the workspace or browser environment. The backend must allow the exact portal origin and support credentialed CORS for refresh cookies. Its refresh cookie is `HttpOnly`, `Secure`, and `SameSite=Strict`; access tokens remain in memory and are never written to browser storage.

## Implemented API-backed areas

- Login, registration, email verification, and resend verification.
- Current-account profile display and logout.
- Current-user tenant overview, tenant creation, organization-type lookup, and invitation of an existing user by ID.
- Accept invitation; assign/revoke tenant role; remove tenant member. The backend enforces tenant permissions.
- Light/dark appearance preference.
- Loading, retry, empty, API error, validation, and server permission-denied messaging.

See [the API dependency report](docs/API_DEPENDENCIES.md) for the exact route support and backend gaps. Unsupported modules are explicitly unavailable; no fabricated API data or business catalogs are used.

## Commands

```powershell
npm run api:types
npm run build
npm run test
npm run test:e2e
```

The committed `openapi.yaml` is generated from the backend's Development `/openapi/v1.json`, including its `/api/v1` paths and response/error definitions. Axios calls use relative paths against the `/api/v1` base URL. Regenerate `src/api/schema.d.ts` after an approved API contract change and review the resulting contract diff.

## Validation status

The portal has passed a live Development API smoke check for health/readiness, OpenAPI, and SQL-backed organization-type reads. Browser-to-API integration remains blocked by the current HTTP Vite origin not matching the SQL-configured HTTPS CORS origin; authentication/session workflows are also blocked by nine missing SQL procedures. The Playwright auth check stubs only the login response to verify error handling and does not prove successful authentication. See [the full-stack integration validation report](docs/INTEGRATION_VALIDATION.md). Do not treat this frontend as production-ready until real API, cookie/CORS, authorization, and supported workflow tests pass in an approved environment.
