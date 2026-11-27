using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Master;

public static class MasterHandlers
{
    public static async Task<IResult> ListOrganizationTypes(
        HttpContext context,
        IPlatformRepository repository,
        CancellationToken cancellationToken) =>
        ApiHelpers.Success(context, await repository.OrganizationTypes(cancellationToken));
}