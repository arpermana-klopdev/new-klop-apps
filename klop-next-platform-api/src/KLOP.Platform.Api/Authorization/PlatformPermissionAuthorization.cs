using KLOP.Platform.Application;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Routing;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api;

public sealed record PlatformPermissionRequirement(string PermissionCode) : IAuthorizationRequirement;

public sealed class PlatformPermissionHandler(IPlatformPermissionRepository repository)
    : AuthorizationHandler<PlatformPermissionRequirement>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        PlatformPermissionRequirement requirement)
    {
        var httpContext = context.Resource as HttpContext;
        var identity = httpContext is null ? null : ApiHelpers.Identity(httpContext);
        if (identity is null)
            return;

        try
        {
            await repository.ValidatePlatformPermission(identity.Value.UserId, identity.Value.SessionId,
                requirement.PermissionCode, httpContext!.RequestAborted);
            context.Succeed(requirement);
        }
        catch (SqlException exception) when (exception.Number == 52332)
        {
            context.Fail();
        }
    }
}

public static class PlatformPermissionEndpointExtensions
{
    public static TBuilder RequirePlatformPermission<TBuilder>(
        this TBuilder builder, string permissionCode)
        where TBuilder : IEndpointConventionBuilder
    {
        var policy = new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .AddRequirements(new PlatformPermissionRequirement(permissionCode))
            .Build();
        builder.RequireAuthorization(policy);
        return builder;
    }
}
