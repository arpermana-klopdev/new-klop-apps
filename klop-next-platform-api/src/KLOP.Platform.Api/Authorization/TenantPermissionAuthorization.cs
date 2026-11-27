using KLOP.Platform.Application;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api;

public sealed record TenantPermissionRequirement(long TenantId, string PermissionCode) : IAuthorizationRequirement;

public sealed class TenantPermissionHandler(IPlatformRepository repository)
    : AuthorizationHandler<TenantPermissionRequirement>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        TenantPermissionRequirement requirement)
    {
        var httpContext = context.Resource as HttpContext;
        var identity = httpContext is null ? null : ApiHelpers.Identity(httpContext);
        if (identity is null)
            return;

        try
        {
            await repository.ValidateSession(identity.Value.UserId, identity.Value.SessionId,
                requirement.TenantId, requirement.PermissionCode, httpContext!.RequestAborted);
            context.Succeed(requirement);
        }
        catch (SqlException exception) when (exception.Number is 52331 or 52332 or 52333)
        {
            context.Fail();
        }
    }
}
