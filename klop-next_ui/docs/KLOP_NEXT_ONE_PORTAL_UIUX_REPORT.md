# KLOP Next – One Portal UI/UX Report

## 1. Existing UI assessment

- The frontend is React 19, TypeScript (strict), Vite, Tailwind, React Router, TanStack Query, Axios, and Lucide.
- Authenticated routes already share `AppShell`; authentication refresh, login, logout, and the in-memory access-token flow are handled separately by `AuthContext` and the API client.
- The previous shell used a generated command icon instead of the KLOP mark, described the main context as “Workspace”, and showed unsupported Platform Admin links with lock icons.
- The dashboard correctly queried the signed-in user's tenant memberships, but put email verification and a “Secure session” summary beside the count and did not clearly separate account memberships from platform-wide data.
- The current `Profile` API shape contains user ID, email, display name, and email verification timestamp only. It does not expose roles, tenant context, or effective permissions.
- Available source assets include the official `docs/KLOP One Portal NEXT Logo.png`, a legacy JPEG logo, a glossy wordmark, a neon hexagon logo, and the existing enterprise ecosystem SVG. No authenticated Platform screenshot was supplied.

## 2. Design principles

- Treat the authenticated shell as an account-level experience until the API supplies a verified active role/context.
- Do not infer platform or tenant privileges from a profile, tenant count, route, or client-side fixture.
- Clearly distinguish feature availability from authorization; use “Coming soon” for missing API-backed modules and reserve permission-denied messaging for actual backend responses.
- Use only API-returned tenant/profile information; never represent a tenant membership count as a platform tenant total.
- Keep login/session behavior, API routes, and backend contracts unchanged.

## 3. Global branding configuration

`src/app/brand.ts` centralizes the application name, tagline, display name, backend name, and exact official logo reference at `docs/KLOP One Portal NEXT Logo.png`. The App Shell, sign-in identity, reusable logo, favicon, page title, dashboard, and footer use this configuration. The original 2149 × 732 aspect ratio is retained. `KLOP PLATFORM` remains the backend identity.

## 4. Existing icon and asset inventory

- `docs/KLOP One Portal NEXT Logo.png` — official logo used by the shared shell, sign-in page, reusable `AppLogo`, and favicon.
- `src/assets/brand/logo.jpeg` — legacy logo retained but no longer used as the official mark.
- `docs/Glossy KLOP Next Portal Logo.png` — existing sign-in wordmark.
- `docs/KLOP NEXT Neon Hexagon Logo.png` — existing standalone brand mark.
- `docs/KLOP Next Enterprise Sign-In.png` — existing sign-in screen reference image.
- `docs/klop-next-enterprise-ecosystem-animated.svg` — existing sign-in illustration.
- Existing Lucide icons are mapped centrally in `src/app/modules.ts`; no icon library or generated brand mark was added.
- No separate favicon file exists; the official logo is reused without altering its artwork.

## 5. Final App Shell structure

One shared authenticated shell now owns a dedicated Platform Administration sidebar (Overview, Registrations, Tenants, User Directory, Master Data, Configuration, Audit Logs, Security Logs), topbar, content outlet, profile menu, theme toggle, mobile navigation drawer, and footer. My Profile, Account Settings, Notifications, and Logout are kept in the profile dropdown. Tenant Members & Roles is linked from the tenant-management view, not the global Platform menu. Sidebar visibility is not an authorization control.

## 6. User persona matrix

| UI persona/context | Source needed before personalization | Current behavior |
|---|---|---|
| `SUPER_ADMIN` / `PLATFORM_SUPPORT` | Effective platform role/context from an approved API contract | Not inferred. Platform modules are marked “Coming soon” until their APIs exist. |
| `PERSONAL` tenant | API-returned tenant type and membership | Listed under Personal overview when a matching tenant is returned. |
| `ORGANIZATION` tenant | API-returned tenant type and membership | Listed under Organization overview when a matching tenant is returned. |
| Tenant `OWNER`, `ADMIN`, or `MEMBER` | Effective tenant role/capability data from the backend | Not inferred. Existing mutation APIs remain authoritative and can return a permission error. |
| User with no tenant membership | A valid empty `/tenants/mine` response | Displayed as an empty account membership state; no tenant is created automatically. |

These are UI contexts/personas, not client-side authorization rules.

## 7. Platform and tenant context design

The authenticated Platform layout is presentation only; the existing API does not provide effective roles or a platform-wide tenant directory. The overview keeps the current account's tenant memberships separate from platform modules and does not infer a platform total or require tenant creation. The existing tenant view continues to show account-scoped tenants. No workspace switching was enabled.

## 8. Navigation and module registry

`src/app/modules.ts` defines unique IDs, display labels, routes, icon references, applicable contexts, optional capability identifiers, availability, group, order, and descriptions. It includes a Registration Center and separate PERSONAL and ORGANIZATION registration routes. No capability identifier is populated because none is supplied by the backend. Unavailable routes show feature status and never act as authorization enforcement.

## 9. Platform overview redesign

The Platform overview emphasizes module navigation while showing only the authenticated account's API-backed tenant memberships. Platform-wide totals and effective role information are explicitly reported as unavailable. Registration Center links to the two requested registration views; user directory, master data, configuration, audit, and security modules remain clearly unavailable. No platform KPIs or fabricated registration rows are shown.

## 10. PERSONAL dashboard design

Returned `PERSONAL` tenant memberships appear in a reusable Personal overview section with only the tenant name/code/type/status and membership status available in the API. Account/profile settings remain available. No tenant is created automatically.

## 11. ORGANIZATION dashboard design

Returned `ORGANIZATION` tenant memberships appear in an Organization overview section. Existing Members & roles operations remain available through their existing page and API calls, with server authorization unchanged. The UI does not fabricate member lists, organization details, or role catalogs.

## 12. UI state handling

- **AVAILABLE:** current supported routes and existing API-backed operations.
- **ACCESS_DENIED:** only surfaced from backend permission-denied responses; no frontend permission simulator is present.
- **COMING_SOON:** unsupported modules use a neutral availability badge, not a lock icon.
- **LOADING:** dashboard membership count and cards use skeletons.
- **ERROR:** query failures show the API error and retry action, not an empty-state fallback.
- **EMPTY:** only a successful empty membership response is displayed as no memberships.
- **Session expired:** existing unauthorized event continues to clear the profile and redirect to sign-in; refresh handling is unchanged.

## 13. Responsive design

The existing desktop sidebar remains fixed; smaller layouts use a labeled drawer. Header controls are constrained to avoid overflow, profile details wrap/truncate safely, dashboard cards use responsive grids, and tenant tables retain their existing narrow-screen card presentation.

## 14. Changed frontend files

- `src/app/brand.ts`, `src/app/modules.ts`
- `src/app/App.tsx`, `src/main.tsx`
- `src/components/AppShell.tsx`, `src/components/AppLogo.tsx`
- `src/features/dashboard/DashboardPage.tsx`
- `src/features/unavailable/UnavailablePage.tsx`
- `src/features/registrations/*`
- `src/features/auth/LoginPage.tsx`, `src/layouts/AuthLayout.tsx`
- `src/features/tenants/TenantsPage.tsx`, `src/features/members/MembersPage.tsx`
- `src/api/client.ts` (backend service identity in safe error copy only)
- `index.html`
- `tests/AppShell.test.tsx`, `tests/DashboardPage.test.tsx`, `tests/modules.test.ts`, `tests/RegistrationPages.test.tsx`
- `tests/api-client.test.ts`, `e2e/auth.spec.ts` (brand/error assertions)
- `docs/API_DEPENDENCIES.md` (registration contract proposal)

No backend source, API route/response contract, SQL, database baseline, JWT/session implementation, or authentication implementation was changed.

## 15. Before/after screenshots

No latest Platform screenshot was attached. The prior browser page was the sign-in route, not a Platform view. No authenticated browser session was available for a genuine post-login screenshot; review of the protected shell requires an approved signed-in session.

## 16. Frontend build and test results

- `npm run build` — passed; includes `tsc -b` typecheck and Vite production build.
- `npm run test` — passed: 7 test files, 37 tests.
- `npm run test:e2e` — passed: 4 Chromium tests, including mobile login layout, safe login-error behavior, registration form selection, and the mocked registration/verification flow.
- Vitest and Playwright use two workers to keep the auth page and existing dashboard query tests stable under concurrent execution.
- `npm run lint` — not run; no lint script is defined in `package.json`.
- No database mutation was run.

## 17. Backend unchanged confirmation

All implementation and tests are confined to the frontend project. No backend repository, API contract, SQL/database, or frozen baseline was edited; no database mutation was run.

## 18. Missing backend API contracts for future integration

1. Effective platform and tenant roles/capabilities, including active context if applicable.
2. Platform-wide tenant/operational overview aggregates and a platform-scoped tenant directory.
3. PERSONAL/ORGANIZATION registration list, detail, search/filter, state, and timeline endpoints.
4. Post-verification personal identity/profile completion contract.
5. Organization registration intake/review, owner detail, and document-requirement catalog.
6. User directory and user administration.
7. Tenant member, invitation, role, and permission discovery/catalog endpoints.
8. Generic master-data discovery and configuration read/write endpoints.
9. Audit and security event query endpoints.
10. Notification delivery/history.
11. Profile editing and password-reset flows.

These are proposals only; no endpoint was added or assumed in this task.

## 19. Remaining UI/UX risks

- Role-aware navigation cannot be personalized until an effective-permissions contract exists; current visible routes are not security controls.
- Registration queues, post-verification personal identity, organization review/documents, platform-wide summary data, and user/member directories remain unavailable until contracts are published.
- PERSONAL/ORGANIZATION sections depend on the tenant type strings returned by the existing API; unknown types remain grouped as “Other tenant types”.
- A live authenticated visual review and positive backend session/permission flow remain dependent on an approved development account and the existing integration environment.

## Platform registration follow-up

The Registration Center separates PERSONAL and ORGANIZATION registration routes from Tenant Management and the global User Directory. `PERSONAL` registration is explicitly user-account onboarding; it does not create a `PERSONAL` Tenant. The existing public self-registration still uses Full Name (mapped to the existing `displayName` contract), Email, and Password.

The two registration views provide reusable queue/search/filter/table states but production queue controls remain disabled because no administrative registration list/detail contract exists. PERSONAL detail fields (user/email verification/profile completion/timeline) and ORGANIZATION detail fields (owner, verification, documents, review state, timeline) are honestly marked unavailable. The ORGANIZATION page reads organization types from the existing API and has no hardcoded type or legal-document lists. A read-only identity-form scaffold accepts future field definitions but has no active field schema or submit action.

Tenant member links now navigate into `/tenants/{tenantId}/members`; the global Platform sidebar no longer includes Members & roles. The existing member API calls and backend authorization behavior are unchanged. See `docs/API_DEPENDENCIES.md` for the registration API contract proposal.

The public registration flow was subsequently expanded to select PERSONAL or ORGANIZATION as a non-persistent onboarding choice, collect Full Name/Email/Password/Confirm Password, reuse the existing registration and email-verification contracts, and show a non-persistent onboarding preview. Google/SSO display options were removed from Login without changing authentication infrastructure. See [KLOP_NEXT_REGISTRATION_UI_IMPLEMENTATION_REPORT.md](./KLOP_NEXT_REGISTRATION_UI_IMPLEMENTATION_REPORT.md) for the current implementation and validation details.
