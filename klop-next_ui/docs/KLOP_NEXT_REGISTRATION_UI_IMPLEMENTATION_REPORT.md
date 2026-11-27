# KLOP Next Registration UI Implementation Report

## 1. Existing Login assessment

The existing React/TypeScript auth screen already handled sign-in, self-registration, resend verification, and email verification through React Hook Form, Zod, `AuthContext`, and the shared Axios client. The existing public routes are `/login`, `/register`, and `/verify-email`; the Login form delegates to the existing `signIn` flow.

## 2. Changed frontend files

- `src/features/auth/LoginPage.tsx`
- `src/features/auth/RegistrationFlowContext.tsx`
- `src/features/auth/TermsModal.tsx`
- `src/features/auth/termsDocuments.ts`
- `src/features/auth/login.css`
- `src/components/ui.tsx`
- `src/app/App.tsx`
- `src/layouts/AuthLayout.tsx`
- `tests/LoginPage.test.tsx`
- `e2e/auth.spec.ts`
- `playwright.config.ts`
- `vite.config.ts`
- `docs/API_DEPENDENCIES.md`
- `KLOP_NEXT_REGISTRATION_UI_IMPLEMENTATION_REPORT.md`

No authentication service, API request schema, backend, SQL, or database files were changed.

## 3. Removed Google/SSO UI

**IMPLEMENTED.** Removed the “OR CONTINUE WITH” divider, Google and SSO buttons, and their “Coming soon” labels from the Login page only. OAuth/SSO backend or other infrastructure was not changed. The login help text, branding panel, illustration, fields, password visibility control, Sign in action, error handling, and footer remain.

## 4. Official logo

**IMPLEMENTED.** The existing official image at `docs/KLOP One Portal NEXT Logo.png` remains the sign-in logo, sourced through the centralized `src/app/brand.ts` configuration. The image artwork and aspect ratio were not changed.

## 5. Branding configuration

**IMPLEMENTED.** Reused the existing centralized application name, tagline, display name, browser title, logo, and favicon reference in `src/app/brand.ts`. The auth page uses the existing KLOP Next display identity; backend identity remains `KLOP PLATFORM`.

## 6. Registration route structure

**IMPLEMENTED.** Reused `/register` for the type selector, account form, and accepted state; no duplicate public route was added. `/verify-email` continues to open the existing verification form. A verification success returns to the sign-in form without automatically signing in.

## 7. Registration type selector

**IMPLEMENTED.** Added keyboard-accessible PERSONAL and ORGANIZATION selectable cards with a single selected value, visible selected state, descriptions, and a Continue action. These stable UI codes represent onboarding intent only. They are not database IDs, Tenant creation, security roles, or permissions.

## 8. Account form and validation

**IMPLEMENTED.** Both choices use the same form: Full Name, Email Address, Password, and Confirm Password. The existing `displayName` mapping, email validation, and password limits are retained; confirmation is checked client-side and never sent. No company, personal identity, or legal-document fields are requested at account registration.

## 9. Existing Register API integration

**EXISTING API REUSED.** `POST /api/v1/auth/register` receives only the contract fields `displayName`, `email`, and `password`. The UI-only confirmation password and PERSONAL/ORGANIZATION intent are excluded. HTTP 202 remains accepted semantics. The page shows the required generic “Check your email” state and does not display the API message or claim that email delivery, verification, profile creation, or Tenant creation has completed.

## 10. Email verification integration

**EXISTING API REUSED.** Existing `/verify-email` form calls `POST /api/v1/auth/verify-email` with `userId` and `token`; resend calls `POST /api/v1/auth/resend-verification` with `email`. Verification codes are masked in the form. Verification success returns to sign-in; resend uses generic non-enumerating feedback. API errors continue through the shared safe error mapper, including HTTP 429 handling.

## 11. PERSONAL onboarding

**UI PREVIEW ONLY.** The accepted state shows a non-persistent preview of future personal identity, contact, address, additional verification, and review steps. It does not collect or save profile data and does not create a PERSONAL Tenant.

## 12. ORGANIZATION onboarding

**UI PREVIEW ONLY.** The accepted state shows a non-persistent preview of future organization details, owner information, review, and master-data-driven Organization Type/document requirements. It does not hardcode catalogs, collect organization data, upload documents, or create an ORGANIZATION Tenant.

## 13. Registration intent persistence

**BACKEND INTEGRATION PENDING.** The chosen type is held only in React component state for the current flow. It is not persisted across refreshes or email verification and is never used for authorization. If no server-owned intent is available later, the user must choose again. A future contract proposal is recorded in `docs/API_DEPENDENCIES.md`.

## 14. Error and security handling

**IMPLEMENTED.** Passwords are never stored in browser storage or logged. The form prevents mismatched confirmation and disables submission while submitting. Non-sensitive form input remains after request failures. Registration and resend success do not echo API messages that could disclose account existence. Server validation remains authoritative; no role or Tenant privilege is granted by the selector.

## 15. Build and typecheck

- `npm run build` — **PASS** (`tsc -b` and Vite production build).
- `npm run lint` — not run; no lint script is defined in `package.json`.

## 16. Frontend test results

- `npm run test` — **PASS**, 7 test files and 50 tests.
- `npm run test:e2e` — **PASS**, 6 Chromium tests.
- Vitest and Playwright worker counts are limited to two to avoid resource-related test flakiness.
- No SQL mutation, test database, or automatic account creation was used.

## 17. Login regression results

**IMPLEMENTED.** Unit and browser tests cover the existing email/password Login form, safe authentication error display, existing sign-in call, official brand presence, mobile overflow, and absence of Google/SSO options. Existing `AuthContext`, token/session handling, login redirect, and authorization behavior were not modified. No live SUPER_ADMIN or PLATFORM_SUPPORT credentials were used for manual login testing.

## 18. Backend unchanged confirmation

**CONFIRMED.** Changes are confined to the frontend project. The authentication service/endpoints, backend, response/request schema, and frozen baseline were not changed.

## 19. Database unchanged confirmation

**CONFIRMED.** No database object or permission was modified; no database mutation or test-account creation was performed.

## 20. Future backend contract requirements

**BACKEND INTEGRATION PENDING.** Persisting registration intent requires an explicitly approved server contract that validates a stable intent code, stores it with a pending registration, and preserves generic acceptance semantics. The intent must never grant a role or permission. Future onboarding also needs verified, authorized personal-profile and organization-application operations, master-data-backed Organization Type/document requirements, and a server-confirmed Tenant creation step. No such request property or endpoint is assumed by this frontend.

**MANUAL E2E PENDING.** Browser tests stub HTTP responses to verify frontend mapping and states; live registration, email delivery, verification, and privileged-account login were not performed.

## 21. Terms & Conditions modal revision

**IMPLEMENTED — FRONTEND ONLY.** The Create Account page keeps its registration type, identity/password fields, Create Account action, and Change Registration Type action. The Terms area now contains the type-specific “Read the … Terms & Conditions” control and a status icon (accessible as not accepted/accepted, green when accepted); the main form contains no acceptance checkbox or visible “Not accepted” text. A short friendly unavailable/load-failure message is shown when relevant, and submission stays disabled unless the form is valid and current applicable Terms have been accepted. The registration footer places “Already have an account? Sign in” on the left and “Change registration type” on the right in the same row.

The shared accessible Terms modal is implemented in `src/features/auth/TermsModal.tsx` using the existing Radix Dialog wrapper. It stays on `/register`, preserves entered form values, traps focus, supports Escape and Cancel, restores focus to the Terms control, and adapts to mobile. `pdfjs-dist` renders every page to the scrollable viewer and extracts page text for assistive technology; the viewer reports ready only after all pages finish rendering. The modal header and footer remain fixed while the document area scrolls. Desktop sizing is up to 60rem wide and 86vh high (capped at 90vh); mobile sizing is 95vw by 95dvh.

**PDF source and status:** The source is `docs/KLOP_Next_Terms_and_Conditions.pdf`; the development URL is `/documents/KLOP_Next_Terms_and_Conditions.pdf`. The file was copied unchanged to `public/documents/` (matching SHA-256) and Vite serves it with `application/pdf` in development. It is a combined six-page document for PERSONAL and ORGANIZATION, not two separate terms documents. The embedded title/subject and page text explicitly identify it as a draft, label draft version 0.1 as not approved, and leave the effective date as a placeholder. The frontend displays that draft metadata and uses the selected Registration Type in the modal, but does not invent an official Document ID or effective date. Vite excludes this draft public directory from production builds; do not deploy the preview asset.

**Agreement and registration gating:** The single agreement checkbox exists only in the modal. Because the supplied PDF is a draft with no official Document ID or published status, the checkbox communicates that acceptance is unavailable and remains disabled after all six pages render; `I Agree` and Create Account remain disabled. The modal reports PDF loading and rendering errors without accepting. The consent path still requires a Published, applicable document with a stable ID/version; no consent is recorded for this draft. The same combined PDF is configured for both registration types, without claiming their terms are independent.

The frontend document contract in `src/features/auth/termsDocuments.ts` retains an adapter for future official-document delivery. An approved Privacy Policy and official Terms API were not found. Required backend work remains: authorized document upload/publish/withdraw, retrieval of the current Published and applicable document, and server-side validation/persistence of document ID, accepted version, registration intent/type, timestamp, user/registration reference, and immutable consent audit evidence. The existing Register request remains exactly `displayName`, `email`, and `password`. The backend, Login/Register/Refresh/Logout APIs, database, stored procedures, and frozen baseline are unchanged.

**Validation:** `npm run build` — **PASS**; `npm run test` — **PASS** (8 files, 53 tests); Chromium E2E — **PASS** (7 tests). Browser checks verified the PDF URL returns `application/pdf`, all six pages render, the viewer has vertical overflow and scrolls independently, header/footer remain visible, the background page does not scroll, mobile has no horizontal overflow, and PDF-load errors keep agreement blocked. A visual browser inspection confirmed the rendered PDF modal and disabled draft-consent state. `npm run lint` is unavailable because no lint script is defined. The Terms flow is not production-ready until legal approval and backend document/consent contracts exist.
