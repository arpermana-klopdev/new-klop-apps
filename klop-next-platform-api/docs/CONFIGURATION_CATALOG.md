# Configuration catalog

Business/runtime settings are read from `cfg.SystemConfigurations` through `cfg.usp_Configuration_GetByKey`. Values are validated at startup and held in memory until restart. The application does not implement a generic configuration write API.

## Bootstrap settings

Only infrastructure bootstrap values belong in `appsettings.Development.json`, `appsettings.Production.json`, or environment variables:

| Setting | Purpose |
|---|---|
| `Sql:Server` | SQL Server host/instance |
| `Sql:Database` | Environment-specific database |
| `Sql:Authentication` | `IntegratedSecurity`, `ActiveDirectoryDefault`, or `ActiveDirectoryManagedIdentity` |
| `Sql:TrustServerCertificate` | Development-only certificate trust override; do not enable in Production |
| `KeyVault:VaultUri` | Environment-specific HTTPS Key Vault address |
| `AllowedHosts` | Explicit host filtering; wildcard is rejected in Production |
| `ForwardedHeaders:KnownProxies` | Explicit trusted proxy IPs, if deployed behind a proxy |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Optional telemetry collector endpoint |

No passwords, signing keys, SMTP credentials, or business/runtime flags belong in these files. In particular, `database.command_timeout_seconds` is loaded from SQL; a `Sql:CommandTimeoutSeconds` appsettings value is not supported or used.

## SQL-backed values

### Existing v1.1 / v1.2 values

| Key | Type | Use |
|---|---|---|
| `auth.access_token_minutes` | INTEGER / PLAIN | Access token lifetime |
| `auth.refresh_token_days` | INTEGER / PLAIN | Session and refresh lifetime |
| `security.max_login_attempts` | INTEGER / PLAIN | SQL login lockout threshold |
| `security.password.min_length` | INTEGER / PLAIN | Password policy (12–128) |
| `registration.personal.enabled` | BOOLEAN / PLAIN | Registration toggle for the database tenant type with this code |
| `registration.organization.enabled` | BOOLEAN / PLAIN | Registration toggle for the database tenant type with this code |

### v1.3 proposed values

| Key | Expected type | Use |
|---|---|---|
| `auth.jwt.issuer` | STRING / PLAIN | JWT issuer |
| `auth.jwt.audience` | STRING / PLAIN | JWT audience |
| `web.allowed_origin` | STRING / PLAIN | Single HTTPS SPA origin |
| `smtp.host` | STRING / PLAIN | SMTP host |
| `smtp.port` | INTEGER / PLAIN | SMTP port |
| `smtp.from` | STRING / PLAIN | Sender address |
| `smtp.require_tls` | BOOLEAN / PLAIN | Production must be true |
| `smtp.username` | STRING / PLAIN, optional | SMTP login name |
| `auth.email_verification_hours` | INTEGER / PLAIN | Verification challenge lifetime (1–24) |
| `auth.signing_key_ref` | STRING / KEYVAULT_REFERENCE | Key Vault secret name only |
| `smtp.password_ref` | STRING / KEYVAULT_REFERENCE | Key Vault secret name only |

These are authored in `sql/050_config_seed_DEVELOPMENT_REVIEW.sql`, which is a Development-only proposal and must be reviewed before execution. Startup fails closed if required issuer or audience settings are missing, inactive, empty, or have the wrong type or storage; the issuer must also be an HTTPS URI. Do not bypass these checks to access Swagger. For a read-only presence/type check (without displaying configuration values), use:

```sql
SELECT expected.ConfigurationKey,
       CASE WHEN actual.ConfigurationId IS NULL THEN 'MISSING_OR_INACTIVE'
            WHEN NULLIF(LTRIM(RTRIM(actual.ConfigurationValue)), '') IS NULL THEN 'EMPTY'
            ELSE 'PRESENT' END AS Status,
       actual.ValueType, actual.StorageType
FROM (VALUES ('auth.jwt.issuer'), ('auth.jwt.audience'), ('auth.signing_key_ref')) AS expected(ConfigurationKey)
LEFT JOIN cfg.SystemConfigurations AS actual
  ON actual.ConfigurationKey = expected.ConfigurationKey AND actual.IsActive = 1;
```

Also verify that `cfg.usp_Configuration_GetByKey` returns the active rows to the application identity. Review the existing Development-only seed with a DBA before any authorized database change; it does not overwrite existing rows. The signing-key reference can be empty only for Development when no Key Vault URI is configured, in which case the existing ephemeral key is used. Production requires an approved Key Vault reference and valid private key.

### v1.4 additions

The additive, idempotent proposal is [001_runtime_settings.sql](../database/migrations/v1.4/001_runtime_settings.sql):

| Key | Default proposal | Bounds | Use |
|---|---:|---:|---|
| `database.command_timeout_seconds` | 30 | 1–120 | Dapper Stored Procedure timeout |
| `security.auth_requests_per_minute` | 8 | 1–120 | Per-IP auth route fixed-window limit |

The application fails startup if these required keys are absent or invalid. DBA review and Development-only execution are required. The migration does not overwrite existing rows.

## Secret loading and environment rules

- Production signing and SMTP secrets are read from Azure Key Vault using `DefaultAzureCredential`; managed identity is preferred.
- `auth.signing_key_ref` must reference a private RSA PEM key of at least 3072 bits. Only public key parameters are exposed through JWKS.
- SMTP credentials are fetched only if an SMTP username is configured.
- Development may use an ephemeral RSA key only when no Key Vault URI is configured. This invalidates tokens on restart and is not suitable for production.
- Only `Development` and `Production` are supported. Production requires TLS for SMTP, explicit `AllowedHosts`, a Key Vault signing key, and environment-separated SQL/Key Vault resources.
- Startup settings are not hot-reloaded; restart after approved configuration changes.
