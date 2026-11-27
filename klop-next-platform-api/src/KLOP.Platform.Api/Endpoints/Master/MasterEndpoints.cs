using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Master;

public static class MasterEndpoints
{
    public static void MapMasterEndpoints(RouteGroupBuilder api)
    {
        api.MapGet("/master/organization-types", MasterHandlers.ListOrganizationTypes)
            .WithTags("Master Data")
            .WithSummary("List organization types")
            .Produces<ApiEnvelope<IReadOnlyList<OrganizationType>>>();
        api.MapGet("/master/tenant-types", MasterHandlers.ListTenantTypes)
            .WithTags("Master Data")
            .WithSummary("List active tenant types")
            .Produces<ApiEnvelope<IReadOnlyList<TenantTypeReference>>>();
    }
}