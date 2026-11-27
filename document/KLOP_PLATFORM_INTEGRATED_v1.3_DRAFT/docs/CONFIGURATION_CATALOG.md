# SQL-driven configuration — KLOP v1.3 DRAFT

Per FROZEN v1.1 decision B07, all nonsecret business/runtime configuration lives in `cfg.SystemConfigurations`. Read access uses `cfg.usp_Configuration_GetByKey` (v1.1) and is loaded at API startup. Existing `RequiresRestart` metadata applies. Any sensitive/protected change requires governance review and approval. **No numeric master IDs are hardcoded in API.**

## Bootstrap (only appsettings.Development.json / Production.json or equivalent environment variables)

- `Sql:Server` — hostname (nonsecret)
- `Sql:Database` — environment-specific database name (nonsecret)
- `Sql:Authentication` — `IntegratedSecurity`, `ActiveDirectoryDefault`, or `ActiveDirectoryManagedIdentity` (no password)
- `KeyVault:VaultUri` — vault address, separate Development and Production vaults
- `AllowedHosts` — ASP.NET Core host protection setting

No passwords, JWT private keys, SMTP passwords, tenant codes, or runtime business flags may be stored in appsettings.

## Existing SQL config keys from v1.1

| Key | Purpose | Baseline sample |
|---|---|---|
| `auth.access_token_minutes` | JWT lifetime, read and validated by API | 15 |
| `auth.refresh_token_days` | session + refresh lifetime | 7 |
| `security.max_login_attempts` | SQL login lockout threshold | 5 |
| `security.password.min_length` | API password validation | 12 |
| `registration.personal.enabled` | Personal creation switch | true |
| `registration.organization.enabled` | Organization creation switch | true |
| `registration.email_verification_required` | Baseline security invariant | true |

Security invariants (e.g. email verification mandatory, last OWNER protection) cannot be weakened by generic config edits.

## New proposed SQL keys for v1.3

| ConfigurationKey | StorageType | Development proposal / purpose |
|---|---|---|
| `auth.jwt.issuer` | PLAIN | `https://localhost:7041` |
| `auth.jwt.audience` | PLAIN | `klop-platform` |
| `web.allowed_origin` | PLAIN | `https://localhost:5173` |
| `smtp.host` | PLAIN | `127.0.0.1` (local Mailpit) |
| `smtp.port` | PLAIN | `1025` |
| `smtp.from` | PLAIN | `klop-dev@localhost` |
| `smtp.require_tls` | PLAIN | false in Development, **true in Production** |
| `smtp.username` | PLAIN | blank in Development |
| `auth.signing_key_ref` | KEYVAULT_REFERENCE | Key Vault **secret name only**, never PEM value |
| `smtp.password_ref` | KEYVAULT_REFERENCE | SMTP secret **name only**, never password |
| `auth.email_verification_hours` | PLAIN | 1 |
| `security.login_lockout_minutes` | PLAIN | 15 |

`sql/050_config_seed_DEVELOPMENT_REVIEW.sql` inserts only missing keys, with protected flags and no real secrets. It is a **Development-only proposal**. Production requires separately reviewed values in the Production database, a Production Key Vault URI, and real SMTP/TLS settings. Never copy the Development values into Production.

RuntimeSettings fails closed if required settings are missing, inactive, invalid, or use the wrong StorageType. It does not expose a generic editing API for protected config. Dynamic runtime reload is not in this candidate; restart after approved setting updates.
