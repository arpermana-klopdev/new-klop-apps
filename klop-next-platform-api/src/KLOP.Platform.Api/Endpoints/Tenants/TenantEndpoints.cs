using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Tenants;

public static class TenantEndpoints
{
    public static void MapTenantEndpoints(RouteGroupBuilder api)
    {
        var tenants = api.MapGroup("/tenants")
            .RequireAuthorization()
            .WithTags("Tenants");
        tenants.MapGet("/{tenantId:long}/permissions", TenantHandlers.Permissions)
            .WithSummary("Get the authenticated user's effective permissions for a tenant")
            .Produces<ApiEnvelope<TenantPermissionsResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        tenants.MapGet("/mine", TenantHandlers.ListMine)
            .WithSummary("List the current user's tenants")
            .Produces<ApiEnvelope<IReadOnlyList<TenantSummary>>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized);

        tenants.MapPost("/", TenantHandlers.Create)
            .WithSummary("Create a tenant")
            .WithDescription("Creates a tenant with the authenticated user as owner; registration settings are enforced.")
            .Produces<ApiEnvelope<TenantCreateResult>>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        tenants.MapPost("/{tenantId:long}/invitations", TenantHandlers.Invite)
            .WithSummary("Invite an existing user")
            .WithDescription("Requires the tenant.members.invite permission for the tenant.")
            .Produces<ApiEnvelope<MembershipIdResponse>>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        tenants.MapPost("/memberships/{membershipId:long}/accept", TenantHandlers.AcceptInvitation)
            .WithSummary("Accept a tenant invitation")
            .Produces<ApiEnvelope<AcceptedResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized);

        tenants.MapDelete("/{tenantId:long}/memberships/{membershipId:long}", TenantHandlers.RemoveMember)
            .WithSummary("Remove a tenant member")
            .WithDescription("Requires the tenant.members.remove permission for the tenant.")
            .Produces<ApiEnvelope<RemovedResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        tenants.MapPost("/{tenantId:long}/memberships/{membershipId:long}/roles", TenantHandlers.AssignRole)
            .WithSummary("Assign a tenant role")
            .WithDescription("Requires the tenant.roles.assign permission for the tenant.")
            .Produces<ApiEnvelope<AssignedResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        tenants.MapDelete("/{tenantId:long}/memberships/{membershipId:long}/roles/{roleCode}", TenantHandlers.RevokeRole)
            .WithSummary("Revoke a tenant role")
            .WithDescription("Requires the tenant.roles.assign permission for the tenant.")
            .Produces<ApiEnvelope<RevokedResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);
    }
}