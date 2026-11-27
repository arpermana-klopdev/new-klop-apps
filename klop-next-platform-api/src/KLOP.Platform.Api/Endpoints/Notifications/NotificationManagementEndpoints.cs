using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api.Endpoints.Notifications;

public sealed record CreateNotificationTemplateRequest(
    string TemplateCode, string DisplayName, string ChannelCode, string LocaleCode, string Subject, string Body);

public static class NotificationManagementEndpoints
{
    public static void MapNotificationManagementEndpoints(RouteGroupBuilder api)
    {
        var notifications = api.MapGroup("/platform/notifications")
            .RequireAuthorization()
            .WithTags("Platform Notifications");

        notifications.MapGet("/permissions", NotificationManagementHandlers.Permissions)
            .WithSummary("Get the caller's effective notification permissions")
            .Produces<ApiEnvelope<NotificationPermissionsResponse>>();

        notifications.MapGet("/templates", NotificationManagementHandlers.Templates)
            .RequirePlatformPermission(NotificationPermissions.Read)
            .WithSummary("List notification templates and active versions")
            .Produces<ApiEnvelope<IReadOnlyList<NotificationTemplateSummary>>>();
        notifications.MapGet("/templates/{templateId:guid}", NotificationManagementHandlers.Template)
            .RequirePlatformPermission(NotificationPermissions.Read)
            .WithSummary("Get notification template details and version history")
            .Produces<ApiEnvelope<NotificationTemplateDetail>>();
        notifications.MapPost("/templates", NotificationManagementHandlers.CreateDraft)
            .RequirePlatformPermission(NotificationPermissions.DraftCreate)
            .WithSummary("Create a notification template draft")
            .Produces<ApiEnvelope<NotificationTemplateDraftResult>>(StatusCodes.Status201Created);
        notifications.MapPut("/versions/{versionId:guid}", NotificationManagementHandlers.UpdateDraft)
            .RequirePlatformPermission(NotificationPermissions.DraftEdit)
            .WithSummary("Edit a notification template draft using optimistic concurrency")
            .Produces<ApiEnvelope<NotificationTemplateDraftResult>>();
        notifications.MapPost("/versions/{versionId:guid}/preview", NotificationManagementHandlers.Preview)
            .RequirePlatformPermission(NotificationPermissions.Preview)
            .WithSummary("Render a notification draft with synthetic preview values only")
            .Produces<ApiEnvelope<NotificationTemplatePreviewResponse>>();
        notifications.MapPost("/versions/{versionId:guid}/submit", NotificationManagementHandlers.Submit)
            .RequirePlatformPermission(NotificationPermissions.Submit)
            .WithSummary("Submit a notification template version for approval")
            .Produces<ApiEnvelope<IReadOnlyList<NotificationTemplateVersion>>>();
        notifications.MapPost("/versions/{versionId:guid}/approval", NotificationManagementHandlers.Decide)
            .RequirePlatformPermission(NotificationPermissions.Approve)
            .WithSummary("Approve or reject a submitted notification template version")
            .Produces<ApiEnvelope<IReadOnlyList<NotificationTemplateVersion>>>();
        notifications.MapPost("/versions/{versionId:guid}/activate", NotificationManagementHandlers.Activate)
            .RequirePlatformPermission(NotificationPermissions.Activate)
            .WithSummary("Activate an approved notification template version")
            .Produces<ApiEnvelope<IReadOnlyList<NotificationTemplateVersion>>>();
        notifications.MapPost("/versions/{versionId:guid}/archive", NotificationManagementHandlers.Archive)
            .RequirePlatformPermission(NotificationPermissions.Archive)
            .WithSummary("Archive a superseded notification template version")
            .Produces<ApiEnvelope<IReadOnlyList<NotificationTemplateVersion>>>();

        notifications.MapGet("/channels", NotificationManagementHandlers.Channels)
            .RequirePlatformPermission(NotificationPermissions.Read)
            .WithSummary("List database-backed notification channels and readiness")
            .Produces<ApiEnvelope<IReadOnlyList<NotificationChannelStatus>>>();
        notifications.MapGet("/history", NotificationManagementHandlers.History)
            .RequirePlatformPermission(NotificationPermissions.History)
            .WithSummary("List paginated notification delivery history")
            .Produces<ApiEnvelope<NotificationDeliveryHistoryPage>>();
        notifications.MapGet("/settings/readiness", NotificationManagementHandlers.SettingsReadiness)
            .RequirePlatformPermission(NotificationPermissions.SettingsRead)
            .WithSummary("Get safe SMTP and template rollout readiness metadata")
            .Produces<ApiEnvelope<NotificationSettingsReadiness>>();
    }
}

public static class NotificationManagementHandlers
{
    public static async Task<IResult> Permissions(
        HttpContext context, NotificationManagementService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context,
            await service.Permissions(identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> Templates(
        HttpContext context, NotificationManagementService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        return ApiHelpers.Success(context,
            await service.Templates(identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> Template(
        Guid templateId, HttpContext context, NotificationManagementService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        var result = await service.Template(templateId, identity.Value.UserId,
            identity.Value.SessionId, cancellationToken);
        return result is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "TEMPLATE_NOT_FOUND", "Template not found.")
            : ApiHelpers.Success(context, result);
    }

    public static async Task<IResult> CreateDraft(
        CreateNotificationTemplateRequest request, HttpContext context,
        NotificationManagementService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        try
        {
            var result = await service.CreateDraft(request.TemplateCode, request.DisplayName,
                request.ChannelCode, request.LocaleCode, request.Subject, request.Body,
                identity.Value.UserId, identity.Value.SessionId, ApiHelpers.Metadata(context), cancellationToken);
            return ApiHelpers.Success(context, result, StatusCodes.Status201Created);
        }
        catch (ArgumentException exception)
        {
            return Invalid(context, exception.Message);
        }
        catch (SqlException exception) when (exception.Number == 53201)
        {
            return Conflict(context);
        }
    }

    public static async Task<IResult> UpdateDraft(
        Guid versionId, NotificationTemplateDraftRequest request, HttpContext context,
        NotificationManagementService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        try
        {
            return ApiHelpers.Success(context, await service.UpdateDraft(versionId, request,
                identity.Value.UserId, identity.Value.SessionId, ApiHelpers.Metadata(context), cancellationToken));
        }
        catch (ArgumentException exception)
        {
            return Invalid(context, exception.Message);
        }
        catch (SqlException exception) when (exception.Number == 53201)
        {
            return Conflict(context);
        }
    }

    public static async Task<IResult> Preview(
        Guid versionId, HttpContext context, NotificationManagementService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        try
        {
            var preview = await service.Preview(versionId, identity.Value.UserId,
                identity.Value.SessionId, cancellationToken);
            return preview is null
                ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "VERSION_NOT_FOUND", "Version not found.")
                : ApiHelpers.Success(context, preview);
        }
        catch (ArgumentException exception)
        {
            return Invalid(context, exception.Message);
        }
    }

    public static Task<IResult> Submit(
        Guid versionId, NotificationDecisionRequest request, HttpContext context,
        NotificationManagementService service, CancellationToken cancellationToken) =>
        Transition(versionId, "submit", request, context, service, cancellationToken);

    public static Task<IResult> Decide(
        Guid versionId, NotificationDecisionRequest request, HttpContext context,
        NotificationManagementService service, CancellationToken cancellationToken) =>
        Transition(versionId, "approve", request, context, service, cancellationToken);

    public static Task<IResult> Activate(
        Guid versionId, NotificationDecisionRequest request, HttpContext context,
        NotificationManagementService service, CancellationToken cancellationToken) =>
        Transition(versionId, "activate", request, context, service, cancellationToken);

    public static Task<IResult> Archive(
        Guid versionId, NotificationDecisionRequest request, HttpContext context,
        NotificationManagementService service, CancellationToken cancellationToken) =>
        Transition(versionId, "archive", request, context, service, cancellationToken);

    public static async Task<IResult> Channels(
        HttpContext context, NotificationManagementService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        return ApiHelpers.Success(context,
            await service.Channels(identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> History(
        HttpContext context, NotificationManagementService service, CancellationToken cancellationToken,
        int pageNumber = 1, int pageSize = 20)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        try
        {
            return ApiHelpers.Success(context, await service.History(pageNumber, pageSize,
                identity.Value.UserId, identity.Value.SessionId, cancellationToken));
        }
        catch (ArgumentOutOfRangeException)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_PAGE", "The history page request is invalid.");
        }
    }

    public static async Task<IResult> SettingsReadiness(
        HttpContext context, NotificationManagementService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        return ApiHelpers.Success(context, await service.SettingsReadiness(identity.Value.UserId,
            identity.Value.SessionId, cancellationToken));
    }

    private static async Task<IResult> Transition(
        Guid versionId, string action, NotificationDecisionRequest request, HttpContext context,
        NotificationManagementService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return Unauthorized(context);
        try
        {
            var rows = await service.Transition(versionId, action, request, identity.Value.UserId,
                identity.Value.SessionId, ApiHelpers.Metadata(context), cancellationToken);
            return rows.Count == 0
                ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "VERSION_NOT_FOUND", "Version not found.")
                : ApiHelpers.Success(context, rows);
        }
        catch (ArgumentException exception)
        {
            return Invalid(context, exception.Message);
        }
        catch (SqlException exception) when (exception.Number == 53201)
        {
            return Conflict(context);
        }
    }

    private static IResult Unauthorized(HttpContext context) =>
        ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

    private static IResult Invalid(HttpContext context, string message) =>
        ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "INVALID_NOTIFICATION_REQUEST", message);

    private static IResult Conflict(HttpContext context) =>
        ApiHelpers.Error(context, StatusCodes.Status409Conflict,
            "NOTIFICATION_VERSION_CONFLICT", "The notification version changed or cannot make this transition.");
}
