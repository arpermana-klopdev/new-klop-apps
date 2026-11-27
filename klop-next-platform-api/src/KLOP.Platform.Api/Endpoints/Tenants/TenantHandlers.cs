using KLOP.Platform.Application;
using Microsoft.AspNetCore.Authorization;

namespace KLOP.Platform.Api.Endpoints.Tenants;

public static class TenantHandlers
{
    public static async Task<IResult> Permissions(
        long tenantId,
        HttpContext context,
        TenantPermissionDiscoveryService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        if (tenantId <= 0)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "VALIDATION_FAILED", "Tenant ID is invalid.");
        return ApiHelpers.Success(context,
            await service.Get(identity.Value.UserId, identity.Value.SessionId, tenantId, cancellationToken));
    }

    public static async Task<IResult> ListMine(
        HttpContext context,
        TenantManagementService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context,
            await service.MyTenants(identity.Value.UserId, cancellationToken));
    }

    public static async Task<IResult> Create(
        TenantCreateRequest request,
        HttpContext context,
        TenantManagementService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var result = await service.CreateTenant(identity.Value.UserId, request,
            ApiHelpers.Metadata(context), cancellationToken);
        return ApiHelpers.Success(context, new TenantCreateResult(result.TenantId, result.MembershipId),
            StatusCodes.Status201Created);
    }

    public static async Task<IResult> Invite(
        long tenantId,
        InviteRequest request,
        HttpContext context,
        TenantManagementService service,
        IAuthorizationService authorization,
        CancellationToken cancellationToken)
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
    }

    public static async Task<IResult> AcceptInvitation(
        long membershipId,
        HttpContext context,
        TenantManagementService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        if (membershipId <= 0)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest, "VALIDATION_FAILED", "Membership ID is invalid.");
        await service.Accept(membershipId, identity.Value.UserId, ApiHelpers.Metadata(context), cancellationToken);
        return ApiHelpers.Success(context, new { accepted = true });
    }

    public static async Task<IResult> RemoveMember(
        long tenantId,
        long membershipId,
        HttpContext context,
        TenantManagementService service,
        IAuthorizationService authorization,
        CancellationToken cancellationToken)
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
    }

    public static async Task<IResult> AssignRole(
        long tenantId,
        long membershipId,
        RoleRequest request,
        HttpContext context,
        TenantManagementService service,
        IAuthorizationService authorization,
        CancellationToken cancellationToken)
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
    }

    public static async Task<IResult> RevokeRole(
        long tenantId,
        long membershipId,
        string roleCode,
        HttpContext context,
        TenantManagementService service,
        IAuthorizationService authorization,
        CancellationToken cancellationToken)
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
    }
}