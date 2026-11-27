# Security review and release blockers — v1.3 DRAFT

This is a **candidate**, not security approval. All DB write SPs must be reviewed and tested on the user's SQL Server before approval.

## Confirmed design controls in the package

- Baseline preservation; new stored procedures only in v1.3 delta, not v1.1/v1.2/v1.2.1.
- No direct application SQL DML; Dapper with `CommandType.StoredProcedure` and named parameters.
- Permission checks at API and SQL boundaries; active session and tenant membership rechecked against DB.
- Passwords encoded with PBKDF2-HMAC-SHA256, 600k iterations, random 32-byte salt; hashes never logged.
- Random 256-bit verification and refresh tokens; only SHA-256 digests stored in SQL; one-time refresh rotation and replay revocation.
- RSA-signed JWT (15-minute lifetime), public JWKS; production private signing key loaded from Azure Key Vault using DefaultAzureCredential. Development ephemeral signing key only when no vault is configured.
- SMTP verification message with user ID + code; TLS required in production; SMTP password (if needed) loaded from Key Vault.
- Audit/security inserts performed within SQL transactions for the new login success/failure/session events; last-OWNER constraints remain enforced by v1.2.1 SPs.
- Per-IP endpoint rate limits, HTTP-only Secure SameSite Strict refresh cookie; Origin match on refresh.
- Input validation and stable error envelopes; no raw SqlException text returned to client.

## P0/P1 blockers before Production

1. **Actual .NET compile and NuGet restore** against the chosen SDK; this environment does not have .NET SDK. Resolve all compiler/compatibility issues.
2. **Development SQL execution and assertions** for new SPs, including concurrent refresh replay and lockout, and direct DML denial for runtime principal. No SQL Server connection was available here.
3. **Penetration/integration verification:** per-IP rate limiter behind trusted reverse proxy, lockout bypass/DoS, CSRF, tenant-switch and session revocation, API response error mapping, SMTP retry/undelivered email reconciliation.
4. **Reliable email delivery:** no transactional outbox exists in frozen schema. Registration may commit even if SMTP delivery fails; resend endpoint is available but delivery reconciliation is not complete.
5. **Full OAuth/OIDC / Entra SSO** not included in this local-login reference package. OpenIddict and token exchange must be implemented before claiming platform-wide auth baseline compliance.
6. **Rotation/revocation of Key Vault signing keys**, JWKS overlap, key retention and tenant/app audience strategy still need deployment design.
7. **Data retention, audit immutability**, backup/restore testing, Azure monitoring, alerting, operational security incident response still require review.
8. Confirm `SqlConnectionFactory` authentication method works for the actual Development/Production SQL Server and least-privilege principal; never grant the API identity dbo/db_owner.
9. Confirm package is correctly merged against the real existing repository to avoid project/reference naming collisions.
10. Validate original architecture conflict about single-tenant vs many-to-many membership by formal ACR, without silent changes.

## Status policy

Do not call this candidate `PASS`, `FROZEN`, `DEPLOYED`, or `PRODUCTION READY` solely because files exist. Unit/build/integration test results require real execution evidence. Record each blocker and review decision in the Excel tracker.
