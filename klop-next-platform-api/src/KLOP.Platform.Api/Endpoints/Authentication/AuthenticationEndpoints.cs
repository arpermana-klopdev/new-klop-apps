using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Authentication;

public static class AuthenticationEndpoints
{
    public static void MapAuthenticationEndpoints(RouteGroupBuilder api, IPlatformRuntimeSettings settings)
    {
        var auth = api.MapGroup("/auth").WithTags("Authentication");
        auth.MapGet("/registration-policy", AuthenticationHandlers.RegistrationPolicy)
            .RequireRateLimiting("auth")
            .WithSummary("Get effective public registration requirements")
            .Produces<ApiEnvelope<RegistrationPolicyResponse>>()
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        var register = settings.DevelopmentTermsBypassEnabled
            ? auth.MapPost("/register", AuthenticationHandlers.RegisterDirect)
            : auth.MapPost("/register", AuthenticationHandlers.RegisterTermsRequired);
        register
            .RequireRateLimiting("auth")
            .WithSummary("Register a local user")
            .WithDescription("If accepted, email verification instructions are sent without disclosing account existence.")
            .Produces<ApiEnvelope<MessageResponse>>(StatusCodes.Status202Accepted)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        auth.MapPost("/resend-verification", AuthenticationHandlers.ResendVerification)
            .RequireRateLimiting("auth")
            .WithSummary("Resend email verification instructions")
            .Produces<ApiEnvelope<MessageResponse>>(StatusCodes.Status202Accepted)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        auth.MapPost("/verify-email", AuthenticationHandlers.VerifyEmail)
            .RequireRateLimiting("auth")
            .WithSummary("Verify an email address")
            .Produces<ApiEnvelope<VerifiedResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        auth.MapPost("/login", AuthenticationHandlers.Login)
            .RequireRateLimiting("auth")
            .WithSummary("Log in")
            .WithDescription("Returns an access token and sets the refresh cookie for an eligible account.")
            .Produces<ApiEnvelope<AccessResult>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        auth.MapPost("/refresh", AuthenticationHandlers.Refresh)
            .RequireRateLimiting("auth")
            .WithSummary("Refresh an access token")
            .WithDescription("Requires the refresh cookie and the configured Origin header; does not require a bearer token.")
            .Produces<ApiEnvelope<AccessResult>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        auth.MapPost("/logout", AuthenticationHandlers.Logout)
            .RequireAuthorization()
            .WithSummary("Log out the current session")
            .Produces<ApiEnvelope<LoggedOutResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized);

        auth.MapGet("/me", AuthenticationHandlers.Me)
            .RequireAuthorization()
            .WithSummary("Get the current user profile")
            .Produces<ApiEnvelope<Profile>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound);
    }
}