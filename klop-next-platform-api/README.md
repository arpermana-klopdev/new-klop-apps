# KLOP Platform Backend (.NET 10)

**Version:** `KLOP-PLATFORM-BACKEND-1.4-DRAFT`  
**Status:** Development read-only/API smoke checks passed; 17 unit tests passed; SQL mutation tests blocked; not production-approved.

This solution ports the 15 approved v1.3 draft API routes to .NET 10 while preserving the database Stored Procedure contracts and the frozen checkpoint. The API does not apply database migrations or write directly to tables. The user-reported v1.5 migration is corroborated by all nine auth/session procedures and signatures being present in the Development catalog; API auth/session remains blocked because the runtime role has no members and none of the nine explicit EXECUTE grants passed verification.

## Quick start

```powershell
dotnet restore KLOP.Platform.sln
dotnet build KLOP.Platform.sln --configuration Release
dotnet test KLOP.Platform.sln --configuration Release
dotnet run --project src/KLOP.Platform.Api/KLOP.Platform.Api.csproj
```

Configure Development SQL access and the required SQL-backed runtime settings first. Mutation integration tests are skipped unless an explicitly opted-in disposable database ending `_TEST` is configured.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Project structure](docs/PROJECT_STRUCTURE.md)
- [API endpoints](docs/API_ENDPOINTS.md)
- [Database integration and migrations](docs/DATABASE_INTEGRATION.md)
- [Observed database dependencies](docs/DATABASE_DEPENDENCIES.md)
- [v1.5 auth/session migration readiness and DBA checklist](docs/DATABASE_V1_5_DEPLOYMENT.md)
- [Known issues and validation gates](docs/KNOWN_ISSUES.md)
- [Configuration catalog](docs/CONFIGURATION_CATALOG.md)
- [Security design/review](docs/SECURITY_DESIGN.md)
- [Logging and observability](docs/LOGGING_DESIGN.md)
- [Test plan and verified results](docs/TEST_PLAN.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Baseline lineage](docs/BASELINE_POINTER.md)
- [Changelog](CHANGELOG.md)
- [Version manifest](VERSION_MANIFEST.json)

See [docs/README.md](docs/README.md) for full setup instructions and known limitations.
