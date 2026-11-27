# KLOP NEXT UI Design System v1.0

This is a candidate design-system baseline for the KLOP One Portal NEXT frontend. It is not frozen or approved; final acceptance belongs to the project owner after visual review and integration testing.

## Brand and theme

- The source of truth for the official logo is `docs/logo.jpeg`. The frontend asset at `src/assets/brand/logo.jpeg` is an exact copy; use the shared `AppLogo` component rather than referencing a machine-specific path or adding duplicate logo handling.
- `src/styles/tokens.css` centralizes the KLOP palette, semantic colors, type scale, spacing, radii, shadows, control dimensions, focus/disabled behavior, motion duration, breakpoints, and z-index layers.
- The default theme is the Enterprise Light Theme. The existing `.dark` theme support is retained with token overrides; it is not newly enabled.
- Tailwind's `brand` palette and `shadow-soft` utility resolve through the global tokens. Prefer these tokens over one-off values for new shared UI.

## Shared UI and layout

| Need | Existing shared component or foundation |
|---|---|
| Buttons | `Button` (`primary`, `secondary`, `ghost`, `danger`; `sm`, `md`) |
| Inputs and password | `TextInput`, `PasswordInput` |
| Checkbox | `AppCheckbox` |
| Labeled fields and validation | `Field`, including associated error IDs |
| Alerts and feedback | `Notice` (`error`, `success`, `info`) |
| Dismissible feedback | `AppToast` |
| Loading | `LoadingState`, `Skeleton`, `AppPageLoader` |
| Content containers and empty states | `AppCard`, `AppEmptyState` |
| Page headings and dialogs | `PageHeading`, `Dialog` |
| Brand image | `AppLogo` (`standard` or `compact`) |
| Authentication layout | `AuthLayout` |
| Authenticated application shell | `AppShell`, which owns the existing header, sidebar, content area, and navigation |

Use the shared components and existing API-driven patterns. Do not add a client-side permission model, fabricated business data, or nonfunctional controls. The login form intentionally omits Remember Me and Forgot Password: the current session architecture does not provide remember-me selection or password-reset routes.

## Login and forms

Use visible labels, `autoComplete`, `aria-invalid`, and `aria-describedby` for validation. Passwords are masked by default and may be revealed only through the labeled visibility control. Disable the submit button while a request is in flight. Authentication errors should come from the API client's safe message mapping; never show raw API payloads or log credentials.

The login uses the existing email/password API contract, in-memory access-token handling, secure refresh cookie, session provider, and route guards. Do not store authentication tokens in browser storage or introduce alternate endpoints.

The approved login composition uses a 40/60 desktop split, with the original `AppLogo` inside a white rounded container, a navy-to-blue brand panel, feature highlights, and a decorative dashboard illustration. The login workspace reuses shared fields and buttons and shows only configured authentication methods: currently email/password. Keep SSO, Google, and administrator contact actions hidden unless their real integrations or destinations are configured. At mobile widths, collapse to one column and hide the decorative illustration.

## Responsive and accessibility standards

- Desktop uses a branded two-column authentication layout; narrower screens reduce decoration and use a single-column mobile layout with the logo visible.
- Use the global focus ring and maintain keyboard-operable controls with descriptive accessible names.
- Keep decoration behind content and hidden from assistive technology.
- Respect `prefers-reduced-motion`; do not rely on animation to communicate state.
- Keep interactive targets at least the shared control height and prevent horizontal overflow.

## Extending the theme

Use tokens for new UI rather than introducing page-specific colors, radii, or shadows. Keep shared components in `src/components`, page-specific layout in the relevant feature, and global token changes in `src/styles/tokens.css`.

Example:

```tsx
<AppCard>
  <PageHeading title="Page title" description="A concise explanation of this view." />
  <Field label="Email address" htmlFor="email">
    <TextInput id="email" type="email" autoComplete="email" />
  </Field>
  <Button variant="primary">Continue</Button>
</AppCard>
```

For layout and authorization, add pages through the existing route structure and `AppShell`. Keep the server API authoritative for session and permission decisions.
