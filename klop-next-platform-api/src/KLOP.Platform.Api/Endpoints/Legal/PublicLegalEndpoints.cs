using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Legal;

public static class PublicLegalEndpoints
{
    public static void MapPublicLegalEndpoints(RouteGroupBuilder api)
    {
        var terms = api.MapGroup("/public/legal/terms").WithTags("Public Legal Documents");
        terms.MapGet("/current", PublicLegalHandlers.Current)
            .WithSummary("Get current published Terms and Conditions for registration")
            .Produces<ApiEnvelope<LegalTermsMetadata>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        terms.MapGet("/{documentVersionId:guid}/file", PublicLegalHandlers.File)
            .WithSummary("Get a published Terms and Conditions PDF")
            .Produces(StatusCodes.Status200OK, contentType: "application/pdf")
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
    }
}
