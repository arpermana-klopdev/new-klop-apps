using System.Data;
using Dapper;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public Task<IReadOnlyList<string>> GetTenantPermissions(long userId, Guid sessionId, long tenantId,
        CancellationToken cancellationToken) =>
        Many<string>("iam.usp_GetTenantPermissions",
            Params(("ActorUserId", userId), ("PublicSessionId", sessionId), ("TenantId", tenantId)),
            cancellationToken);

    public Task<IReadOnlyList<TenantSummary>> MyTenants(long userId, CancellationToken cancellationToken) =>
        Many<TenantSummary>("ten.usp_ListMyTenants", Params(("UserId", userId)), cancellationToken);

    public async Task<(long TenantId, long MembershipId)> CreateTenant(long userId, string code, string type,
        string name, long? organizationTypeId, string? registeredName, string requestId, Guid correlationId,
        CancellationToken cancellationToken)
    {
        var parameters = Params(("OwnerUserId", userId), ("TenantCode", code), ("TenantTypeCode", type),
            ("DisplayName", name), ("OrganizationTypeId", organizationTypeId), ("RegisteredName", registeredName),
            ("RequestId", requestId), ("CorrelationId", correlationId));
        parameters.Add("TenantId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        parameters.Add("MembershipId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        await Execute("ten.usp_CreateTenantWithOwner", parameters, cancellationToken);
        return (parameters.Get<long>("TenantId"), parameters.Get<long>("MembershipId"));
    }

    public async Task<long> Invite(long tenantId, long actorUserId, long inviteeUserId, string requestId,
        Guid correlationId, CancellationToken cancellationToken)
    {
        var parameters = Params(("TenantId", tenantId), ("ActorUserId", actorUserId),
            ("InviteeUserId", inviteeUserId), ("RequestId", requestId), ("CorrelationId", correlationId));
        parameters.Add("MembershipId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        await Execute("ten.usp_InviteExistingUser", parameters, cancellationToken);
        return parameters.Get<long>("MembershipId");
    }

    public Task Accept(long membershipId, long actorUserId, string requestId, Guid correlationId,
        CancellationToken cancellationToken) =>
        Execute("ten.usp_AcceptMembership", Params(("MembershipId", membershipId), ("ActorUserId", actorUserId),
            ("RequestId", requestId), ("CorrelationId", correlationId)), cancellationToken);

    public Task Remove(long membershipId, long actorUserId, string requestId, Guid correlationId,
        CancellationToken cancellationToken) =>
        Execute("ten.usp_RemoveTenantMember", Params(("MembershipId", membershipId), ("ActorUserId", actorUserId),
            ("RequestId", requestId), ("CorrelationId", correlationId)), cancellationToken);

    public Task AssignRole(long membershipId, long actorUserId, string roleCode, string requestId,
        Guid correlationId, CancellationToken cancellationToken) =>
        Execute("iam.usp_AssignTenantRole", Params(("MembershipId", membershipId), ("ActorUserId", actorUserId),
            ("RoleCode", roleCode), ("RequestId", requestId), ("CorrelationId", correlationId)), cancellationToken);

    public Task RevokeRole(long membershipId, long actorUserId, string roleCode, string requestId,
        Guid correlationId, CancellationToken cancellationToken) =>
        Execute("iam.usp_RevokeTenantRole", Params(("MembershipId", membershipId), ("ActorUserId", actorUserId),
            ("RoleCode", roleCode), ("RequestId", requestId), ("CorrelationId", correlationId)), cancellationToken);
}