using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api.Endpoints.RolePermissionMatrix;

public static class RolePermissionMatrixEndpoints
{
    public static void MapRolePermissionMatrixEndpoints(RouteGroupBuilder api)
    {
        var matrix = api.MapGroup("/platform/role-permissions")
            .RequireAuthorization()
            .WithTags("Platform Role & Permission Matrix");

        matrix.MapGet("/access", RolePermissionMatrixHandlers.Access)
            .WithSummary("Get the caller's effective matrix access capabilities")
            .Produces<ApiEnvelope<RolePermissionMatrixAccessResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        matrix.MapGet("/matrix", RolePermissionMatrixHandlers.Get)
            .RequirePlatformPermission(RolePermissionMatrixPermissions.Read)
            .WithSummary("Load the database-backed unified role and permission matrix")
            .Produces<ApiEnvelope<RolePermissionMatrixResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        matrix.MapGet("/history", RolePermissionMatrixHandlers.History)
            .RequirePlatformPermission(RolePermissionMatrixPermissions.Read)
            .WithSummary("View permission grant change history")
            .Produces<ApiEnvelope<IReadOnlyList<RolePermissionMatrixHistoryEntry>>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        matrix.MapPost("/changes/validate", RolePermissionMatrixHandlers.Validate)
            .RequirePlatformPermission(RolePermissionMatrixPermissions.Update)
            .WithSummary("Validate a proposed role permission batch without applying it")
            .Produces<ApiEnvelope<RolePermissionMatrixValidationResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);

        matrix.MapPost("/changes", RolePermissionMatrixHandlers.Save)
            .RequirePlatformPermission(RolePermissionMatrixPermissions.Update)
            .WithSummary("Atomically save a validated role permission batch")
            .Produces<ApiEnvelope<RolePermissionMatrixSaveResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict);
    }
}

public static class RolePermissionMatrixHandlers
{
    public static async Task<IResult> Access(
        HttpContext context, RolePermissionMatrixService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        return ApiHelpers.Success(context, await service.GetAccess(
            identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> Get(
        HttpContext context, RolePermissionMatrixService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        return ApiHelpers.Success(context,
            await service.Get(identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> History(
        HttpContext context, RolePermissionMatrixService service,
        CancellationToken cancellationToken, int pageNumber = 1, int pageSize = 20)
    {
        if (pageNumber is < 1 or > 100_000 || pageSize is < 1 or > 100)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_PAGE", "The history page request is invalid.");
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        return ApiHelpers.Success(context, await service.History(identity.Value.UserId,
            identity.Value.SessionId, pageNumber, pageSize, cancellationToken));
    }

    public static async Task<IResult> Validate(
        RolePermissionMatrixBatchRequest request, HttpContext context,
        RolePermissionMatrixService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        try
        {
            return ApiHelpers.Success(context, await service.Validate(identity.Value.UserId,
                identity.Value.SessionId, request, cancellationToken));
        }
        catch (ArgumentException exception)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_PERMISSION_BATCH", exception.Message);
        }
        catch (FormatException)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_PERMISSION_BATCH", "A concurrency version is invalid.");
        }
    }

    public static async Task<IResult> Save(
        RolePermissionMatrixBatchRequest request, HttpContext context,
        RolePermissionMatrixService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        try
        {
            return ApiHelpers.Success(context, await service.Save(identity.Value.UserId,
                identity.Value.SessionId, request, ApiHelpers.Metadata(context), cancellationToken));
        }
        catch (ArgumentException exception)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_PERMISSION_BATCH", exception.Message);
        }
        catch (FormatException)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_PERMISSION_BATCH", "A concurrency version is invalid.");
        }
        catch (SqlException exception) when (exception.Number == 52990)
        {
            return ApiHelpers.Error(context, StatusCodes.Status409Conflict,
                "PERMISSION_BATCH_REJECTED", "One or more permission changes violate the current policy.");
        }
        catch (SqlException exception) when (exception.Number == 52991)
        {
            return ApiHelpers.Error(context, StatusCodes.Status409Conflict,
                "STALE_PERMISSION_MATRIX", "The matrix changed after it was loaded. Reload and review the current values.");
        }
    }
}
