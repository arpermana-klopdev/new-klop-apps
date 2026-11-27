using KLOP.Platform.Api.Logging;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace KLOP.Platform.Api.Endpoints.System;

public static class SystemEndpoints
{
    public static void MapSystemEndpoints(WebApplication app)
    {
        app.MapGet("/health/live", SystemHandlers.Live)
            .AllowAnonymous()
            .WithMetadata(new RoutineHealthCheckLoggingMetadata())
            .WithTags("Health")
            .WithSummary("Check process liveness")
            .Produces<HealthResponse>();
        app.MapHealthChecks("/health/ready", new HealthCheckOptions
        {
            Predicate = check => check.Tags.Contains("ready"),
            ResultStatusCodes =
            {
                [HealthStatus.Healthy] = StatusCodes.Status200OK,
                [HealthStatus.Degraded] = StatusCodes.Status503ServiceUnavailable,
                [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
            },
            ResponseWriter = SystemHandlers.WriteReadinessResponse
        }).AllowAnonymous()
            .WithMetadata(new RoutineHealthCheckLoggingMetadata())
            .WithTags("Health");
        app.MapGet("/.well-known/jwks.json", SystemHandlers.PublicJwks)
            .AllowAnonymous()
            .WithTags("Authentication")
            .WithSummary("Get public signing keys")
            .Produces<JwksResponse>();
    }
}