# KLOP Platform Backend Architecture

## Solution overview

KLOP Platform is a .NET 10 modular monolith with four production projects and two test projects. The API remains ASP.NET Core Minimal APIs. SQL Server remains authoritative for operational data and configuration; Infrastructure uses Dapper, `Microsoft.Data.SqlClient`, and stored procedures. This structure refactors existing code only; it does not change application workflows or the database contract.

## Dependency graph

```text
KLOP.Platform.Api ───────────────> KLOP.Platform.Application ───────────────> KLOP.Platform.Domain
		├────────────────────────> KLOP.Platform.Domain
		└────────────────────────> KLOP.Platform.Infrastructure ───────────> KLOP.Platform.Application
```

The API references Application, Domain, and Infrastructure explicitly. Infrastructure implements Application ports and depends on Application (and transitively Domain). Application depends on Domain only. Domain has no internal-project or framework dependency. There are no circular project references. API is the composition root; Infrastructure is not referenced from Application or Domain.

## Layer responsibilities

- **API** — HTTP route adapters, request validation filter, authentication/authorization integration, response/cookie handling, health and JWKS endpoints, OpenAPI, middleware pipeline, startup configuration, and composition.
- **Application** — authentication and tenant use cases, request validation, application contracts, and ports for persistence, runtime configuration, notifications, and token issuance. It contains no SQL or ASP.NET HTTP types.
- **Domain** — data models used by identity, tenant, and master-data use cases. Existing models remain simple Dapper/API boundary models; no new invariants were introduced.
- **Infrastructure** — SQL connection factory, SQL-backed runtime settings, Dapper stored-procedure repository, SQL readiness query, infrastructure DI registration, RSA/JWT signing, Key Vault access, and SMTP delivery.

## Feature and module boundaries

API routes are grouped in `Endpoints/Authentication`, `Endpoints/Tenants`, `Endpoints/MasterData`, and `Endpoints/System`. Startup concerns are in `Bootstrap`; response helpers, authorization, validation, health, security, and OpenAPI classes have responsibility-specific folders.

Application use cases and validators are grouped under `Features/Authentication` and `Features/Tenants`. Cross-feature ports are located under `Abstractions/Persistence`, `Configuration`, `Notifications`, and `Security`. Existing public CLR namespaces were retained for moved types to avoid gratuitous source compatibility changes.

Domain models are grouped under `Identity`, `Tenants`, and `MasterData`. The SQL Server repository keeps a shared connection/parameter helper and feature-specific partial implementations under `Persistence/SqlServer/Repositories`.

## Final source layout

```text
src/
├── KLOP.Platform.Api/
│   ├── Program.cs
│   ├── Bootstrap/ (service, authentication, observability, request pipeline)
│   ├── Endpoints/ (Authentication, Tenants, MasterData, System)
│   ├── Authorization/
│   ├── Extensions/
│   ├── Filters/
│   ├── Health/
│   ├── OpenApi/
│   └── Security/ (refresh-cookie adapter)
├── KLOP.Platform.Application/
│   ├── Abstractions/ (Configuration, Notifications, Persistence, Security)
│   └── Features/ (Authentication, Tenants, shared contracts/security)
├── KLOP.Platform.Domain/
│   ├── Identity/
│   ├── MasterData/
│   └── Tenants/
└── KLOP.Platform.Infrastructure/
	├── Configuration/
	├── DependencyInjection/
	├── Notifications/Email/
	├── Persistence/SqlServer/ (Connections, Repositories/{Identity,MasterData,Tenants})
	└── Security/ (Key Vault, key material, token issuance)
tests/
├── KLOP.Platform.UnitTests/ (ApiContracts, Authentication, Persistence)
└── KLOP.Platform.IntegrationTests/ (Persistence; guarded and not run)
```

## Database access and data safety

`IPlatformRepository` is the Application persistence port. `KlopRepository` implements it using shared Dapper execution helpers and named stored procedures. Procedure names, parameter names/types/output handling, command timeout, connection lifecycle, cancellation, and result models were retained in the feature partials. No endpoint executes SQL, no application-table DML was added, and no transaction ownership moved from procedures. Master data, authorization, roles, permissions, and operational configuration remain database-driven.

The `KLOP-PLATFORM-DB-FOUNDATION-1.1` frozen baseline and all database/SQL files are unchanged. No database was connected to, created, migrated, seeded, or modified during this refactor.

## Authentication and authorization boundaries

JWT issuer/audience/signature/lifetime validation, RS256, session checks, tenant permission checks, refresh-cookie name and flags, origin checks, rate limits, lockout handling, and refresh/session stored-procedure calls are retained. The API continues to enforce the existing Development/Production-only policy. Development password-hash compatibility (`100000.saltBase64.hashBase64` versus the verifier's `pbkdf2-sha256$...` encoding) remains a separate unresolved blocker; this refactor does not modify password verification or hashes. The Development SQL runtime identity/least-privilege issue remains documented and unchanged.

## Adding a feature

1. Add HTTP contracts and thin endpoint mappings in the API feature folder; preserve route/version conventions and metadata.
2. Put use-case orchestration and validators in the matching Application `Features` folder.
3. Add only required domain concepts under the corresponding Domain context; keep transport and persistence models simple unless an invariant warrants a domain type.
4. Add an Application port only for a real external dependency. Implement it in Infrastructure and invoke database stored procedures rather than table DML.
5. Register implementations through the existing composition/bootstrap path, and add offline unit/contract tests. Keep persistent database tests guarded and explicitly approved.

## Naming and dependency rules

- Use feature names in endpoint, service, validator, repository-part, and test filenames.
- Application and Domain must not reference Infrastructure, API, SQL Server, or ASP.NET HTTP types.
- Infrastructure may implement Application ports and may depend on external persistence/security/notification libraries; it must not reference API.
- API handlers adapt HTTP input/output and delegate business work to Application or an existing read port.
- Keep stored procedure identifiers and SQL-owned authorization/audit semantics at the persistence boundary.
- Do not add a mediator, ORM, event bus, generic repository layer, or speculative feature without a concrete requirement.