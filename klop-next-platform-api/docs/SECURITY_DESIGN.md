# Security design

## Authentication

- PBKDF2-HMAC-SHA256 with 600,000 iterations, random 32-byte salt, and a versioned encoded format; passwords are never reversibly encrypted.
- Verification/refresh tokens use 256 bits of random entropy; only SHA-256 digests are stored.
- Access JWTs use RSA-SHA256, validate issuer/audience/signature/lifetime, and are limited to configured lifetime. Production private signing material is loaded from Azure Key Vault using `DefaultAzureCredential`.
- Development may use an ephemeral RSA key only without a vault URI; tokens expire on process restart.
- The API validates database session state for every JWT request. Refresh rotation/replay handling is delegated to the reviewed SQL procedure.

## Authorization and tenant boundaries

- Tenant membership and permission are rechecked in SQL for each protected operation; permission values are contract identifiers, not a local role catalog.
- User and tenant IDs supplied by clients are not authentication claims. The server derives owner/actor IDs from `sub`.
- SQL procedures independently enforce tenant status, active membership, scope, role authority, and last-active-Owner protection.
- Personal/organization tenant types, organization types, and registration settings are read from SQL.
- The backend exposes no platform-role mutation route; broader platform administration requires approved procedure and policy contracts.

## Credential, cookie, and request protections

- Refresh tokens are only issued via a `__Host-` HttpOnly, Secure, SameSite=Strict cookie; refresh also checks exact configured Origin.
- CORS allows one configured origin and only required methods/headers; wildcard origins are not used.
- Auth routes use a fixed-window per-IP limit from SQL configuration. Behind a proxy, only explicitly trusted forwarded headers are honored.
- Request bodies are limited to 64 KiB. HTTPS redirection and Production HSTS are enabled. Security headers deny framing and disable MIME sniffing.
- SQL connections require encryption and certificate validation (`TrustServerCertificate=false`).

## Secrets and logging

No secrets are permitted in appsettings or SQL configuration values. SQL stores only Key Vault secret references. Tokens, passwords, SQL parameter values, and request bodies are not logged or returned. SQL errors map to safe Problem Details responses.

## Auditing

Authoritative audit/security events are written transactionally by the Stored Procedures. Serilog is operational logging only and is not the audit system of record.

## Release blockers

- The v1.3 SQL delta and v1.4 migration/grants need Development execution and independent review.
- SQL integration/security/concurrency tests have not run.
- Full OIDC/Entra SSO, key rotation/JWKS overlap, distributed rate limiting, email outbox/reconciliation, reverse-proxy production settings, retention, alerting, and penetration testing remain open.
- SMTP uses the framework client retained from v1.3; replace or formally approve it before production use.
