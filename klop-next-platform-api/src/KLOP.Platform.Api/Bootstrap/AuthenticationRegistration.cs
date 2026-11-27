using KLOP.Platform.Api;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.Tokens;

namespace KLOP.Platform.Api.Bootstrap;

public static class AuthenticationRegistration
{
    public static void AddPlatformAuthentication(
        this WebApplicationBuilder builder,
        IPlatformRuntimeSettings settings,
        KeyMaterial keyMaterial)
    {
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.MapInboundClaims = false;
                options.RequireHttpsMetadata = true;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = settings.JwtIssuer,
                    ValidateAudience = true,
                    ValidAudience = settings.JwtAudience,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = keyMaterial.SigningKey,
                    ValidateLifetime = true,
                    ClockSkew = TimeSpan.FromSeconds(30),
                    NameClaimType = "sub",
                    RoleClaimType = "role",
                    ValidAlgorithms = [SecurityAlgorithms.RsaSha256]
                };
                options.Events = new JwtBearerEvents
                {
                    OnTokenValidated = async context =>
                    {
                        var identity = context.Principal is { } principal
                            ? ApiHelpers.Identity(principal)
                            : null;
                        if (identity is null)
                        {
                            LogAuthenticationEvent(context.HttpContext, "SESSION_CLAIMS_INVALID");
                            context.Fail("Invalid session claims.");
                            return;
                        }

                        var repository = context.HttpContext.RequestServices.GetRequiredService<IPlatformRepository>();
                        try
                        {
                            await repository.ValidateSession(identity.Value.UserId, identity.Value.SessionId,
                                null, null, context.HttpContext.RequestAborted);
                        }
                        catch (SqlException exception) when (exception.Number == 52330)
                        {
                            LogAuthenticationEvent(context.HttpContext, "SESSION_INACTIVE");
                            context.Fail("Inactive session.");
                        }
                    },
                    OnAuthenticationFailed = context =>
                    {
                        var logger = CreateLogger(context.HttpContext);
                        logger.LogWarning(
                            "Bearer token validation failed. IsImportantProcessEvent={IsImportantProcessEvent} Component={Component} ResultCode={ResultCode} CorrelationId={CorrelationId} FailureType={FailureType}",
                            true, "Authentication", "AUTHENTICATION_FAILED",
                            ApiHelpers.Correlation(context.HttpContext).ToString("D"),
                            context.Exception.GetType().Name);
                        return Task.CompletedTask;
                    },
                    OnChallenge = async context =>
                    {
                        context.HandleResponse();
                        if (context.AuthenticateFailure is null)
                        {
                            var logger = CreateLogger(context.HttpContext);
                            logger.LogWarning(
                                "Bearer authentication challenge without a validation failure. IsImportantProcessEvent={IsImportantProcessEvent} Component={Component} ResultCode={ResultCode} CorrelationId={CorrelationId} AuthorizationHeaderPresent={AuthorizationHeaderPresent}",
                                true, "Authentication", "AUTHENTICATION_HEADER_MISSING",
                                ApiHelpers.Correlation(context.HttpContext).ToString("D"),
                                context.Request.Headers.ContainsKey("Authorization"));
                        }
                        await ApiHelpers.Error(context.HttpContext, StatusCodes.Status401Unauthorized,
                            "UNAUTHORIZED", "Authentication is required.").ExecuteAsync(context.HttpContext);
                    },
                    OnForbidden = async context =>
                    {
                        await ApiHelpers.Error(context.HttpContext, StatusCodes.Status403Forbidden,
                            "FORBIDDEN", "Operation is not permitted.").ExecuteAsync(context.HttpContext);
                    }
                };
            });
        builder.Services.AddAuthorization();
    }

    private static void LogAuthenticationEvent(HttpContext context, string resultCode)
    {
        var logger = CreateLogger(context);
        logger.LogWarning(
            "Bearer session validation rejected the request. IsImportantProcessEvent={IsImportantProcessEvent} Component={Component} ResultCode={ResultCode} CorrelationId={CorrelationId}",
            true, "Authentication", resultCode, ApiHelpers.Correlation(context).ToString("D"));
    }

    private static ILogger CreateLogger(HttpContext context) =>
        context.RequestServices.GetRequiredService<ILoggerFactory>()
            .CreateLogger(nameof(AuthenticationRegistration));
}