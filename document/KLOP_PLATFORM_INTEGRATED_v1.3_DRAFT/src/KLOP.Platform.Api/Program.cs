using System.Globalization;
using KLOP.Platform.Api;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.Tokens;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;
var env = builder.Environment;
var bootstrapFactory = new SqlConnectionFactory(config);
var settings = await RuntimeSettings.Load(bootstrapFactory);
var material = await KeyMaterial.Load(config, env, settings);
builder.Services.AddSingleton(settings);
builder.Services.AddSingleton(material);
builder.Services.AddSingleton<TokenIssuer>();
builder.Services.AddSingleton<PasswordCodec>();
builder.Services.AddSingleton<SqlConnectionFactory>();
builder.Services.AddScoped<KlopRepository>();
builder.Services.AddTransient<IVerificationEmailSender,SmtpVerificationEmailSender>();
builder.Services.AddCors(o=>o.AddPolicy("spa",p=>p.WithOrigins(settings.AllowedOrigin)
    .WithMethods("GET","POST","DELETE").WithHeaders("Authorization","Content-Type","X-Correlation-Id")
    .AllowCredentials()));
builder.Services.AddRateLimiter(o => {
    o.RejectionStatusCode=429;
    o.AddPolicy("auth",ctx=>RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown", _=>new FixedWindowRateLimiterOptions {
            PermitLimit=8,Window=TimeSpan.FromMinutes(1),QueueLimit=0,AutoReplenishment=true
        }));
});
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o=> {
    o.MapInboundClaims=false;
    o.RequireHttpsMetadata=true;
    o.TokenValidationParameters=new TokenValidationParameters {
        ValidateIssuer=true,ValidIssuer=settings.JwtIssuer,
        ValidateAudience=true,ValidAudience=settings.JwtAudience,
        ValidateIssuerSigningKey=true,IssuerSigningKey=material.SigningKey,
        ValidateLifetime=true,ClockSkew=TimeSpan.FromSeconds(30),
        NameClaimType="sub",RoleClaimType="role"
    };
    o.Events=new JwtBearerEvents {
        OnTokenValidated=async ctx=> {
            var id=ApiHelpers.Identity(ctx.HttpContext);
            if(id is null) {ctx.Fail("Invalid principal");return;}
            try {
                var db=ctx.HttpContext.RequestServices.GetRequiredService<KlopRepository>();
                await db.ValidateSession(id.Value.UserId,id.Value.Sid,null,null,ctx.HttpContext.RequestAborted);
            } catch {ctx.Fail("Inactive session");}
        }
    };
});
builder.Services.AddAuthorization();
var app = builder.Build();
app.Use(async(ctx,next)=>{
    try {await next();}
    catch(SqlException ex) {
        var mapped=ApiHelpers.MapSql(ex);
        // Never log SQL text, procedure parameters, hashes, or verification tokens.
        ctx.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("Database")
            .LogWarning("SQL operation failed, error {SqlErrorNumber}, request {RequestId}",ex.Number,ctx.TraceIdentifier);
        if(!ctx.Response.HasStarted) await ApiHelpers.Error(ctx,mapped.Status,mapped.Code,mapped.Message).ExecuteAsync(ctx);
    }
    catch(Exception ex) {
        ctx.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("Request")
            .LogError("Unhandled failure type {FailureType}, request {RequestId}",ex.GetType().Name,ctx.TraceIdentifier);
        if(!ctx.Response.HasStarted) await ApiHelpers.Error(ctx,500,"SERVER_ERROR","Request could not be completed.").ExecuteAsync(ctx);
    }
});
app.UseHttpsRedirection();
app.UseCors("spa");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapGet("/health/live",()=>Results.Ok(new {status="live"}));
app.MapGet("/health/ready",async (KlopRepository db,CancellationToken ct)=> {
    await db.OrganizationTypes(ct);return Results.Ok(new {status="ready"});
});
app.MapGet("/.well-known/jwks.json",(KeyMaterial keys)=>Results.Json(keys.PublicJwks()));

var api=app.MapGroup("/api/v1");
api.MapGet("/master/organization-types",async(HttpContext ctx,KlopRepository db,CancellationToken ct)=>
    ApiHelpers.Success(ctx,await db.OrganizationTypes(ct)));

var auth=api.MapGroup("/auth");
auth.MapPost("/register", async (RegistrationRequest req,HttpContext ctx,KlopRepository db,
    PasswordCodec hasher,IVerificationEmailSender email,CancellationToken ct)=> {
    if(!UserInput.EmailOkay(req.Email) || string.IsNullOrWhiteSpace(req.DisplayName) || req.DisplayName.Length>150
       || req.Password is null || req.Password.Length<settings.MinPasswordLength || req.Password.Length>128)
        return ApiHelpers.Error(ctx,400,"INVALID_INPUT","Registration details are invalid.");
    var raw=SecretTokens.NewToken();
    var hash=hasher.Hash(req.Password);
    try {
        var result=await db.Register(req.Email.Trim(),req.DisplayName.Trim(),hash,SecretTokens.Sha256(raw),
            ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
        try {await email.Send(req.Email.Trim(),result.UserId,raw,ct);}
        catch(Exception ex) {
            ctx.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("Email")
                .LogWarning("Verification delivery failed: {FailureType}",ex.GetType().Name);
            // Account was already committed. User can request another challenge.
        }
    }
    catch(SqlException ex) when (ex.Number == 52113) { /* deliberate anti-enumeration */ }
    return ApiHelpers.Success(ctx,new { message="If accepted, verification instructions will be emailed." },202);
}).RequireRateLimiting("auth");
auth.MapPost("/resend-verification",async(ResendVerificationRequest req,HttpContext ctx,KlopRepository db,
    IVerificationEmailSender email,CancellationToken ct)=> {
    if(!UserInput.EmailOkay(req.Email)) return ApiHelpers.Error(ctx,400,"INVALID_INPUT","Invalid email.");
    var raw=SecretTokens.NewToken();
    var userId=await db.Resend(req.Email.Trim(),SecretTokens.Sha256(raw),ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    if(userId.HasValue) {
        try {await email.Send(req.Email.Trim(),userId.Value,raw,ct);}
        catch(Exception ex) {
            ctx.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("Email")
                .LogWarning("Resend delivery failed: {FailureType}",ex.GetType().Name);
        }
    }
    return ApiHelpers.Success(ctx,new {message="If eligible, verification instructions will be emailed."},202);
}).RequireRateLimiting("auth");
auth.MapPost("/verify-email",async(VerifyEmailRequest req,HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    if(req.UserId<=0 || req.Token is null || req.Token.Length<32 || req.Token.Length>100)
        return ApiHelpers.Error(ctx,400,"INVALID_INPUT","Invalid verification request.");
    await db.ConfirmEmail(req.UserId,SecretTokens.Sha256(req.Token),ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    return ApiHelpers.Success(ctx,new {verified=true});
}).RequireRateLimiting("auth");
var dummyHash = new PasswordCodec().Hash("DummyPasswordRandomForTimingOnly2026!");
auth.MapPost("/login",async(LoginRequest req,HttpContext ctx,KlopRepository db,PasswordCodec hasher,
    TokenIssuer issuer,CancellationToken ct)=> {
    if(!UserInput.EmailOkay(req.Email) || string.IsNullOrEmpty(req.Password) || req.Password.Length>128)
        return ApiHelpers.Error(ctx,401,"INVALID_CREDENTIALS","Email or password is incorrect.");
    var c=await db.GetLoginCandidate(SecretTokens.NormalizeEmail(req.Email),ct);
    var matched=hasher.Verify(req.Password,c?.PasswordHash ?? dummyHash);
    var allowed=c is not null && matched && c.IsActive && c.EmailVerifiedAtUtc.HasValue &&
        (!c.LockoutUntilUtc.HasValue || c.LockoutUntilUtc.Value<=DateTime.UtcNow);
    if(!allowed) {
        if(c is not null && !matched) await db.RecordLoginFailure(c.UserId,ApiHelpers.Correlation(ctx),ct);
        return ApiHelpers.Error(ctx,401,"INVALID_CREDENTIALS","Email or password is incorrect.");
    }
    var refresh=SecretTokens.NewToken();
    var sid=await db.CreateSession(c!.UserId,SecretTokens.Sha256(refresh),ApiHelpers.Correlation(ctx),ctx.TraceIdentifier,ct);
    RefreshCookies.Set(ctx.Response,sid,refresh,settings.RefreshDays);
    return ApiHelpers.Success(ctx,issuer.Issue(c.UserId,sid));
}).RequireRateLimiting("auth");
auth.MapPost("/refresh",async(HttpContext ctx,KlopRepository db,
    TokenIssuer issuer,CancellationToken ct)=> {
    if(!ApiHelpers.SameOrigin(ctx,settings)) return ApiHelpers.Error(ctx,403,"ORIGIN_DENIED","Origin not permitted.");
    var cookie=RefreshCookies.Read(ctx.Request);
    if(cookie is null) return ApiHelpers.Error(ctx,401,"INVALID_CREDENTIALS","Refresh required.");
    var replacement=SecretTokens.NewToken();
    try {
        var userId=await db.RotateRefresh(cookie.Value.Sid,SecretTokens.Sha256(cookie.Value.Token),
            SecretTokens.Sha256(replacement),ApiHelpers.Correlation(ctx),ct);
        RefreshCookies.Set(ctx.Response,cookie.Value.Sid,replacement,settings.RefreshDays);
        return ApiHelpers.Success(ctx,issuer.Issue(userId,cookie.Value.Sid));
    }
    catch(SqlException ex) when(ex.Number is 52342 or 52343 or 52344 or 52346 or 52347) {
        RefreshCookies.Clear(ctx.Response);
        return ApiHelpers.Error(ctx,401,"INVALID_CREDENTIALS","Refresh not accepted.");
    }
}).RequireRateLimiting("auth");
auth.MapPost("/logout",async(HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null) return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    await db.RevokeSession(id.Value.UserId,id.Value.Sid,ApiHelpers.Correlation(ctx),ct);
    RefreshCookies.Clear(ctx.Response);
    return ApiHelpers.Success(ctx,new {loggedOut=true});
}).RequireAuthorization();
auth.MapGet("/me",async(HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null) return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    var profile=await db.GetProfile(id.Value.UserId,ct);
    return profile is null?ApiHelpers.Error(ctx,404,"NOT_FOUND","User unavailable."):ApiHelpers.Success(ctx,profile);
}).RequireAuthorization();

var tenants=api.MapGroup("/tenants").RequireAuthorization();
tenants.MapGet("/mine",async(HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null)return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    return ApiHelpers.Success(ctx,await db.MyTenants(id.Value.UserId,ct));
});
tenants.MapPost("/",async(TenantCreateRequest req,HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null)return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    if(string.IsNullOrWhiteSpace(req.TenantCode)||req.TenantCode.Length>50||
       string.IsNullOrWhiteSpace(req.TenantTypeCode)||req.TenantTypeCode.Length>50||
       string.IsNullOrWhiteSpace(req.DisplayName)||req.DisplayName.Length>200)
        return ApiHelpers.Error(ctx,400,"INVALID_INPUT","Invalid tenant request.");
    if ((req.TenantTypeCode.Equals("PERSONAL",StringComparison.OrdinalIgnoreCase) && !settings.PersonalEnabled) ||
        (req.TenantTypeCode.Equals("ORGANIZATION",StringComparison.OrdinalIgnoreCase) && !settings.OrganizationEnabled))
        return ApiHelpers.Error(ctx,403,"REGISTRATION_DISABLED","Tenant registration is disabled.");
    var x=await db.CreateTenant(id.Value.UserId,req.TenantCode,req.TenantTypeCode,req.DisplayName,
        req.OrganizationTypeId,req.RegisteredName,ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    return ApiHelpers.Success(ctx,new TenantCreateResult(x.TenantId,x.MembershipId),201);
});
tenants.MapPost("/{tenantId:long}/invitations",async(long tenantId,InviteRequest req,HttpContext ctx,
    KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null)return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    if(!await ApiHelpers.Can(ctx,db,tenantId,"tenant.members.invite",ct))
        return ApiHelpers.Error(ctx,403,"FORBIDDEN","Permission denied.");
    var member=await db.Invite(tenantId,id.Value.UserId,req.InviteeUserId,ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    return ApiHelpers.Success(ctx,new {membershipId=member},201);
});
tenants.MapPost("/memberships/{membershipId:long}/accept",async(long membershipId,HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null)return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    await db.Accept(membershipId,id.Value.UserId,ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    return ApiHelpers.Success(ctx,new {accepted=true});
});
tenants.MapDelete("/{tenantId:long}/memberships/{membershipId:long}",async(long tenantId,long membershipId,
    HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null)return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    if(!await ApiHelpers.Can(ctx,db,tenantId,"tenant.members.remove",ct))
        return ApiHelpers.Error(ctx,403,"FORBIDDEN","Permission denied.");
    await db.Remove(membershipId,id.Value.UserId,ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    return ApiHelpers.Success(ctx,new {removed=true});
});
tenants.MapPost("/{tenantId:long}/memberships/{membershipId:long}/roles",async(long tenantId,long membershipId,
    RoleRequest req,HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null)return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    if(!await ApiHelpers.Can(ctx,db,tenantId,"tenant.roles.assign",ct))
        return ApiHelpers.Error(ctx,403,"FORBIDDEN","Permission denied.");
    if(string.IsNullOrWhiteSpace(req.RoleCode)||req.RoleCode.Length>50)
        return ApiHelpers.Error(ctx,400,"INVALID_INPUT","Invalid role code.");
    await db.AssignRole(membershipId,id.Value.UserId,req.RoleCode,ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    return ApiHelpers.Success(ctx,new {assigned=true});
});
tenants.MapDelete("/{tenantId:long}/memberships/{membershipId:long}/roles/{roleCode}",async(long tenantId,long membershipId,
    string roleCode,HttpContext ctx,KlopRepository db,CancellationToken ct)=> {
    var id=ApiHelpers.Identity(ctx);if(id is null)return ApiHelpers.Error(ctx,401,"UNAUTHORIZED","Login required.");
    if(!await ApiHelpers.Can(ctx,db,tenantId,"tenant.roles.assign",ct))
        return ApiHelpers.Error(ctx,403,"FORBIDDEN","Permission denied.");
    if(string.IsNullOrWhiteSpace(roleCode)||roleCode.Length>50)
        return ApiHelpers.Error(ctx,400,"INVALID_INPUT","Invalid role code.");
    await db.RevokeRole(membershipId,id.Value.UserId,roleCode,ctx.TraceIdentifier,ApiHelpers.Correlation(ctx),ct);
    return ApiHelpers.Success(ctx,new {revoked=true});
});
app.Run();
public partial class Program { }
