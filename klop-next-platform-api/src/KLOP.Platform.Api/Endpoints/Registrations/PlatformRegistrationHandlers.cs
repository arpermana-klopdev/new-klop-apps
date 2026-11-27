using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api.Endpoints.Registrations;

public static class PlatformRegistrationHandlers
{
    public static async Task<IResult> Permissions(HttpContext context,
        PlatformRegistrationPermissionService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        return ApiHelpers.Success(context,
            await service.Get(identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> Summary(string? registrationType, HttpContext context,
        PlatformRegistrationService service, CancellationToken cancellationToken)
    {
        if (!RegistrationTypeCodes.IsSupported(registrationType))
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_REGISTRATION_TYPE", "A supported registration type is required.");
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        var summary = await service.GetSummary(registrationType!, identity.Value.UserId, identity.Value.SessionId,
            cancellationToken);
        return summary is null
            ? ApiHelpers.Error(context, StatusCodes.Status503ServiceUnavailable,
                "REGISTRATION_SERVICE_UNAVAILABLE", "Registration summary is unavailable.")
            : ApiHelpers.Success(context, summary);
    }

    public static async Task<IResult> List([AsParameters] PlatformRegistrationListParameters parameters,
        HttpContext context, PlatformRegistrationService service, CancellationToken cancellationToken)
    {
        if (!RegistrationTypeCodes.IsSupported(parameters.RegistrationType))
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_REGISTRATION_TYPE", "A supported registration type is required.");
        if (parameters.Search?.Length > 200)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_SEARCH", "The registration search term must be 200 characters or fewer.");
        if (!string.IsNullOrWhiteSpace(parameters.EmailVerificationStatus) &&
            !new[] { "PENDING", "VERIFIED" }.Contains(
                parameters.EmailVerificationStatus.Trim(), StringComparer.OrdinalIgnoreCase))
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_EMAIL_VERIFICATION_FILTER", "The email verification filter is invalid.");
        if (!string.IsNullOrWhiteSpace(parameters.ApplicationStatus) &&
            parameters.ApplicationStatus.Trim().Length > 30)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_APPLICATION_STATUS", "The application status filter is invalid.");
        if (parameters.PageNumber is < 1 or > 1_000_000 ||
            parameters.PageSize is < 1 or > 100)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_PAGE", "Page number must be between 1 and 1000000, and page size between 1 and 100.");

        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        try
        {
            var result = await service.List(new PlatformRegistrationListQuery
            {
                RegistrationType = parameters.RegistrationType!,
                Search = parameters.Search,
                EmailVerificationStatus = parameters.EmailVerificationStatus,
                ApplicationStatus = parameters.ApplicationStatus,
                PageNumber = parameters.PageNumber,
                PageSize = parameters.PageSize
            }, identity.Value.UserId, identity.Value.SessionId, cancellationToken);
            return ApiHelpers.Success(context, result);
        }
        catch (SqlException exception) when (exception.Number == 52912)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_APPLICATION_STATUS", "The application status filter is invalid.");
        }
    }

    public static async Task<IResult> Get(long registrationApplicationId, HttpContext context,
        PlatformRegistrationService service, CancellationToken cancellationToken)
    {
        if (registrationApplicationId < 1)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_REGISTRATION_ID", "The registration application identifier is invalid.");
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        var detail = await service.Get(registrationApplicationId, identity.Value.UserId, identity.Value.SessionId,
            cancellationToken);
        return detail is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound,
                "REGISTRATION_NOT_FOUND", "The registration application is unavailable.")
            : ApiHelpers.Success(context, detail);
    }

    public static async Task<IResult> Timeline(long registrationApplicationId, HttpContext context,
        PlatformRegistrationService service, CancellationToken cancellationToken)
    {
        if (registrationApplicationId < 1)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_REGISTRATION_ID", "The registration application identifier is invalid.");
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        try
        {
            return ApiHelpers.Success(context, await service.GetTimeline(registrationApplicationId,
                identity.Value.UserId, identity.Value.SessionId, cancellationToken));
        }
        catch (SqlException exception) when (exception.Number == 52916)
        {
            return ApiHelpers.Error(context, StatusCodes.Status404NotFound,
                "REGISTRATION_NOT_FOUND", "The registration application is unavailable.");
        }
    }
}
