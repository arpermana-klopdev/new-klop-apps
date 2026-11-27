# Registration Setup — effective policy and Terms readiness

Issue #7. Scope is source-only while SQL and live validation are on HOLD.

- The Setup Center Registration Setup page uses the existing public `GET /api/v1/auth/registration-policy` contract for allowed registration types, effective Terms consent and password bounds. These are effective runtime settings, not an editable database catalog.
- Each PERSONAL/ORGANIZATION card uses `GET /api/v1/public/legal/terms/current` for that scope; a missing published document is distinguished from failed retrieval or a mismatched response. Required unverified Terms are flagged. Refresh/retry is available. No inferred values, mutation controls, credentials, or storage references.
- Email delivery/verification configuration and onboarding submission behavior are not exposed by these contracts. No assertion of operational readiness is made.
- System Configuration administration remains HOLD: dedicated approved PLATFORM authorization and protected database read/write contracts are prerequisites. Do not reuse an unrelated permission or expose raw configuration/secret values. Notifications and master-data writes remain HOLD.
- No backend contract changes are needed for this read-only integration. No SQL changes or execution, new grant, deployment, or live test. Existing frozen artifacts untouched.
- Three component regression cases added: effective policy and scoped Terms, failure/retry, required missing Terms. GitHub CI validates source; record actual results on the PR. Live UAT remains owner-held.
