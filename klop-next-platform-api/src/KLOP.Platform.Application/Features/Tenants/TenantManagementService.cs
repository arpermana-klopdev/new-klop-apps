using KLOP.Platform.Domain;

namespace KLOP.Platform.Application;

public sealed class TenantManagementService(IPlatformRepository repository)
{
    public async Task<(long TenantId, long MembershipId)> CreateTenant(long userId, TenantCreateRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var types = await repository.TenantTypes(cancellationToken);
        var tenantType = types.FirstOrDefault(x =>
            string.Equals(x.Code, request.TenantTypeCode.Trim(), StringComparison.OrdinalIgnoreCase));
        if (tenantType is null)
            throw new UnknownTenantTypeException();

        var settingKey = $"registration.{tenantType.Code.ToLowerInvariant()}.enabled";
        var setting = await repository.GetConfiguration(settingKey, cancellationToken);
        if (setting is null || setting.StorageType != "PLAIN" || setting.ValueType != "BOOLEAN" ||
            !bool.TryParse(setting.ConfigurationValue, out var enabled))
            throw new InvalidOperationException($"Required SQL setting '{settingKey}' is missing or invalid.");
        if (!enabled)
            throw new TenantRegistrationDisabledException();

        return await repository.CreateTenant(userId, request.TenantCode.Trim(), tenantType.Code,
            request.DisplayName.Trim(), request.OrganizationTypeId, request.RegisteredName?.Trim(),
            metadata.RequestId, metadata.CorrelationId, cancellationToken);
    }

    public Task<IReadOnlyList<TenantSummary>> MyTenants(long userId, CancellationToken cancellationToken) =>
        repository.MyTenants(userId, cancellationToken);

    public Task<long> Invite(long tenantId, long actorUserId, long inviteeUserId, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.Invite(tenantId, actorUserId, inviteeUserId, metadata.RequestId, metadata.CorrelationId,
            cancellationToken);

    public Task Accept(long membershipId, long actorUserId, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.Accept(membershipId, actorUserId, metadata.RequestId, metadata.CorrelationId, cancellationToken);

    public Task Remove(long membershipId, long actorUserId, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.Remove(membershipId, actorUserId, metadata.RequestId, metadata.CorrelationId, cancellationToken);

    public Task AssignRole(long membershipId, long actorUserId, string roleCode, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.AssignRole(membershipId, actorUserId, roleCode.Trim(), metadata.RequestId,
            metadata.CorrelationId, cancellationToken);

    public Task RevokeRole(long membershipId, long actorUserId, string roleCode, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.RevokeRole(membershipId, actorUserId, roleCode.Trim(), metadata.RequestId,
            metadata.CorrelationId, cancellationToken);
}