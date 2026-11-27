using KLOP.Platform.Api;
using KLOP.Platform.Api.Endpoints.Authentication;
using KLOP.Platform.Api.Endpoints.Legal;
using KLOP.Platform.Api.Endpoints.Master;
using KLOP.Platform.Api.Endpoints.Onboarding;
using KLOP.Platform.Api.Endpoints.Registrations;
using KLOP.Platform.Api.Endpoints.RolePermissionMatrix;
using KLOP.Platform.Api.Endpoints.System;
using KLOP.Platform.Api.Endpoints.Tenants;
using KLOP.Platform.Application;

namespace KLOP.Platform.Api.Endpoints;

public static class PlatformEndpointMappings
{
    public static void MapPlatformEndpoints(this WebApplication app, IPlatformRuntimeSettings settings)
    {
        SystemEndpoints.MapSystemEndpoints(app);
        var api = app.MapGroup("/api/v1")
            .AddEndpointFilter<ValidationFilter>();
        MasterEndpoints.MapMasterEndpoints(api);
        AuthenticationEndpoints.MapAuthenticationEndpoints(api, settings);
        PublicLegalEndpoints.MapPublicLegalEndpoints(api);
        if (app.Configuration.GetValue<bool>("PlatformLegalDocuments:AdministrationEnabled"))
            PlatformLegalDocumentEndpoints.MapPlatformLegalDocumentEndpoints(api);
        OnboardingEndpoints.MapOnboardingEndpoints(api);
        PlatformRegistrationEndpoints.MapPlatformRegistrationEndpoints(api);
        RolePermissionMatrixEndpoints.MapRolePermissionMatrixEndpoints(api);
        TenantEndpoints.MapTenantEndpoints(api);
    }
}