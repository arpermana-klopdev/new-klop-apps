# Register UI–Backend Integration Report

## 1. Existing frontend/backend mapping

- [LoginPage.tsx](./klop-next_ui/src/features/auth/LoginPage.tsx) contains PERSONAL/ORGANIZATION selection, Create Account validation, email verification, and the existing Login flow.
- The frontend posts through [auth.ts](./klop-next_ui/src/api/auth.ts) to the existing `POST /api/v1/auth/register`.
- Backend [Contracts.cs](./klop-next-platform-api/src/KLOP.Platform.Application/Features/Contracts.cs) defines `RegistrationRequest`; [AuthenticationHandlers.cs](./klop-next-platform-api/src/KLOP.Platform.Api/Endpoints/Authentication/AuthenticationHandlers.cs) returns the existing generic HTTP 202 response.
- Published Terms metadata and PDF are served by the existing `/api/v1/public/legal/terms/current` and `/api/v1/public/legal/terms/{documentVersionId}/file` endpoints.
- Existing email verification, resend, and Login implementations were retained.

## 2. Files changed

- [LoginPage.tsx](./klop-next_ui/src/features/auth/LoginPage.tsx) — sends the backend Register contract, handles `TERMS_VERSION_OUTDATED`, and prevents duplicate submission.
- [TermsModal.tsx](./klop-next_ui/src/features/auth/TermsModal.tsx), [termsDocuments.ts](./klop-next_ui/src/features/auth/termsDocuments.ts), and [login.css](./klop-next_ui/src/features/auth/login.css) — fetches published Terms metadata, keeps the existing PDF viewer/scrollbar, and shows the draft PDF without allowing consent when official Terms cannot be verified.
- [legal.ts](./klop-next_ui/src/api/legal.ts) — new API wrapper for published Terms metadata.
- [client.ts](./klop-next_ui/src/api/client.ts), [contracts.ts](./klop-next_ui/src/api/contracts.ts), [openapi.yaml](./klop-next_ui/openapi.yaml), and [schema.d.ts](./klop-next_ui/src/api/schema.d.ts) — API URL resolution and updated Register/Terms contracts.
- [LoginPage.test.tsx](./klop-next_ui/tests/LoginPage.test.tsx), [api-client.test.ts](./klop-next_ui/tests/api-client.test.ts), and [termsDocuments.test.ts](./klop-next_ui/tests/termsDocuments.test.ts) — focused flow and contract tests.
- No backend, database, migration, SQL security, or authentication implementation files were changed.

## 3. API payload verification

Verified for both registration types:

```json
{
  "fullName": "Ada Lovelace",
  "email": "ada@example.com",
  "password": "a-valid-password",
  "registrationType": "PERSONAL",
  "termsDocumentVersionId": "02468ace-1357-4bdf-8024-68ace1357bdf",
  "termsAccepted": true
}
```

`ORGANIZATION` is also covered. Confirm Password is validated in the UI and is not included in the request. The 202 response is treated generically; the UI asks the user to check for verification instructions and does not claim that an account was created.

## 4. Terms integration status

- The UI requests current Terms metadata per registration type and uses the backend `documentVersionId`, publication status, version, effective date, and PDF URL. Metadata requests bypass stale cache entries.
- Consent is possible only through the modal checkbox for a published document. “Accepted” is shown on the Register page after I Agree. A stale-version response clears consent and opens the current Terms for review.
- Read-only checks against the local Development API returned HTTP 404 `TERMS_UNAVAILABLE` for both PERSONAL and ORGANIZATION. The existing bundled PDF remains readable in the modal as a clearly marked draft; acceptance and Create Account remain disabled. No document ID or consent is fabricated.

## 5. Build/test results

- Frontend typecheck: `npm run typecheck` — passed.
- Frontend build: `npm run build` — passed. Vite reported existing annotation warnings from Zod dependency files.
- Frontend tests: `npm test` — 63 passed.
- Backend build: `dotnet build KLOP.Platform.sln --no-restore` — passed, 0 warnings/errors.
- Backend unit tests: `dotnet test tests\KLOP.Platform.UnitTests\KLOP.Platform.UnitTests.csproj --no-build --no-restore` — 105 passed. No database or registration writes were used.
- Frontend lint was not run; this project has no lint script.

## 6. Remaining blockers specifically affecting Register

Development has no currently published Terms document for either registration type (`TERMS_UNAVAILABLE`). Therefore real registration is intentionally blocked until an authorized Terms version is published. The Register request contract and HTTP 202 flow were validated with non-mutating tests; no Development registration was submitted.

## 7. Manual Register test steps

1. Select PERSONAL or ORGANIZATION and complete Full Name, Email, Password, and Confirm Password.
2. With the current Development state, open Terms and verify the draft PDF is readable to its final page; confirm the draft warning, disabled checkbox/I Agree, and disabled Create Account.
3. After an authorized Terms version is published for the chosen type, open Terms, verify the displayed metadata/PDF, explicitly check the modal checkbox, then select I Agree. Confirm “Accepted” appears and form values remain.
4. Submit using an approved test email only. Inspect the request for `fullName`, `email`, `password`, `registrationType`, `termsDocumentVersionId`, and `termsAccepted: true`; confirm no Confirm Password is sent.
5. Confirm the generic verification-instructions response, complete the existing email verification flow, then sign in through the existing Login page.
6. To check a Terms-version race, coordinate a newly published version between acceptance and submission; verify consent resets and the new version must be reviewed and accepted.
