using System.Text.Json;
using KLOP.Platform.Infrastructure;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace KLOP.Platform.Api.Endpoints.System;

public static class SystemHandlers
{
    public static IResult Live() => Results.Json(new { status = "live" });

    public static async Task WriteReadinessResponse(HttpContext context, HealthReport report)
    {
        context.Response.ContentType = "application/json";
        await JsonSerializer.SerializeAsync(context.Response.Body,
            new { status = report.Status.ToString().ToLowerInvariant() },
            cancellationToken: context.RequestAborted);
    }

    public static IResult PublicJwks(KeyMaterial key) => Results.Json(key.PublicJwks());
}