using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

namespace KLOP.Platform.Api;

internal sealed class HealthReadinessDocumentTransformer : IOpenApiDocumentTransformer
{
    public async Task TransformAsync(OpenApiDocument document, OpenApiDocumentTransformerContext context,
        CancellationToken cancellationToken)
    {
        var endpoints = context.ApplicationServices.GetRequiredService<EndpointDataSource>().Endpoints;
        if (!endpoints.OfType<RouteEndpoint>().Any(endpoint => endpoint.RoutePattern.RawText == "/health/ready"))
            return;

        var schema = await context.GetOrCreateSchemaAsync(typeof(HealthResponse), cancellationToken: cancellationToken);
        OpenApiResponse Response(string description) => new()
        {
            Description = description,
            Content = new Dictionary<string, OpenApiMediaType>
            {
                ["application/json"] = new() { Schema = schema }
            }
        };

        // Health-check middleware has no HTTP method metadata, so API Explorer omits it.
        document.Paths["/health/ready"] = new OpenApiPathItem
        {
            Operations = new Dictionary<HttpMethod, OpenApiOperation>
            {
                [HttpMethod.Get] = new()
                {
                    Summary = "Check SQL readiness",
                    Description = "Reports healthy, degraded or unhealthy without exposing dependency details.",
                    Tags = new HashSet<OpenApiTagReference> { new("Health", document) },
                    Responses = new OpenApiResponses
                    {
                        ["200"] = Response("Healthy"),
                        ["503"] = Response("Degraded or unhealthy")
                    }
                }
            }
        };
    }
}
