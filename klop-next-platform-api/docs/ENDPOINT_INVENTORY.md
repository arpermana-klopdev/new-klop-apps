# KLOP Platform API Endpoint Inventory

**Current source:** Feature modules under `src/KLOP.Platform.Api/Endpoints/`; `Program.cs` is the composition root. The full route/method/authentication/rate-limit inventory is maintained in [API_CONTRACT_VERIFICATION.md](docs/api/API_CONTRACT_VERIFICATION.md).

The API retains 15 `/api/v1` operations and three infrastructure routes. The generated OpenAPI document contains all 18 operations and matches the pre-refactor build snapshot exactly. The live API was not started for this structural refactor because startup loads SQL-backed runtime settings.

## Feature map

- Authentication: `src/KLOP.Platform.Api/Endpoints/Authentication/AuthenticationEndpoints.cs`
- Tenants and memberships: `src/KLOP.Platform.Api/Endpoints/Tenants/TenantEndpoints.cs`
- Master data: `src/KLOP.Platform.Api/Endpoints/MasterData/MasterDataEndpoints.cs`
- System, health, and JWKS: `src/KLOP.Platform.Api/Endpoints/System/SystemEndpoints.cs`
- Shared `/api/v1` validation filter and route registration: `src/KLOP.Platform.Api/Endpoints/PlatformEndpointMappings.cs`

All endpoints continue to delegate business and persistence work to Application services or ports. No SQL statements or table DML were added to HTTP handlers. Procedure dependencies are documented in [DATABASE_DEPENDENCIES.md](docs/DATABASE_DEPENDENCIES.md). The route-contract test checks all 18 route patterns, explicit method metadata, tenant authorization, auth rate limits, auth summaries, and selected response statuses.

The refresh route continues to require the existing protected cookie and exact configured Origin. Tenant permission checks remain in the authorization handler and stored procedures. Login compatibility remains a separately documented blocker; no real-user login or session flow was exercised.