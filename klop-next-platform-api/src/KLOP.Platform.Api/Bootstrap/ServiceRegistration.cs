using System.Net;
using System.Threading.RateLimiting;
using FluentValidation;
using KLOP.Platform.Api;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;

namespace KLOP.Platform.Api.Bootstrap;

public static class ServiceRegistration
{
    public static async Task AddPlatformServicesAsync(this WebApplicationBuilder builder)
    {
        var environment = builder.Environment;
        var configuration = builder.Configuration;
        var services = builder.Services;

        if (!environment.IsDevelopment() && !environment.IsProduction())
            throw new InvalidOperationException("Only Development and Production environments are supported.");
        var allowedHosts = configuration["AllowedHosts"];
        if (string.IsNullOrWhiteSpace(allowedHosts) ||
            (environment.IsProduction() && allowedHosts.Split(';').Any(host => host.Trim() == "*")))
            throw new InvalidOperationException("AllowedHosts must be explicitly configured; wildcard hosts are not allowed in Production.");

        builder.AddPlatformObservability();
        builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 64 * 1024);
        services.AddOpenApi(options =>
        {
            options.AddDocumentTransformer<BearerSecurityDocumentTransformer>();
            options.AddDocumentTransformer<HealthReadinessDocumentTransformer>();
            options.AddOperationTransformer<BearerSecurityOperationTransformer>();
        });
        services.AddValidatorsFromAssemblyContaining<RegistrationRequestValidator>();

        var trustedProxyAddresses = configuration.GetSection("ForwardedHeaders:KnownProxies").Get<string[]>() ?? [];
        services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            options.ForwardLimit = 1;
            foreach (var address in trustedProxyAddresses)
            {
                if (!IPAddress.TryParse(address, out var proxy))
                    throw new InvalidOperationException("ForwardedHeaders:KnownProxies contains an invalid IP address.");
                options.KnownProxies.Add(proxy);
            }
        });

        var developmentTermsBypassEnabled =
            configuration.GetValue<bool>("Registration:DevelopmentTermsBypassEnabled");

        var bootstrapFactory = new SqlConnectionFactory(configuration, environment.IsDevelopment());
        var settings = await RuntimeSettings.Load(bootstrapFactory, developmentTermsBypassEnabled);
        RegistrationPolicyRules.ValidateRuntime(settings, environment.IsDevelopment());
        if (environment.IsProduction() && !settings.SmtpRequireTls)
            throw new InvalidOperationException("SMTP TLS must be enabled in Production.");

        services.AddCors(options => options.AddPolicy("spa", policy =>
            policy.WithOrigins(settings.AllowedOrigin)
                .WithMethods("GET", "POST", "PUT", "DELETE")
                .WithHeaders("Authorization", "Content-Type", "X-Correlation-Id")
                .WithExposedHeaders("X-Correlation-Id")
                .AllowCredentials()));

        var keyVaultSecrets = new KeyVaultSecrets(configuration);
        var keyMaterial = await KeyMaterial.Load(configuration, environment, settings, keyVaultSecrets,
            CancellationToken.None);

        services.AddPlatformInfrastructure(bootstrapFactory, settings, keyVaultSecrets, keyMaterial);
        services.AddSingleton<PasswordCodec>();
        services.AddScoped<AuthenticationService>();
        services.AddScoped<TenantManagementService>();
        services.AddScoped<TenantPermissionDiscoveryService>();
        services.AddScoped<LegalTermsService>();
        services.AddScoped<LegalDocumentsService>();
        services.AddScoped<OnboardingService>();
        services.AddScoped<PlatformRegistrationPermissionService>();
        services.AddScoped<PlatformRegistrationService>();
        services.AddScoped<RolePermissionMatrixService>();
        services.AddScoped<NotificationManagementService>();
        services.AddScoped<SystemConfigurationService>();
        services.AddScoped<IAuthorizationHandler, TenantPermissionHandler>();
        services.AddScoped<IAuthorizationHandler, PlatformPermissionHandler>();
        services.AddHealthChecks().AddCheck<SqlServerReadinessCheck>("sql-server", tags: ["ready"]);

        services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = settings.AuthRequestsPerMinute,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0,
                    AutoReplenishment = true
                }));
            options.OnRejected = async (context, cancellationToken) =>
            {
                context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
                await ApiHelpers.Error(context.HttpContext, StatusCodes.Status429TooManyRequests,
                    "RATE_LIMITED", "Too many requests.").ExecuteAsync(context.HttpContext);
            };
        });

        builder.AddPlatformAuthentication(settings, keyMaterial);
    }
}