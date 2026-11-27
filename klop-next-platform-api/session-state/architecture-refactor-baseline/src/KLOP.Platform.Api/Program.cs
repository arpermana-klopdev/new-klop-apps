using System.Text.Json;
using System.Net;
using System.Threading.RateLimiting;
using FluentValidation;
using KLOP.Platform.Api;
using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using KLOP.Platform.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.Tokens;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Context;

var builder = WebApplication.CreateBuilder(args);
var environment = builder.Environment;

if (!environment.IsDevelopment() && !environment.IsProduction())
    throw new InvalidOperationException("Only Development and Production environments are supported.");
var allowedHosts = builder.Configuration["AllowedHosts"];
if (string.IsNullOrWhiteSpace(allowedHosts) ||
    (environment.IsProduction() && allowedHosts.Split(';').Any(host => host.Trim() == "*")))
    throw new InvalidOperationException("AllowedHosts must be explicitly configured; wildcard hosts are not allowed in Production.");

builder.Host.UseSerilog((context, services, logger) => logger
    .ReadFrom.Configuration(context.Configuration)
    .ReadFrom.Services(services)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Application", "KLOP.Platform.Api")
    .Enrich.WithProperty("Environment", context.HostingEnvironment.EnvironmentName)
    .WriteTo.Console(outputTemplate:
        "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties:j}{NewLine}{Exception}"));

builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 64 * 1024);
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer<BearerSecurityDocumentTransformer>();
    options.AddDocumentTransformer<HealthReadinessDocumentTransformer>();
    options.AddOperationTransformer<BearerSecurityOperationTransformer>();
});
builder.Services.AddValidatorsFromAssemblyContaining<RegistrationRequestValidator>();
var trustedProxyAddresses = builder.Configuration.GetSection("ForwardedHeaders:KnownProxies").Get<string[]>() ?? [];
builder.Services.Configure<ForwardedHeadersOptions>(options =>
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

var bootstrapFactory = new SqlConnectionFactory(builder.Configuration, environment.IsDevelopment());
var settings = await RuntimeSettings.Load(bootstrapFactory);
if (environment.IsProduction() && !settings.SmtpRequireTls)
    throw new InvalidOperationException("SMTP TLS must be enabled in Production.");
builder.Services.AddCors(options => options.AddPolicy("spa", policy =>
    policy.WithOrigins(settings.AllowedOrigin)
        .WithMethods("GET", "POST", "DELETE")
        .WithHeaders("Authorization", "Content-Type", "X-Correlation-Id")
        .AllowCredentials()));

var keyVaultSecrets = new KeyVaultSecrets(builder.Configuration);
var keyMaterial = await KeyMaterial.Load(builder.Configuration, environment, settings, keyVaultSecrets,
    CancellationToken.None);

builder.Services.AddSingleton(settings);
builder.Services.AddSingleton<IPlatformRuntimeSettings>(settings);
builder.Services.AddSingleton<IPasswordPolicy>(settings);
builder.Services.AddSingleton(bootstrapFactory);
builder.Services.AddSingleton(keyVaultSecrets);
builder.Services.AddSingleton<IKeyVaultSecrets>(keyVaultSecrets);
builder.Services.AddSingleton(keyMaterial);
builder.Services.AddSingleton<PasswordCodec>();
builder.Services.AddSingleton<TokenIssuer>();
builder.Services.AddSingleton<IAccessTokenIssuer>(services => services.GetRequiredService<TokenIssuer>());
builder.Services.AddScoped<IPlatformRepository, KlopRepository>();
builder.Services.AddScoped<AuthenticationService>();
builder.Services.AddScoped<TenantManagementService>();
builder.Services.AddTransient<IVerificationEmailSender, SmtpVerificationEmailSender>();
builder.Services.AddScoped<IAuthorizationHandler, TenantPermissionHandler>();
builder.Services.AddHealthChecks().AddCheck<SqlServerReadinessCheck>("sql-server", tags: ["ready"]);

var openTelemetry = builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("KLOP.Platform.Api"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(options => options.RecordException = false)
        .AddHttpClientInstrumentation(options => options.RecordException = false)
        .AddSqlClientInstrumentation(options => options.RecordException = false))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation());

if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
{
    openTelemetry.WithTracing(tracing => tracing.AddOtlpExporter());
    openTelemetry.WithMetrics(metrics => metrics.AddOtlpExporter());
}

builder.Services.AddRateLimiter(options =>
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
                var identity = ApiHelpers.Identity(context.HttpContext);
                if (identity is null)
                {
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
                    context.Fail("Inactive session.");
                }
            },
            OnChallenge = async context =>
            {
                context.HandleResponse();
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

var app = builder.Build();

app.UseForwardedHeaders();
app.Use(async (context, next) =>
{
    var correlationId = Guid.TryParse(context.Request.Headers["X-Correlation-Id"], out var supplied)
        ? supplied
        : Guid.NewGuid();
    context.Items[ApiHelpers.CorrelationItemKey] = correlationId;
    context.TraceIdentifier = correlationId.ToString("D");
    context.Response.OnStarting(() =>
    {
        context.Response.Headers["X-Correlation-Id"] = correlationId.ToString("D");
        return Task.CompletedTask;
    });

    using (LogContext.PushProperty("CorrelationId", correlationId))
    using (LogContext.PushProperty("TraceId", System.Diagnostics.Activity.Current?.TraceId.ToString()))
    {
        await next();
    }
});

app.Use(async (context, next) =>
{
    try
    {
        await next();
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
    {
        throw;
    }
    catch (TenantRegistrationDisabledException)
    {
        await ApiHelpers.Error(context, StatusCodes.Status403Forbidden,
            "REGISTRATION_DISABLED", "Tenant registration is disabled.").ExecuteAsync(context);
    }
    catch (UnknownTenantTypeException)
    {
        await ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
            "INVALID_TENANT_TYPE", "Tenant type is not available.").ExecuteAsync(context);
    }
    catch (SqlException exception)
    {
        var mapped = ApiHelpers.MapSql(exception);
        var logger = context.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("Database");
        if (mapped.Status >= StatusCodes.Status500InternalServerError)
            logger.LogError("Database operation failed. SqlErrorNumber={SqlErrorNumber}", exception.Number);
        else
            logger.LogWarning("Database operation rejected. SqlErrorNumber={SqlErrorNumber}", exception.Number);
        if (context.Response.HasStarted)
            throw;
        await ApiHelpers.Error(context, mapped.Status, mapped.Code, mapped.Message).ExecuteAsync(context);
    }
    catch (Exception exception)
    {
        context.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("Request")
            .LogError("Unhandled request failure. FailureType={FailureType}", exception.GetType().Name);
        if (context.Response.HasStarted)
            throw;
        await ApiHelpers.Error(context, StatusCodes.Status500InternalServerError,
            "SERVER_ERROR", "Request could not be completed.").ExecuteAsync(context);
    }
});

app.UseSerilogRequestLogging(options =>
{
    options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
    {
        diagnosticContext.Set("Endpoint", httpContext.GetEndpoint()?.DisplayName ?? "unmatched");
        diagnosticContext.Set("TraceId", System.Diagnostics.Activity.Current?.TraceId.ToString());
    };
});
app.UseStatusCodePages(async statusContext =>
{
    var context = statusContext.HttpContext;
    var status = context.Response.StatusCode;
    var (code, message) = status switch
    {
        StatusCodes.Status404NotFound => ("NOT_FOUND", "The requested resource was not found."),
        StatusCodes.Status405MethodNotAllowed => ("METHOD_NOT_ALLOWED", "The HTTP method is not supported."),
        _ => ("REQUEST_FAILED", "The request could not be completed.")
    };
    await ApiHelpers.Error(context, status, code, message).ExecuteAsync(context);
});
app.Use(async (context, next) =>
{
    context.Response.OnStarting(() =>
    {
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        context.Response.Headers["X-Frame-Options"] = "DENY";
        context.Response.Headers["Referrer-Policy"] = "no-referrer";
        context.Response.Headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()";
        return Task.CompletedTask;
    });
    await next();
});
if (environment.IsProduction())
    app.UseHsts();
app.UseHttpsRedirection();
app.UseRouting();
app.UseCors("spa");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

if (environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseSwaggerUI(options => options.SwaggerEndpoint("../openapi/v1.json", "KLOP Platform API v1"));
}

app.MapGet("/health/live", () => Results.Json(new { status = "live" }))
    .AllowAnonymous()
    .WithTags("Health")
    .WithSummary("Check process liveness")
    .Produces<HealthResponse>();
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready"),
    ResultStatusCodes =
    {
        [Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Healthy] = StatusCodes.Status200OK,
        [Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Degraded] = StatusCodes.Status503ServiceUnavailable,
        [Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
    },
    ResponseWriter = async (context, report) =>
    {
        context.Response.ContentType = "application/json";
        await JsonSerializer.SerializeAsync(context.Response.Body,
            new { status = report.Status.ToString().ToLowerInvariant() },
            cancellationToken: context.RequestAborted);
    }
}).AllowAnonymous().WithTags("Health");
app.MapGet("/.well-known/jwks.json", (KeyMaterial key) => Results.Json(key.PublicJwks()))
    .AllowAnonymous()
    .WithTags("Authentication")
    .WithSummary("Get public signing keys")
    .Produces<JwksResponse>();

var api = app.MapGroup("/api/v1")
    .AddEndpointFilter<ValidationFilter>();

api.MapGet("/master/organization-types", async (
    HttpContext context,
    IPlatformRepository repository,
    CancellationToken cancellationToken) =>
    ApiHelpers.Success(context, await repository.OrganizationTypes(cancellationToken)))
    .WithTags("Master Data")
    .WithSummary("List organization types")
    .Produces<ApiEnvelope<IReadOnlyList<OrganizationType>>>();

var auth = api.MapGroup("/auth").WithTags("Authentication");
auth.MapPost("/register", async (
    RegistrationRequest request,
    HttpContext context,
    AuthenticationService service,
    CancellationToken cancellationToken) =>
{
    await service.Register(request, ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context,
        new { message = "If accepted, verification instructions will be emailed." },
        StatusCodes.Status202Accepted);
}).RequireRateLimiting("auth")
    .WithSummary("Register a local user")
    .WithDescription("If accepted, email verification instructions are sent without disclosing account existence.")
    .Produces<ApiEnvelope<MessageResponse>>(StatusCodes.Status202Accepted)
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status429TooManyRequests);

auth.MapPost("/resend-verification", async (
    ResendVerificationRequest request,
    HttpContext context,
    AuthenticationService service,
    CancellationToken cancellationToken) =>
{
    await service.ResendVerification(request, ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context,
        new { message = "If eligible, verification instructions will be emailed." },
        StatusCodes.Status202Accepted);
}).RequireRateLimiting("auth")
    .WithSummary("Resend email verification instructions")
    .Produces<ApiEnvelope<MessageResponse>>(StatusCodes.Status202Accepted)
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status429TooManyRequests);

auth.MapPost("/verify-email", async (
    VerifyEmailRequest request,
    HttpContext context,
    AuthenticationService service,
    CancellationToken cancellationToken) =>
{
    await service.ConfirmEmail(request, ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context, new { verified = true });
}).RequireRateLimiting("auth")
    .WithSummary("Verify an email address")
    .Produces<ApiEnvelope<VerifiedResponse>>()
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status429TooManyRequests);

auth.MapPost("/login", async (
    LoginRequest request,
    HttpContext context,
    AuthenticationService service,
    CancellationToken cancellationToken) =>
{
    var session = await service.Login(request, ApiHelpers.Metadata(context), cancellationToken);
    if (session is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized,
            "INVALID_CREDENTIALS", "Email or password is incorrect.");
    RefreshCookies.Set(context.Response, session);
    return ApiHelpers.Success(context, session.Access);
}).RequireRateLimiting("auth")
    .WithSummary("Log in")
    .WithDescription("Returns an access token and sets the refresh cookie for an eligible account.")
    .Produces<ApiEnvelope<AccessResult>>()
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status429TooManyRequests);

auth.MapPost("/refresh", async (
    HttpContext context,
    AuthenticationService service,
    IPlatformRuntimeSettings runtimeSettings,
    CancellationToken cancellationToken) =>
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
}).RequireRateLimiting("auth")
    .WithSummary("Refresh an access token")
    .WithDescription("Requires the refresh cookie and the configured Origin header; does not require a bearer token.")
    .Produces<ApiEnvelope<AccessResult>>()
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status403Forbidden)
    .ProducesProblem(StatusCodes.Status429TooManyRequests);

auth.MapPost("/logout", async (
    HttpContext context,
    AuthenticationService service,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    await service.Logout(identity.Value.UserId, identity.Value.SessionId,
        ApiHelpers.Metadata(context), cancellationToken);
    RefreshCookies.Clear(context.Response);
    return ApiHelpers.Success(context, new { loggedOut = true });
}).RequireAuthorization()
    .WithSummary("Log out the current session")
    .Produces<ApiEnvelope<LoggedOutResponse>>()
    .ProducesProblem(StatusCodes.Status401Unauthorized);

auth.MapGet("/me", async (
    HttpContext context,
    AuthenticationService service,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    var profile = await service.GetProfile(identity.Value.UserId, cancellationToken);
    return profile is null
        ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "NOT_FOUND", "User unavailable.")
        : ApiHelpers.Success(context, profile);
}).RequireAuthorization()
    .WithSummary("Get the current user profile")
    .Produces<ApiEnvelope<Profile>>()
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status404NotFound);

var tenants = api.MapGroup("/tenants")
    .RequireAuthorization()
    .WithTags("Tenants");
tenants.MapGet("/mine", async (
    HttpContext context,
    TenantManagementService service,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    return ApiHelpers.Success(context,
        await service.MyTenants(identity.Value.UserId, cancellationToken));
}).WithSummary("List the current user's tenants")
    .Produces<ApiEnvelope<IReadOnlyList<TenantSummary>>>()
    .ProducesProblem(StatusCodes.Status401Unauthorized);

tenants.MapPost("/", async (
    TenantCreateRequest request,
    HttpContext context,
    TenantManagementService service,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    var result = await service.CreateTenant(identity.Value.UserId, request,
        ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context, new TenantCreateResult(result.TenantId, result.MembershipId),
        StatusCodes.Status201Created);
}).WithSummary("Create a tenant")
    .WithDescription("Creates a tenant with the authenticated user as owner; registration settings are enforced.")
    .Produces<ApiEnvelope<TenantCreateResult>>(StatusCodes.Status201Created)
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status403Forbidden);

tenants.MapPost("/{tenantId:long}/invitations", async (
    long tenantId,
    InviteRequest request,
    HttpContext context,
    TenantManagementService service,
    IAuthorizationService authorization,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    if (tenantId <= 0)
        return ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "VALIDATION_FAILED", "Tenant ID is invalid.");
    if (!await ApiHelpers.Can(context, authorization, tenantId, "tenant.members.invite"))
        return ApiHelpers.Error(context, StatusCodes.Status403Forbidden, "FORBIDDEN", "Permission denied.");
    var membershipId = await service.Invite(tenantId, identity.Value.UserId, request.InviteeUserId,
        ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context, new { membershipId }, StatusCodes.Status201Created);
}).WithSummary("Invite an existing user")
    .WithDescription("Requires the tenant.members.invite permission for the tenant.")
    .Produces<ApiEnvelope<MembershipIdResponse>>(StatusCodes.Status201Created)
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status403Forbidden);

tenants.MapPost("/memberships/{membershipId:long}/accept", async (
    long membershipId,
    HttpContext context,
    TenantManagementService service,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    if (membershipId <= 0)
        return ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "VALIDATION_FAILED", "Membership ID is invalid.");
    await service.Accept(membershipId, identity.Value.UserId, ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context, new { accepted = true });
}).WithSummary("Accept a tenant invitation")
    .Produces<ApiEnvelope<AcceptedResponse>>()
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status401Unauthorized);

tenants.MapDelete("/{tenantId:long}/memberships/{membershipId:long}", async (
    long tenantId,
    long membershipId,
    HttpContext context,
    TenantManagementService service,
    IAuthorizationService authorization,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    if (tenantId <= 0 || membershipId <= 0)
        return ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "VALIDATION_FAILED", "Tenant or membership ID is invalid.");
    if (!await ApiHelpers.Can(context, authorization, tenantId, "tenant.members.remove"))
        return ApiHelpers.Error(context, StatusCodes.Status403Forbidden, "FORBIDDEN", "Permission denied.");
    await service.Remove(membershipId, identity.Value.UserId, ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context, new { removed = true });
}).WithSummary("Remove a tenant member")
    .WithDescription("Requires the tenant.members.remove permission for the tenant.")
    .Produces<ApiEnvelope<RemovedResponse>>()
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status403Forbidden);

tenants.MapPost("/{tenantId:long}/memberships/{membershipId:long}/roles", async (
    long tenantId,
    long membershipId,
    RoleRequest request,
    HttpContext context,
    TenantManagementService service,
    IAuthorizationService authorization,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    if (tenantId <= 0 || membershipId <= 0)
        return ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "VALIDATION_FAILED", "Tenant or membership ID is invalid.");
    if (!await ApiHelpers.Can(context, authorization, tenantId, "tenant.roles.assign"))
        return ApiHelpers.Error(context, StatusCodes.Status403Forbidden, "FORBIDDEN", "Permission denied.");
    await service.AssignRole(membershipId, identity.Value.UserId, request.RoleCode,
        ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context, new { assigned = true });
}).WithSummary("Assign a tenant role")
    .WithDescription("Requires the tenant.roles.assign permission for the tenant.")
    .Produces<ApiEnvelope<AssignedResponse>>()
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status403Forbidden);

tenants.MapDelete("/{tenantId:long}/memberships/{membershipId:long}/roles/{roleCode}", async (
    long tenantId,
    long membershipId,
    string roleCode,
    HttpContext context,
    TenantManagementService service,
    IAuthorizationService authorization,
    CancellationToken cancellationToken) =>
{
    var identity = ApiHelpers.Identity(context);
    if (identity is null)
        return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
    if (tenantId <= 0 || membershipId <= 0 || string.IsNullOrWhiteSpace(roleCode) || roleCode.Length > 50)
        return ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "VALIDATION_FAILED", "Tenant, membership, or role is invalid.");
    if (!await ApiHelpers.Can(context, authorization, tenantId, "tenant.roles.assign"))
        return ApiHelpers.Error(context, StatusCodes.Status403Forbidden, "FORBIDDEN", "Permission denied.");
    await service.RevokeRole(membershipId, identity.Value.UserId, roleCode,
        ApiHelpers.Metadata(context), cancellationToken);
    return ApiHelpers.Success(context, new { revoked = true });
}).WithSummary("Revoke a tenant role")
    .WithDescription("Requires the tenant.roles.assign permission for the tenant.")
    .Produces<ApiEnvelope<RevokedResponse>>()
    .ProducesProblem(StatusCodes.Status400BadRequest)
    .ProducesProblem(StatusCodes.Status401Unauthorized)
    .ProducesProblem(StatusCodes.Status403Forbidden);

app.Run();

public partial class Program { }
