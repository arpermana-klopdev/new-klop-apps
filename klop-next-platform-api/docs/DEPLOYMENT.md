# Deployment

This package is DRAFT and is not approved for Production. Production deployment requires SQL and security approval plus completed integration/concurrency/security evidence.

## Environment

Only `Development` and `Production` are supported. Use separate SQL databases, managed identities, Key Vaults, and SMTP settings. Never commit production credentials.

Bootstrap values may be provided by environment variables:

```powershell
$env:ASPNETCORE_ENVIRONMENT = 'Production'
$env:Sql__Server = '<sql-server>'
$env:Sql__Database = '<production-database>'
$env:Sql__Authentication = 'ActiveDirectoryManagedIdentity'
$env:KeyVault__VaultUri = 'https://<vault-name>.vault.azure.net/'
$env:AllowedHosts = '<api-hostname>'
$env:OTEL_EXPORTER_OTLP_ENDPOINT = 'http://<collector>:4317'
```

Do not include passwords or private keys in the environment/appsettings. The hosting identity needs only the SQL Stored Procedure EXECUTE grants and Key Vault secret get permission required by the configured references.

## SQL and Key Vault

1. DBA verifies foundation versions and current object definitions.
2. DBA reviews and applies approved v1.3 proposals and the additive v1.4 configuration/grant proposals in Development first.
3. Configure required SQL configuration keys and secret references. Production SMTP TLS is mandatory.
4. Verify SQL TLS certificate trust and the managed identity's effective database permissions. Do not grant `db_owner`, `db_datawriter`, or direct operational table DML.

No migration runs at API startup.

## Reverse proxy and TLS

Terminate TLS at a trusted ingress or serve HTTPS directly. If using forwarded headers, set `ForwardedHeaders__KnownProxies__0` (and further indexed entries as needed) to explicit proxy IPs. The app honors only configured trusted proxies; do not allow arbitrary `X-Forwarded-*` values. Configure the ingress to pass the original HTTPS scheme and use secure cookies.

Production `AllowedHosts` must be explicit and cannot be `*`. Configure proxy-aware rate limits and do not assume one forwarded IP is trustworthy without network controls.

## Container

Build from the solution root:

```powershell
docker build -t klop-platform-api:1.4-draft .
```

The container listens on port 8080 and runs as the non-root app user. Supply runtime settings through the deployment platform; do not bake environment-specific secrets into image layers. The included Mailpit compose file is local Development-only.

## Health and OpenAPI

- `GET /health/live` checks only process liveness.
- `GET /health/ready` checks the configured SQL readiness procedure and returns only generic status.
- Swagger UI at `/swagger` and OpenAPI JSON at `/openapi/v1.json` are exposed only in Development, not Production.

After deployment, verify health, the observed environment, SQL permissions, Key Vault access, TLS, OTLP delivery (if enabled), and a safe authentication flow in a disposable environment. Production promotion requires explicit owner approval.
