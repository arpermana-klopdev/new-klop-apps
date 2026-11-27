# Project structure

```text
KLOP.Platform.sln
├── src/
│   ├── KLOP.Platform.Api/
│   │   ├── Program.cs
│   │   ├── Bootstrap/ (service, authentication, observability, request pipeline)
│   │   ├── Endpoints/ (Authentication, Tenants, MasterData, System)
│   │   ├── Authorization/  Extensions/  Filters/  Health/  OpenApi/  Security/
│   ├── KLOP.Platform.Application/
│   │   ├── Abstractions/ (Configuration, Notifications, Persistence, Security)
│   │   └── Features/ (Authentication, Tenants, shared contracts/security)
│   ├── KLOP.Platform.Domain/ (Identity, Tenants, MasterData)
│   └── KLOP.Platform.Infrastructure/
│       ├── Configuration/  DependencyInjection/
│       ├── Notifications/Email/
│       ├── Persistence/SqlServer/ (Connections, Repositories by feature)
│       └── Security/ (Key Vault, signing keys, token issuance)
├── tests/
│   ├── KLOP.Platform.UnitTests/ (ApiContracts, Authentication, Persistence)
│   └── KLOP.Platform.IntegrationTests/ (Persistence; guarded)
├── database/  sql/  docs/  deploy/
└── Dockerfile  CHANGELOG.md  VERSION_MANIFEST.json
```

See [BACKEND_ARCHITECTURE.md](architecture/BACKEND_ARCHITECTURE.md) for the full dependency graph and feature responsibilities, and [API_CONTRACT_VERIFICATION.md](api/API_CONTRACT_VERIFICATION.md) for the route inventory. Endpoint maps are feature modules, not composition-root code. New application behaviors should be implemented behind Application services and ports rather than embedding SQL or business rules in HTTP handlers.
