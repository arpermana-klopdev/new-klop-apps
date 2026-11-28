using KLOP.Platform.Application;
using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Mvc;

namespace KLOP.Platform.Api.Endpoints.SystemConfiguration;

public static class SystemConfigurationEndpoints
{
    public static void MapSystemConfigurationEndpoints(RouteGroupBuilder api)
    {
        var configurations = api.MapGroup("/platform/configurations")
            .RequireAuthorization()
            .WithTags("Platform System Configuration");

        configurations.MapGet("/permissions", SystemConfigurationHandlers.Permissions)
            .WithSummary("Discover effective configuration-management capabilities")
            .Produces<ApiEnvelope<SystemConfigurationAccessResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized);

        configurations.MapGet("/catalog", SystemConfigurationHandlers.Catalog)
            .RequirePlatformPermission(SystemConfigurationPermissions.Read)
            .WithSummary("Read the explicitly classified safe configuration catalog")
            .Produces<ApiEnvelope<SystemConfigurationCatalogPage>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        configurations.MapGet("/requests", SystemConfigurationHandlers.Requests)
            .RequirePlatformPermission(SystemConfigurationPermissions.Read)
            .WithSummary("List configuration change requests without exposing configuration values")
            .Produces<ApiEnvelope<SystemConfigurationRequestPage>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        configurations.MapGet("/approvals", SystemConfigurationHandlers.Approvals)
            .RequirePlatformPermission(SystemConfigurationPermissions.Approve)
            .WithSummary("List submitted configuration requests awaiting an independent decision")
            .Produces<ApiEnvelope<SystemConfigurationRequestPage>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        configurations.MapGet("/history", SystemConfigurationHandlers.History)
            .RequirePlatformPermission(SystemConfigurationPermissions.History)
            .WithSummary("Read deterministic applied configuration history")
            .Produces<ApiEnvelope<SystemConfigurationHistoryPage>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        configurations.MapPost("/requests", SystemConfigurationHandlers.CreateDraft)
            .RequirePlatformPermission(SystemConfigurationPermissions.RequestCreate)
            .WithSummary("Create a draft for the explicitly supported bounded integer candidate")
            .Produces<ApiEnvelope<SystemConfigurationDraftResult>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);

        configurations.MapPut("/requests/{requestId:guid}", SystemConfigurationHandlers.UpdateDraft)
            .RequirePlatformPermission(SystemConfigurationPermissions.RequestEdit)
            .WithSummary("Update an unsubmitted configuration request")
            .Produces<ApiEnvelope<SystemConfigurationDraftResult>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);

        configurations.MapPost("/requests/{requestId:guid}/submit", SystemConfigurationHandlers.Submit)
            .RequirePlatformPermission(SystemConfigurationPermissions.Submit)
            .WithSummary("Submit a configuration request for independent approval")
            .Produces<ApiEnvelope<SystemConfigurationDraftResult>>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);

        configurations.MapPost("/requests/{requestId:guid}/approval", SystemConfigurationHandlers.Decide)
            .RequirePlatformPermission(SystemConfigurationPermissions.Approve)
            .WithSummary("Approve or reject a submitted configuration request")
            .Produces<ApiEnvelope<SystemConfigurationDraftResult>>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);

        configurations.MapPost("/requests/{requestId:guid}/cancel", SystemConfigurationHandlers.Cancel)
            .RequirePlatformPermission(SystemConfigurationPermissions.Cancel)
            .WithSummary("Cancel an owned draft or submitted configuration request")
            .Produces<ApiEnvelope<SystemConfigurationDraftResult>>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);

        configurations.MapPost("/requests/{requestId:guid}/apply", SystemConfigurationHandlers.Apply)
            .RequirePlatformPermission(SystemConfigurationPermissions.Apply)
            .WithSummary("Apply an approved configuration request exactly once")
            .Produces<ApiEnvelope<SystemConfigurationDraftResult>>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);
    }
}

public sealed record SystemConfigurationAccessResponse(
    bool CanRead,
    bool CanCreateRequest,
    bool CanEditRequest,
    bool CanSubmit,
    bool CanCancel,
    bool CanApprove,
    bool CanApply,
    bool CanReadHistory);

public static class SystemConfigurationHandlers
{
    public static async Task<IResult> Permissions(
        HttpContext context, [FromServices] IPlatformPermissionRepository repository,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var effective = await repository.GetPlatformPermissions(
            identity.Value.UserId, identity.Value.SessionId, cancellationToken);
        return ApiHelpers.Success(context, new SystemConfigurationAccessResponse(
            effective.Contains(SystemConfigurationPermissions.Read, StringComparer.Ordinal),
            effective.Contains(SystemConfigurationPermissions.RequestCreate, StringComparer.Ordinal),
            effective.Contains(SystemConfigurationPermissions.RequestEdit, StringComparer.Ordinal),
            effective.Contains(SystemConfigurationPermissions.Submit, StringComparer.Ordinal),
            effective.Contains(SystemConfigurationPermissions.Cancel, StringComparer.Ordinal),
            effective.Contains(SystemConfigurationPermissions.Approve, StringComparer.Ordinal),
            effective.Contains(SystemConfigurationPermissions.Apply, StringComparer.Ordinal),
            effective.Contains(SystemConfigurationPermissions.History, StringComparer.Ordinal)));
    }

    public static async Task<IResult> Catalog(
        HttpContext context, [FromServices] SystemConfigurationService service, CancellationToken cancellationToken,
        string? category = null, int pageNumber = 1, int pageSize = 25) =>
        await Read(context, async identity => await service.Catalog(category, pageNumber, pageSize,
            identity.UserId, identity.SessionId, cancellationToken));

    public static async Task<IResult> Requests(
        HttpContext context, [FromServices] SystemConfigurationService service, CancellationToken cancellationToken,
        string status = "ALL", int pageNumber = 1, int pageSize = 25) =>
        await Read(context, async identity => await service.Requests(status, pageNumber, pageSize,
            identity.UserId, identity.SessionId, cancellationToken));

    public static async Task<IResult> Approvals(
        HttpContext context, [FromServices] SystemConfigurationService service, CancellationToken cancellationToken,
        int pageNumber = 1, int pageSize = 25) =>
        await Read(context, async identity => await service.Approvals(pageNumber, pageSize,
            identity.UserId, identity.SessionId, cancellationToken));

    public static async Task<IResult> History(
        HttpContext context, [FromServices] SystemConfigurationService service, CancellationToken cancellationToken,
        int pageNumber = 1, int pageSize = 25) =>
        await Read(context, async identity => await service.History(pageNumber, pageSize,
            identity.UserId, identity.SessionId, cancellationToken));

    public static async Task<IResult> CreateDraft(
        SystemConfigurationDraftRequest request, HttpContext context,
        [FromServices] SystemConfigurationService service, CancellationToken cancellationToken) =>
        await Mutate(context, identity => service.CreateDraft(request, identity.UserId, identity.SessionId,
            ApiHelpers.Metadata(context), cancellationToken));

    public static async Task<IResult> UpdateDraft(
        Guid requestId, SystemConfigurationDraftUpdate request, HttpContext context,
        [FromServices] SystemConfigurationService service, CancellationToken cancellationToken) =>
        await Mutate(context, identity => service.UpdateDraft(requestId, request, identity.UserId,
            identity.SessionId, ApiHelpers.Metadata(context), cancellationToken));

    public static async Task<IResult> Submit(
        Guid requestId, SystemConfigurationTransitionRequest request, HttpContext context,
        [FromServices] SystemConfigurationService service, CancellationToken cancellationToken) =>
        await Transition(requestId, "SUBMIT", new SystemConfigurationDecisionRequest("SUBMIT",
            request.RequestConcurrencyVersion), context, service, cancellationToken);

    public static async Task<IResult> Decide(
        Guid requestId, SystemConfigurationDecisionRequest request, HttpContext context,
        [FromServices] SystemConfigurationService service, CancellationToken cancellationToken) =>
        await Transition(requestId, "APPROVAL", request, context, service, cancellationToken);

    public static async Task<IResult> Cancel(
        Guid requestId, SystemConfigurationTransitionRequest request, HttpContext context,
        [FromServices] SystemConfigurationService service, CancellationToken cancellationToken) =>
        await Transition(requestId, "CANCEL", new SystemConfigurationDecisionRequest("CANCEL",
            request.RequestConcurrencyVersion), context, service, cancellationToken);

    public static async Task<IResult> Apply(
        Guid requestId, SystemConfigurationTransitionRequest request, HttpContext context,
        [FromServices] SystemConfigurationService service, CancellationToken cancellationToken) =>
        await Mutate(context, identity => service.Apply(requestId, request, identity.UserId,
            identity.SessionId, ApiHelpers.Metadata(context), cancellationToken));

    private static async Task<IResult> Transition(
        Guid requestId, string action, SystemConfigurationDecisionRequest request, HttpContext context,
        [FromServices] SystemConfigurationService service, CancellationToken cancellationToken) =>
        await Mutate(context, identity => service.Transition(requestId, action, request, identity.UserId,
            identity.SessionId, ApiHelpers.Metadata(context), cancellationToken));

    private static async Task<IResult> Read<T>(
        HttpContext context, Func<(long UserId, Guid SessionId), Task<T>> action)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        try
        {
            return ApiHelpers.Success(context, await action(identity.Value));
        }
        catch (ArgumentException)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_CONFIGURATION_QUERY", "The configuration query is invalid.");
        }
        catch (SqlException exception) when (exception.Number == 52332 || exception.Number is >= 53590 and <= 53599)
        {
            return ApiHelpers.Error(context, StatusCodes.Status403Forbidden,
                "CONFIGURATION_ACCESS_DENIED", "Configuration access is not available.");
        }
    }

    private static async Task<IResult> Mutate(
        HttpContext context, Func<(long UserId, Guid SessionId), Task<SystemConfigurationDraftResult>> action)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        try
        {
            return ApiHelpers.Success(context, await action(identity.Value));
        }
        catch (ArgumentException)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_CONFIGURATION_REQUEST", "The configuration request is invalid.");
        }
        catch (SqlException exception) when (exception.Number == 52332 || exception.Number is >= 53590 and <= 53599)
        {
            var statusCode = exception.Number == 52332
                ? StatusCodes.Status403Forbidden
                : StatusCodes.Status409Conflict;
            return ApiHelpers.Error(context, statusCode,
                exception.Number == 52332 ? "CONFIGURATION_ACCESS_DENIED" : "CONFIGURATION_CHANGE_REJECTED",
                exception.Number == 52332
                    ? "Configuration access is not available."
                    : "The configuration change conflicts with current policy or data.");
        }
    }
}
