using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.AspNetCore.Mvc;

namespace KLOP.Platform.Api.Endpoints.Registrations;

public sealed record PlatformRegistrationListParameters(
    string? RegistrationType,
    string? Search,
    string? EmailVerificationStatus,
    string? ApplicationStatus,
    int PageNumber = 1,
    int PageSize = 20);

public static class PlatformRegistrationEndpoints
{
    public static void MapPlatformRegistrationEndpoints(RouteGroupBuilder api)
    {
        api.MapGet("/platform/registrations/permissions", PlatformRegistrationHandlers.Permissions)
            .RequireAuthorization()
            .WithTags("Platform Registrations")
            .WithSummary("Get the authenticated user's effective registration permissions")
            .Produces<ApiEnvelope<PlatformRegistrationPermissionsResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        var registrations = api.MapGroup("/platform/registrations")
            .RequireAuthorization()
            .RequirePlatformPermission(PlatformRegistrationPermissions.Read)
            .WithTags("Platform Registrations");

        registrations.MapGet("/summary", PlatformRegistrationHandlers.Summary)
            .WithSummary("Get registration summary counts by registration type")
            .Produces<ApiEnvelope<PlatformRegistrationSummary>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        registrations.MapGet("", PlatformRegistrationHandlers.List)
            .WithSummary("Search and page registration applications")
            .Produces<ApiEnvelope<PlatformRegistrationPage>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        registrations.MapGet("/{registrationApplicationId:long}", PlatformRegistrationHandlers.Get)
            .WithSummary("Get registration application details")
            .Produces<ApiEnvelope<PlatformRegistrationDetail>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        registrations.MapGet("/{registrationApplicationId:long}/timeline", PlatformRegistrationHandlers.Timeline)
            .WithSummary("Get persisted registration and verification timeline events")
            .Produces<ApiEnvelope<IReadOnlyList<PlatformRegistrationTimelineEvent>>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
    }
}
