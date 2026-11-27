# Architecture

## Layers

- **Domain** — API-independent identity, tenant, and master-data models.
- **Application** — feature use cases, request contracts, FluentValidation rules, security primitives, and repository/runtime/notification/security ports. It does not reference SQL Server or Infrastructure.
- **Infrastructure** — Dapper/SqlClient implementations of the ports, stored-procedure parameter mapping, SQL-backed settings, connection creation, JWT/key management, and SMTP delivery.
- **API** — feature endpoint modules, refresh-cookie HTTP handling, authorization integration, health checks, middleware, logging, observability, OpenAPI, and dependency-injection composition.

The dependency direction is API → Application and Infrastructure; Application → Domain; Infrastructure → Application. The API also references Domain explicitly for its public route contracts. Domain and Application do not depend on concrete SQL implementations. See [the detailed backend architecture](architecture/BACKEND_ARCHITECTURE.md).

## Persistence

SQL Server is authoritative for account, tenant, membership, role, audit, security event, master, and configuration data. Repository methods invoke named procedures with `CommandType.StoredProcedure`, typed inputs/outputs, cancellation, and a SQL-configured command timeout. No controller/endpoint issues table SQL or dynamic SQL. The database procedures own their transactions; the application does not wrap them in an external transaction.

The existing v1.1 + v1.2 + v1.2.1 schema/procedures are preserved. v1.3 auth/session procedures and v1.4 configuration/grant proposals are additive and require DBA review and Development verification.

## Authentication and authorization

Local registration/login use PBKDF2-HMAC-SHA256, email challenges, short-lived RSA-signed JWTs, and hashed rotating refresh tokens. Token issuance and key material are Infrastructure services; the API performs JWT validation, cookie handling, and HTTP authorization integration. The SQL session is checked on every bearer request. Authorization for tenant operations is resolved from current membership and permission records in SQL at request time.

`TenantPermissionHandler` performs reusable permission checks; the write procedures re-check actor authority, tenant lifecycle, role scope, and last-Owner invariants. Actor and Owner user IDs are derived from claims, never from body data.

## Multi-tenancy

Membership is user-to-tenant many-to-many. Tenant type and registration enablement come from SQL master/configuration rows. Organization types come through the existing master-data procedure. The backend does not assume one tenant per user and does not cache tenant permissions.

## Observability and audit

Serilog emits structured logs to stdout without request/response bodies. OpenTelemetry instruments HTTP and SqlClient and exports via OTLP only when configured. SQL Stored Procedures remain authoritative for transactional audit/security records; Serilog is not an audit substitute.

## Deliberate scope limits

- No Redis dependency or cache is required.
- No hosted background service or message broker is added without an approved job.
- No master/configuration write endpoint is exposed.
- No full OAuth/OIDC authorization-code flow, Entra federation, key rotation overlap, or transactional email outbox is included.
- API-level idempotency is not available in the source database contract.
