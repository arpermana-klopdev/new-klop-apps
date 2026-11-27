using System.Security.Cryptography;
using KLOP.Platform.Api;
using KLOP.Platform.Api.Endpoints;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using FluentValidation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class ApiRouteContractTests
{
    [Fact]
    public async Task PlatformLegalDocumentRoutesAreOmittedUnlessExplicitlyEnabled()
    {
        var builder = WebApplication.CreateBuilder();
        builder.Services.AddHealthChecks();
        builder.Services.AddAuthorization();
        builder.Services.AddSingleton(new KeyMaterial(RSA.Create(3072), "route-contract-test"));
        builder.Services.AddSingleton<IPlatformRepository>(_ => throw new InvalidOperationException());
        builder.Services.AddSingleton<IPlatformRuntimeSettings>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<AuthenticationService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<TenantManagementService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<TenantPermissionDiscoveryService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<LegalTermsService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<LegalDocumentsService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<OnboardingService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<PlatformRegistrationPermissionService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<PlatformRegistrationService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<RolePermissionMatrixService>(_ => throw new InvalidOperationException());
        await using var app = builder.Build();
        app.MapPlatformEndpoints(TestSettings());

        var routes = ((IEndpointRouteBuilder)app).DataSources
            .SelectMany(dataSource => dataSource.Endpoints)
            .OfType<RouteEndpoint>()
            .Select(GetRoute)
            .ToArray();

        Assert.DoesNotContain(routes, route =>
            route.Contains("/platform/legal-documents", StringComparison.Ordinal));
    }

    [Fact]
    public async Task EndpointModulesPreserveRouteMethodsAndSecurityMetadata()
    {
        var builder = WebApplication.CreateBuilder();
        builder.Configuration["PlatformLegalDocuments:AdministrationEnabled"] = "true";
        builder.Services.AddHealthChecks();
        builder.Services.AddAuthorization();
        builder.Services.AddSingleton(new KeyMaterial(RSA.Create(3072), "route-contract-test"));
        builder.Services.AddSingleton<IPlatformRepository>(_ => throw new InvalidOperationException());
        builder.Services.AddSingleton<IPlatformRuntimeSettings>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<AuthenticationService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<TenantManagementService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<TenantPermissionDiscoveryService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<LegalTermsService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<LegalDocumentsService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<OnboardingService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<PlatformRegistrationPermissionService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<PlatformRegistrationService>(_ => throw new InvalidOperationException());
        builder.Services.AddScoped<RolePermissionMatrixService>(_ => throw new InvalidOperationException());
        await using var app = builder.Build();
        app.MapPlatformEndpoints(TestSettings());

        var endpoints = ((IEndpointRouteBuilder)app).DataSources
            .SelectMany(dataSource => dataSource.Endpoints)
            .OfType<RouteEndpoint>()
            .ToDictionary(
                endpoint => $"{endpoint.Metadata.GetMetadata<IHttpMethodMetadata>()?.HttpMethods.SingleOrDefault() ?? "ALL"} {GetRoute(endpoint)}",
                endpoint => endpoint,
                StringComparer.Ordinal);

        string[] expectedRoutes =
        [
            "GET /health/live",
            "ALL /health/ready",
            "GET /.well-known/jwks.json",
            "GET /api/v1/master/organization-types",
            "GET /api/v1/public/legal/terms/current",
            "GET /api/v1/public/legal/terms/{documentVersionId:guid}/file",
            "GET /api/v1/platform/legal-documents/permissions",
            "GET /api/v1/platform/legal-documents/",
            "POST /api/v1/platform/legal-documents/",
            "GET /api/v1/platform/legal-documents/{legalDocumentId:guid}",
            "PUT /api/v1/platform/legal-documents/versions/{documentVersionId:guid}",
            "GET /api/v1/platform/legal-documents/versions/{documentVersionId:guid}/preview",
            "POST /api/v1/platform/legal-documents/versions/{documentVersionId:guid}/submit-for-approval",
            "POST /api/v1/platform/legal-documents/versions/{documentVersionId:guid}/approve",
            "POST /api/v1/platform/legal-documents/versions/{documentVersionId:guid}/publish",
            "POST /api/v1/platform/legal-documents/versions/{documentVersionId:guid}/archive",
            "POST /api/v1/auth/register",
            "GET /api/v1/auth/registration-policy",
            "POST /api/v1/auth/resend-verification",
            "POST /api/v1/auth/verify-email",
            "POST /api/v1/auth/login",
            "POST /api/v1/auth/refresh",
            "POST /api/v1/auth/logout",
            "GET /api/v1/auth/me",
            "GET /api/v1/onboarding/me",
            "PUT /api/v1/onboarding/personal/draft",
            "PUT /api/v1/onboarding/organization/draft",
            "GET /api/v1/onboarding/organization/requirements",
            "POST /api/v1/onboarding/submit",
            "GET /api/v1/onboarding/{applicationId:long}",
            "GET /api/v1/platform/registrations/summary",
            "GET /api/v1/platform/registrations/permissions",
            "GET /api/v1/platform/registrations/",
            "GET /api/v1/platform/registrations/{registrationApplicationId:long}",
            "GET /api/v1/platform/registrations/{registrationApplicationId:long}/timeline",
            "GET /api/v1/platform/role-permissions/access",
            "GET /api/v1/platform/role-permissions/matrix",
            "GET /api/v1/platform/role-permissions/history",
            "POST /api/v1/platform/role-permissions/changes/validate",
            "POST /api/v1/platform/role-permissions/changes",
            "GET /api/v1/tenants/mine",
            "GET /api/v1/tenants/{tenantId:long}/permissions",
            "POST /api/v1/tenants/",
            "POST /api/v1/tenants/{tenantId:long}/invitations",
            "POST /api/v1/tenants/memberships/{membershipId:long}/accept",
            "DELETE /api/v1/tenants/{tenantId:long}/memberships/{membershipId:long}",
            "POST /api/v1/tenants/{tenantId:long}/memberships/{membershipId:long}/roles",
            "DELETE /api/v1/tenants/{tenantId:long}/memberships/{membershipId:long}/roles/{roleCode}"
        ];

        Assert.Equal(expectedRoutes.Order(StringComparer.Ordinal), endpoints.Keys.Order(StringComparer.Ordinal));
        Assert.Equal(48, endpoints.Count);

        foreach (var route in expectedRoutes.Where(route => route.Contains("/auth/", StringComparison.Ordinal)))
        {
            var endpoint = endpoints[route];
            Assert.NotNull(endpoint.Metadata.GetMetadata<IEndpointSummaryMetadata>());
        }

        foreach (var route in expectedRoutes.Where(route => route.Contains("/tenants/", StringComparison.Ordinal)))
            Assert.NotEmpty(endpoints[route].Metadata.GetOrderedMetadata<IAuthorizeData>());

        foreach (var route in expectedRoutes.Where(route => route.Contains("/onboarding/", StringComparison.Ordinal)))
            Assert.NotEmpty(endpoints[route].Metadata.GetOrderedMetadata<IAuthorizeData>());

        foreach (var route in expectedRoutes.Where(route => route.Contains("/platform/legal-documents", StringComparison.Ordinal)))
            Assert.NotEmpty(endpoints[route].Metadata.GetOrderedMetadata<IAuthorizeData>());

        foreach (var route in expectedRoutes.Where(route =>
                     route.Contains("/platform/registrations", StringComparison.Ordinal) &&
                     !route.EndsWith("/permissions", StringComparison.Ordinal)))
        {
            Assert.NotEmpty(endpoints[route].Metadata.GetOrderedMetadata<IAuthorizeData>());
            var permissionPolicy = endpoints[route].Metadata.GetMetadata<AuthorizationPolicy>();
            Assert.NotNull(permissionPolicy);
            Assert.Contains(permissionPolicy.Requirements.OfType<PlatformPermissionRequirement>(),
                requirement => requirement.PermissionCode == PlatformRegistrationPermissions.Read);
        }
        var registrationPermissionsRoute = endpoints["GET /api/v1/platform/registrations/permissions"];
        Assert.NotEmpty(registrationPermissionsRoute.Metadata.GetOrderedMetadata<IAuthorizeData>());
        Assert.Null(registrationPermissionsRoute.Metadata.GetMetadata<AuthorizationPolicy>());

        foreach (var route in new[]
                 {
                     "GET /api/v1/platform/role-permissions/matrix",
                     "GET /api/v1/platform/role-permissions/history"
                 })
        {
            var policy = endpoints[route].Metadata.GetMetadata<AuthorizationPolicy>();
            Assert.NotNull(policy);
            Assert.Contains(policy.Requirements.OfType<PlatformPermissionRequirement>(),
                requirement => requirement.PermissionCode == RolePermissionMatrixPermissions.Read);
        }

        foreach (var route in new[]
                 {
                     "POST /api/v1/platform/role-permissions/changes/validate",
                     "POST /api/v1/platform/role-permissions/changes"
                 })
        {
            var policy = endpoints[route].Metadata.GetMetadata<AuthorizationPolicy>();
            Assert.NotNull(policy);
            Assert.Contains(policy.Requirements.OfType<PlatformPermissionRequirement>(),
                requirement => requirement.PermissionCode == RolePermissionMatrixPermissions.Update);
        }
        Assert.Null(endpoints["GET /api/v1/platform/role-permissions/access"]
            .Metadata.GetMetadata<AuthorizationPolicy>());

        foreach (var route in expectedRoutes.Where(route => route.Contains("/public/legal/terms", StringComparison.Ordinal)))
            Assert.Empty(endpoints[route].Metadata.GetOrderedMetadata<IAuthorizeData>());

        foreach (var route in expectedRoutes.Where(route => route.EndsWith("/register", StringComparison.Ordinal) ||
                     route.EndsWith("/resend-verification", StringComparison.Ordinal) ||
                     route.EndsWith("/verify-email", StringComparison.Ordinal) ||
                     route.EndsWith("/login", StringComparison.Ordinal) ||
                     route.EndsWith("/refresh", StringComparison.Ordinal)))
        {
            Assert.Contains(endpoints[route].Metadata.GetOrderedMetadata<EnableRateLimitingAttribute>(),
                metadata => metadata.PolicyName == "auth");
        }

        Assert.NotEmpty(endpoints["POST /api/v1/auth/logout"].Metadata.GetOrderedMetadata<IAuthorizeData>());
        Assert.NotEmpty(endpoints["GET /api/v1/auth/me"].Metadata.GetOrderedMetadata<IAuthorizeData>());

        var loginResponses = endpoints["POST /api/v1/auth/login"].Metadata
            .GetOrderedMetadata<IProducesResponseTypeMetadata>()
            .Select(metadata => metadata.StatusCode);
        Assert.Contains(StatusCodes.Status401Unauthorized, loginResponses);
        Assert.Contains(StatusCodes.Status429TooManyRequests, loginResponses);

        var registrationResponses = endpoints["POST /api/v1/auth/register"].Metadata
            .GetOrderedMetadata<IProducesResponseTypeMetadata>()
            .Select(metadata => metadata.StatusCode);
        Assert.Contains(StatusCodes.Status202Accepted, registrationResponses);
        Assert.Contains(StatusCodes.Status400BadRequest, registrationResponses);
        Assert.Contains(StatusCodes.Status429TooManyRequests, registrationResponses);
        Assert.Empty(endpoints["POST /api/v1/auth/register"].Metadata.GetOrderedMetadata<IAuthorizeData>());
        Assert.Equal(typeof(TermsRequiredRegistrationRequest),
            endpoints["POST /api/v1/auth/register"].Metadata.GetMetadata<IAcceptsMetadata>()?.RequestType);
    }

    [Fact]
    public async Task RegistrationEndpointUsesTheDevelopmentContractOnlyWhenBypassIsEnabled()
    {
        foreach (var bypassEnabled in new[] { false, true })
        {
            var builder = WebApplication.CreateBuilder();
            builder.Services.AddHealthChecks();
            builder.Services.AddAuthorization();
            builder.Services.AddSingleton(new KeyMaterial(RSA.Create(3072), "route-contract-test"));
            builder.Services.AddSingleton<IPlatformRepository>(_ => throw new InvalidOperationException());
            builder.Services.AddSingleton<IPlatformRuntimeSettings>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<AuthenticationService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<TenantManagementService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<TenantPermissionDiscoveryService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<LegalTermsService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<LegalDocumentsService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<OnboardingService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<PlatformRegistrationPermissionService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<PlatformRegistrationService>(_ => throw new InvalidOperationException());
            builder.Services.AddScoped<RolePermissionMatrixService>(_ => throw new InvalidOperationException());
            await using var app = builder.Build();
            app.MapPlatformEndpoints(TestSettings(bypassEnabled));

            var endpoint = ((IEndpointRouteBuilder)app).DataSources
                .SelectMany(dataSource => dataSource.Endpoints)
                .OfType<RouteEndpoint>()
                .Single(route => GetRoute(route) == "/api/v1/auth/register");
            var expectedRequestType = bypassEnabled
                ? typeof(DirectRegistrationRequest)
                : typeof(TermsRequiredRegistrationRequest);

            Assert.Equal(expectedRequestType, endpoint.Metadata.GetMetadata<IAcceptsMetadata>()?.RequestType);
        }
    }

    [Fact]
    public async Task RegistrationValidationErrorsMapToTheExistingProblemResponse()
    {
        var settings = new RuntimeSettings("https://issuer.example", "klop-test", "https://app.example", 15, 30,
            5, 12, 24, 30, 30, "smtp.example", 25, "no-reply@example.com", true, null, null, null);
        using var services = new ServiceCollection()
            .AddLogging()
            .AddSingleton<IValidator<RegistrationRequest>>(new RegistrationRequestValidator(settings))
            .BuildServiceProvider();
        var httpContext = new DefaultHttpContext { RequestServices = services };
        httpContext.Request.Path = "/api/v1/auth/register";
        httpContext.Response.Body = new MemoryStream();
        var filterContext = new TestInvocationContext(httpContext,
            new RegistrationRequest("invalid-email", "", ""));
        var nextCalled = false;

        var result = Assert.IsAssignableFrom<IResult>(await new ValidationFilter().InvokeAsync(filterContext, _ =>
        {
            nextCalled = true;
            return ValueTask.FromResult<object?>(null);
        }));
        await result.ExecuteAsync(httpContext);

        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status400BadRequest, httpContext.Response.StatusCode);
        httpContext.Response.Body.Position = 0;
        using var response = await System.Text.Json.JsonDocument.ParseAsync(httpContext.Response.Body);
        Assert.Equal("VALIDATION_FAILED", response.RootElement.GetProperty("title").GetString());
        var errors = response.RootElement.GetProperty("errors");
        Assert.True(errors.TryGetProperty(nameof(RegistrationRequest.Email), out _));
        Assert.True(errors.TryGetProperty(nameof(RegistrationRequest.DisplayName), out _));
        Assert.True(errors.TryGetProperty(nameof(RegistrationRequest.Password), out _));
    }

    private sealed class TestInvocationContext(HttpContext httpContext, params object?[] arguments)
        : EndpointFilterInvocationContext
    {
        public override HttpContext HttpContext { get; } = httpContext;
        public override IList<object?> Arguments { get; } = arguments;
        public override T GetArgument<T>(int index) => (T)Arguments[index]!;
    }

    private static string GetRoute(RouteEndpoint endpoint) => endpoint.RoutePattern.RawText ?? "/" +
        string.Join("/", endpoint.RoutePattern.PathSegments.Select(segment => string.Concat(
            segment.Parts.Select(part => part switch
            {
                RoutePatternLiteralPart literal => literal.Content,
                RoutePatternParameterPart parameter => $"{{{parameter.Name}{string.Concat(parameter.ParameterPolicies.Select(policy => $":{policy.Content}"))}{(parameter.IsOptional ? "?" : "")}}}",
                _ => throw new InvalidOperationException($"Unsupported route pattern part: {part.GetType().Name}.")
            }))));

    private static RuntimeSettings TestSettings(bool developmentTermsBypassEnabled = false) =>
        new("https://issuer.example", "klop-test", "https://app.example", 15, 30,
            5, 12, 24, 30, 30, "smtp.example", 25, "no-reply@example.com", true, null, null, null,
            LegalConsentEnforcement: !developmentTermsBypassEnabled,
            DevelopmentTermsBypassEnabled: developmentTermsBypassEnabled);
}