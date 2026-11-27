namespace KLOP.Platform.Application;

public interface ITenantPermissionRepository
{
    Task<IReadOnlyList<string>> GetTenantPermissions(long userId, Guid sessionId, long tenantId,
        CancellationToken cancellationToken);
}

public sealed record TenantPermissionsResponse(IReadOnlyList<string> Permissions);

public sealed class TenantPermissionDiscoveryService(ITenantPermissionRepository repository)
{
    public async Task<TenantPermissionsResponse> Get(long userId, Guid sessionId, long tenantId,
        CancellationToken cancellationToken)
    {
        var permissions = await repository.GetTenantPermissions(userId, sessionId, tenantId, cancellationToken);
        return new TenantPermissionsResponse(
            permissions.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray());
    }
}
