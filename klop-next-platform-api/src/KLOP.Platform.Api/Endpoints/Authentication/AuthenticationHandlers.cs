using KLOP.Platform.Application;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api.Endpoints.Authentication;

public static class AuthenticationHandlers
{
    public static IResult RegistrationPolicy(HttpContext context, IPlatformRuntimeSettings settings)
    {
        context.Response.Headers.CacheControl = "no-store";
        return ApiHelpers.Success(context, RegistrationPolicyRules.GetEffective(settings));
    }

    public static Task<IResult> RegisterDirect(
        DirectRegistrationRequest request,
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken) =>
        Register(ToRegistrationCommand(request), context, service, cancellationToken);

    public static Task<IResult> RegisterTermsRequired(
        TermsRequiredRegistrationRequest request,
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken) =>
        Register(ToRegistrationCommand(request), context, service, cancellationToken);

    public static async Task<IResult> Register(
        RegistrationRequest request,
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken)
    {
        await service.Register(request, ApiHelpers.Metadata(context), cancellationToken);
        return ApiHelpers.Success(context,
            new { message = "If accepted, verification instructions will be emailed." },
            StatusCodes.Status202Accepted);
    }

    private static RegistrationRequest ToRegistrationCommand(DirectRegistrationRequest request) =>
        new(request.Email, request.DisplayName, request.Password)
        {
            RegistrationType = request.RegistrationType
        };

    private static RegistrationRequest ToRegistrationCommand(TermsRequiredRegistrationRequest request) =>
        new(request.Email, request.DisplayName, request.Password)
        {
            RegistrationType = request.RegistrationType,
            TermsDocumentVersionId = request.TermsDocumentVersionId,
            TermsAccepted = request.TermsAccepted
        };

    public static async Task<IResult> ResendVerification(
        ResendVerificationRequest request,
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken)
    {
        await service.ResendVerification(request, ApiHelpers.Metadata(context), cancellationToken);
        return ApiHelpers.Success(context,
            new { message = "If eligible, verification instructions will be emailed." },
            StatusCodes.Status202Accepted);
    }

    public static async Task<IResult> VerifyEmail(
        VerifyEmailRequest request,
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken)
    {
        await service.ConfirmEmail(request, ApiHelpers.Metadata(context), cancellationToken);
        return ApiHelpers.Success(context, new { verified = true });
    }

    public static async Task<IResult> Login(
        LoginRequest request,
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken)
    {
        var session = await service.Login(request, ApiHelpers.Metadata(context), cancellationToken);
        if (session is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized,
                "INVALID_CREDENTIALS", "Email or password is incorrect.");
        RefreshCookies.Set(context.Response, session);
        return ApiHelpers.Success(context, session.Access);
    }

    public static async Task<IResult> Refresh(
        HttpContext context,
        AuthenticationService service,
        IPlatformRuntimeSettings runtimeSettings,
        CancellationToken cancellationToken)
    {
        if (!ApiHelpers.SameOrigin(context, runtimeSettings))
            return ApiHelpers.Error(context, StatusCodes.Status403Forbidden, "ORIGIN_DENIED", "Origin not permitted.");
        var cookie = RefreshCookies.Read(context.Request);
        if (cookie is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized,
                "INVALID_CREDENTIALS", "Refresh required.");

        try
        {
            var session = await service.Refresh(cookie.Value.SessionId, cookie.Value.Token,
                ApiHelpers.Metadata(context), cancellationToken);
            RefreshCookies.Set(context.Response, session);
            return ApiHelpers.Success(context, session.Access);
        }
        catch (SqlException exception) when (exception.Number is 52342 or 52343 or 52344 or 52346 or 52347)
        {
            RefreshCookies.Clear(context.Response);
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized,
                "INVALID_CREDENTIALS", "Refresh not accepted.");
        }
    }

    public static async Task<IResult> Logout(
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        await service.Logout(identity.Value.UserId, identity.Value.SessionId,
            ApiHelpers.Metadata(context), cancellationToken);
        RefreshCookies.Clear(context.Response);
        return ApiHelpers.Success(context, new { loggedOut = true });
    }

    public static async Task<IResult> Me(
        HttpContext context,
        AuthenticationService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var profile = await service.GetProfile(identity.Value.UserId, cancellationToken);
        return profile is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "NOT_FOUND", "User unavailable.")
            : ApiHelpers.Success(context, profile);
    }
}