# Backend Architecture Refactoring Changelog

## Structural changes

- Reduced `src/KLOP.Platform.Api/Program.cs` from 633 lines to the composition root: builder creation, service registration, pipeline and endpoint-module calls, and application start.
- Added `Bootstrap/ServiceRegistration.cs`, `AuthenticationRegistration.cs`, `ObservabilityRegistration.cs`, and `RequestPipeline.cs`. Middleware ordering and startup validation were retained; Serilog is still configured before SQL-backed startup settings are loaded.
- Extracted route definitions from Program into Authentication, Tenant, MasterData, and System endpoint modules. Handler bodies, paths, methods, metadata, cookies, filters, and policies were retained.
- Added `InfrastructureRegistration.AddPlatformInfrastructure` for settings, SQL repository, Key Vault, signing, token issuer, and email-sender registrations.
- Split `KlopRepository` into shared execution/parameter helpers and Identity, Tenants, and MasterData partial implementations. Stored procedure names and parameter mappings were retained.
- Moved JWT signing, Key Vault, and SMTP implementations to Infrastructure; the Key Vault port/value contract now lives in Application. Refresh-cookie behavior remains in the API.
- Added direct API references to Application and Domain alongside Infrastructure; no circular references were introduced.
- No SQL, database, Production configuration, frozen baseline, authentication algorithm, account, role, or permission changes were made.

## File moves and splits

| Original path | New path(s) / disposition |
|---|---|
| `src/KLOP.Platform.Api/ApiHelpers.cs` | `src/KLOP.Platform.Api/Extensions/ApiHelpers.cs` |
| `src/KLOP.Platform.Api/Authorization.cs` | `src/KLOP.Platform.Api/Authorization/TenantPermissionAuthorization.cs` |
| `src/KLOP.Platform.Api/HealthReadinessDocumentTransformer.cs` | `src/KLOP.Platform.Api/OpenApi/HealthReadinessDocumentTransformer.cs` |
| `src/KLOP.Platform.Api/OpenApiResponseModels.cs` | `src/KLOP.Platform.Api/OpenApi/OpenApiResponseModels.cs` |
| `src/KLOP.Platform.Api/OpenApiSecurityTransformers.cs` | `src/KLOP.Platform.Api/OpenApi/OpenApiSecurityTransformers.cs` |
| `src/KLOP.Platform.Api/SqlServerReadinessCheck.cs` | `src/KLOP.Platform.Api/Health/SqlServerReadinessCheck.cs` |
| `src/KLOP.Platform.Api/ValidationFilter.cs` | `src/KLOP.Platform.Api/Filters/ValidationFilter.cs` |
| `src/KLOP.Platform.Api/AuthServices.cs` | `TokenIssuer` and `SmtpVerificationEmailSender` moved to Infrastructure; `RefreshCookies` retained in `src/KLOP.Platform.Api/Security/RefreshCookies.cs` |
| `src/KLOP.Platform.Api/KeyMaterial.cs` | `src/KLOP.Platform.Infrastructure/Security/KeyMaterial.cs` |
| `src/KLOP.Platform.Api/KeyVaultSecrets.cs` | `src/KLOP.Platform.Infrastructure/Security/KeyVaultSecrets.cs`; `IKeyVaultSecrets` and `KeyVaultSecretValue` are Application abstractions |
| `src/KLOP.Platform.Application/Contracts.cs` | `src/KLOP.Platform.Application/Features/Contracts.cs` |
| `src/KLOP.Platform.Application/PlatformServices.cs` | Split into `Features/Authentication/AuthenticationService.cs` and `Features/Tenants/TenantManagementService.cs` |
| `src/KLOP.Platform.Application/RequestValidators.cs` | Split into `Features/Authentication/AuthenticationValidators.cs` and `Features/Tenants/TenantValidators.cs` |
| `src/KLOP.Platform.Application/Security.cs` | `src/KLOP.Platform.Application/Features/Security.cs` |
| `src/KLOP.Platform.Application/Ports.cs` | Split into `Abstractions/Configuration/IPlatformRuntimeSettings.cs`, `Notifications/IVerificationEmailSender.cs`, `Persistence/IPlatformRepository.cs`, and `Security/IAccessTokenIssuer.cs` |
| `src/KLOP.Platform.Domain/Models.cs` | Split into `Identity/IdentityModels.cs`, `Tenants/TenantModels.cs`, and `MasterData/MasterDataModels.cs` |
| `src/KLOP.Platform.Infrastructure/KlopRepository.cs` | Shared helpers remain in `Persistence/SqlServer/Repositories/KlopRepository.cs`; feature methods are in the Identity, Tenants, and MasterData repository partials |
| `src/KLOP.Platform.Infrastructure/RuntimeSettings.cs` | `src/KLOP.Platform.Infrastructure/Configuration/RuntimeSettings.cs` |
| `src/KLOP.Platform.Infrastructure/SqlConnectionFactory.cs` | `src/KLOP.Platform.Infrastructure/Persistence/SqlServer/Connections/SqlConnectionFactory.cs` |
| `tests/KLOP.Platform.UnitTests/SecurityTests.cs` | `tests/KLOP.Platform.UnitTests/Authentication/SecurityTests.cs` |
| `tests/KLOP.Platform.UnitTests/OpenApiSecurityTests.cs` | `tests/KLOP.Platform.UnitTests/ApiContracts/OpenApiSecurityTests.cs` |
| `tests/KLOP.Platform.IntegrationTests/DatabaseWorkflowTests.cs` | `tests/KLOP.Platform.IntegrationTests/Persistence/DatabaseWorkflowTests.cs` |
| `tests/KLOP.Platform.IntegrationTests/SqlServerFactAttribute.cs` | `tests/KLOP.Platform.IntegrationTests/Persistence/SqlServerFactAttribute.cs` |

## New files

- API bootstrap and four route modules plus the shared endpoint-map entry point.
- Infrastructure DI registration, Security/Key Vault and token implementation files, and SMTP notification implementation.
- Application Key Vault port.
- Unit tests for route/method/security metadata, refresh-cookie attributes/read behavior, and Infrastructure DI resolution.

## Namespace and dependency changes

- Existing public CLR namespaces and model/contract shapes were retained despite file moves, minimizing source-level compatibility risk.
- New API bootstrap and endpoint modules use `KLOP.Platform.Api.Bootstrap` and `KLOP.Platform.Api.Endpoints`; Infrastructure implementations use `KLOP.Platform.Infrastructure`; the new Key Vault port uses `KLOP.Platform.Application`.
- API now explicitly references Application and Domain rather than relying on Infrastructure's transitive references.
- UnitTests now explicitly references Infrastructure for its direct Infrastructure-registration contract test.
- Infrastructure now directly references its JWT and hosting abstractions packages for security and notification implementations.

## Intentional exceptions

- Shared Application contracts remain in the existing `KLOP.Platform.Application` namespace for compatibility.
- ASP.NET refresh-cookie construction stays in API because it is an HTTP response concern.
- The existing repository port remains one interface because all methods are implemented by the same SQL adapter and changing its consumers is outside a structural relocation.
- Authentication hash compatibility and Development SQL least-privilege remediation were deliberately not mixed into this change.